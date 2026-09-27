local model = require('review_comments.model')
local util = require('review_comments.util')

local M = {}
local unpack_values = table.unpack or unpack

function M.paths(root, config)
  local base = util.join(root, config.storage.directory)
  local current = util.join(base, config.storage.current_file)
  return {
    base = base,
    current = current,
    archive = util.join(base, config.storage.archive_directory),
    recovery = util.join(base, config.storage.recovery_directory or 'recovery'),
    lock = current .. '.lock',
  }
end

function M.exists(root, config)
  local paths = M.paths(root, config)
  local uv = vim.uv or vim.loop
  return util.is_within(root, paths.current) and uv.fs_stat(paths.current) ~= nil
end

local function safe_storage_path(root, base)
  if not util.is_within(root, base) then
    return false, 'Review storage must remain inside the Git repository'
  end

  local uv = vim.uv or vim.loop
  local cursor = root
  local relative = util.relative_path(root, base)
  for component in relative:gmatch('[^/]+') do
    cursor = util.join(cursor, component)
    if uv.fs_stat(cursor) then
      local real = uv.fs_realpath(cursor)
      if real and not util.is_within(root, real) then
        return false, 'Review storage resolves outside the Git repository: ' .. cursor
      end
    end
  end
  return true
end

local function safe_storage_paths(root, paths)
  for _, path in pairs(paths) do
    local safe, err = safe_storage_path(root, path)
    if not safe then
      return false, err
    end
  end
  return true
end

local function exclude_pattern(config)
  local directory = config.storage.directory:gsub('\\', '/'):gsub('^%./', '')
  return '/' .. directory:gsub('/+$', '') .. '/'
end

function M.ensure_git_excluded(root, config)
  if config.storage.add_to_git_exclude == false then
    return true
  end

  local common_dir = util.git_common_dir(root)
  if not common_dir then
    return false, 'Could not resolve the Git common directory'
  end

  local info_dir = util.join(common_dir, 'info')
  local exclude_file = util.join(info_dir, 'exclude')
  local pattern = exclude_pattern(config)
  local uv = vim.uv or vim.loop
  local content, read_err = util.read_file(exclude_file)
  if not content and uv.fs_stat(exclude_file) then
    return false, 'Could not read existing Git exclude file: ' .. tostring(read_err)
  end
  content = content or ''

  for line in content:gmatch('[^\r\n]+') do
    if line == pattern then
      return true
    end
  end

  local ok, err = util.ensure_directory(info_dir)
  if not ok then
    return false, err
  end

  if content ~= '' and content:sub(-1) ~= '\n' then
    content = content .. '\n'
  end
  content = content .. pattern .. '\n'
  return util.write_atomic(exclude_file, content)
end

local function new_document(root)
  return model.new_session({ started_from = util.git_session_context(root) })
end

local function token_for(content, schema_version)
  if content == nil then
    return { exists = false }
  end
  return {
    exists = true,
    digest = util.sha256(content),
    schema_version = schema_version,
  }
end

local function read_current(path)
  local uv = vim.uv or vim.loop
  if not uv.fs_stat(path) then
    return nil, nil
  end
  local content, err = util.read_file(path)
  if content == nil then
    return nil, 'Could not read review state: ' .. tostring(err)
  end
  return content
end

local function lock_error(paths)
  return 'Review storage is busy (lock exists at ' .. paths.lock .. ')'
end

local function read_unlocked(paths)
  local uv = vim.uv or vim.loop
  if uv.fs_stat(paths.lock) then
    return nil, lock_error(paths)
  end
  local content, err = read_current(paths.current)
  if err then
    return nil, err
  end
  if uv.fs_stat(paths.lock) then
    return nil, lock_error(paths)
  end
  return content
end

local function decode(content)
  local ok, document = pcall(vim.json.decode, content)
  if not ok then
    return nil, 'Could not decode review state: ' .. tostring(document)
  end
  return document
end

local function tokens_match(expected, actual)
  expected = expected or { exists = false }
  if (expected.exists == true) ~= (actual.exists == true) then
    return false
  end
  return expected.exists ~= true or expected.digest == actual.digest
end

local function with_lock(paths, callback)
  local ok, mkdir_err = util.ensure_directory(paths.base)
  if not ok then
    return false, mkdir_err
  end

  local uv = vim.uv or vim.loop
  local fd, open_err = uv.fs_open(paths.lock, 'wx', 384)
  if not fd then
    return false,
      'Review storage is busy (lock exists at ' .. paths.lock .. '): ' .. tostring(open_err)
  end

  pcall(
    uv.fs_write,
    fd,
    string.format('pid=%s\ncreated_at=%s\n', uv.os_getpid(), util.timestamp()),
    -1
  )

  local values = { n = 0 }
  local call_ok, thrown = xpcall(function()
    local function capture(...)
      values.n = select('#', ...)
      for index = 1, values.n do
        values[index] = select(index, ...)
      end
    end
    capture(callback())
  end, debug.traceback)

  pcall(uv.fs_close, fd)
  pcall(uv.fs_unlink, paths.lock)
  if not call_ok then
    return false, 'Review storage operation failed: ' .. tostring(thrown)
  end
  return true, unpack_values(values, 1, values.n)
end

local function recovery_path(paths, prefix, suffix)
  local name = string.format(
    '%s-%s-%s.json',
    prefix,
    util.filename_timestamp(),
    (suffix or util.new_id('recovery')):gsub('[^%w_-]', '_')
  )
  return util.unique_path(util.join(paths.recovery, name))
end

local function write_recovery(paths, prefix, suffix, content)
  local ok, err = util.ensure_directory(paths.recovery)
  if not ok then
    return nil, err
  end
  local path = recovery_path(paths, prefix, suffix)
  local written, write_err = util.write_atomic(path, content)
  if not written then
    return nil, write_err
  end
  return path
end

local function recover_corrupt(root, paths, content, reason)
  local locked, recovered, recovery_err = with_lock(paths, function()
    local latest, read_err = read_current(paths.current)
    if read_err then
      return nil, read_err
    end
    if latest == nil or util.sha256(latest) ~= util.sha256(content) then
      return nil, 'Review state changed while corruption recovery was starting; retry the operation'
    end
    local ok, mkdir_err = util.ensure_directory(paths.recovery)
    if not ok then
      return nil, mkdir_err
    end
    local path = recovery_path(paths, 'corrupt', util.new_id('state'))
    local uv = vim.uv or vim.loop
    local renamed, rename_err = uv.fs_rename(paths.current, path)
    if not renamed then
      return nil, 'Could not preserve corrupt review state: ' .. tostring(rename_err)
    end
    return path
  end)
  if not locked then
    return nil, recovered
  end
  if not recovered then
    return nil, recovery_err
  end
  return {
    document = new_document(root),
    token = token_for(nil),
    recovered_from = recovered,
    recovery_reason = reason,
  }
end

--- Load, migrate, and validate the current review document.
--- @return {document: table, token: table, migration?: table, recovered_from?: string}? result
--- @return string? error
function M.load(root, config)
  local paths = M.paths(root, config)
  local safe, safe_err = safe_storage_paths(root, paths)
  if not safe then
    return nil, safe_err
  end

  local content, read_err = read_unlocked(paths)
  if read_err then
    return nil, read_err
  end
  if content == nil then
    return { document = new_document(root), token = token_for(nil) }
  end

  local decoded, decode_err = decode(content)
  if not decoded then
    return recover_corrupt(root, paths, content, decode_err)
  end
  if type(decoded.schema_version) == 'number' and decoded.schema_version > model.SCHEMA_VERSION then
    return nil,
      string.format('Unsupported future review schema version: %s', decoded.schema_version)
  end

  local document, migration, upgrade_err = model.upgrade(decoded)
  if not document then
    return recover_corrupt(root, paths, content, upgrade_err)
  end

  local token = token_for(content, decoded.schema_version)
  if migration then
    token.migration_content = content
  end
  return { document = document, token = token, migration = migration }
end

local function normalized_for_comparison(document)
  local value = vim.deepcopy(document)
  value.revision = 0
  if value.session then
    value.session.updated_at = ''
  end
  return value
end

local function unchanged_from_disk(document, content)
  if content == nil then
    return false
  end
  local decoded = decode(content)
  if not decoded or decoded.schema_version ~= model.SCHEMA_VERSION then
    return false
  end
  local disk = model.upgrade(decoded)
  if not disk then
    return false
  end
  return vim.deep_equal(normalized_for_comparison(document), normalized_for_comparison(disk))
end

local function actual_token(content)
  if content == nil then
    return token_for(nil)
  end
  local decoded = decode(content)
  return token_for(content, decoded and decoded.schema_version or nil)
end

--- Check whether an in-memory token still identifies the current on-disk bytes.
--- This is a read-only command-boundary check, not a replacement for save CAS.
--- @return boolean? matches nil when the state cannot be read safely
--- @return string? error
--- @return table? actual_token
function M.check_token(root, config, expected_token)
  local paths = M.paths(root, config)
  local safe, safe_err = safe_storage_paths(root, paths)
  if not safe then
    return nil, safe_err
  end
  local content, read_err = read_unlocked(paths)
  if read_err then
    return nil, read_err
  end
  local current_token = actual_token(content)
  return tokens_match(expected_token, current_token), nil, current_token
end

local function conflict_error(paths, document)
  local encoded = util.encode_json(document) .. '\n'
  local path, err = write_recovery(paths, 'conflict', document.session.id, encoded)
  if not path then
    return 'Review state changed on disk; local changes were not overwritten, but the conflict snapshot failed: '
      .. tostring(err)
  end
  return 'Review state changed on disk; local changes were preserved at ' .. path
end

local function backup_migration(paths, expected_token, document)
  if not expected_token or not expected_token.migration_content then
    return true
  end
  local prefix =
    string.format('pre-migration-v%s', tostring(expected_token.schema_version or 'unknown'))
  local path, err =
    write_recovery(paths, prefix, document.session.id, expected_token.migration_content)
  if not path then
    return false, 'Could not preserve the pre-migration review state: ' .. tostring(err)
  end
  return true
end

local function persist_document(path, document, previous_document)
  local ok, result = xpcall(function()
    local candidate = vim.deepcopy(document)
    candidate.revision = (
      (previous_document and previous_document.revision)
      or candidate.revision
      or 0
    ) + 1
    model.touch(candidate)

    local valid, validation_err = model.validate(candidate)
    if not valid then
      return { error = validation_err }
    end

    local encoded = util.encode_json(candidate) .. '\n'
    local written, write_err = util.write_atomic(path, encoded)
    if not written then
      return { error = write_err }
    end
    return {
      candidate = candidate,
      token = token_for(encoded, model.SCHEMA_VERSION),
    }
  end, debug.traceback)
  if not ok then
    return nil, 'Could not persist review state: ' .. tostring(result)
  end
  if result.error then
    return nil, result.error
  end

  -- Commit storage-managed metadata only after the durable write succeeds.
  document.revision = result.candidate.revision
  document.session.updated_at = result.candidate.session.updated_at
  return result.token
end

--- Compare-and-swap a review document onto disk.
--- @return boolean ok
--- @return string? error
--- @return table? new_token
function M.save(root, document, config, expected_token)
  local paths = M.paths(root, config)
  local safe, safe_err = safe_storage_paths(root, paths)
  if not safe then
    return false, safe_err
  end
  local valid, validation_err = model.validate(document)
  if not valid then
    return false, validation_err
  end

  local excluded, exclude_err = M.ensure_git_excluded(root, config)
  if not excluded then
    util.notify(config, 'Could not update .git/info/exclude: ' .. exclude_err, vim.log.levels.WARN)
  end

  local locked, ok, err, new_token = with_lock(paths, function()
    local content, read_err = read_current(paths.current)
    if read_err then
      return false, read_err
    end
    local current_token = actual_token(content)
    if not tokens_match(expected_token, current_token) then
      return false, conflict_error(paths, document)
    end
    if
      unchanged_from_disk(document, content)
      and (not expected_token or not expected_token.migration_content)
    then
      return true, nil, current_token
    end

    local backed_up, backup_err = backup_migration(paths, expected_token, document)
    if not backed_up then
      return false, backup_err
    end
    local previous = content and decode(content) or nil
    if previous and previous.schema_version ~= model.SCHEMA_VERSION then
      previous = model.upgrade(previous)
    end
    local saved_token, save_err = persist_document(paths.current, document, previous)
    if not saved_token then
      return false, save_err
    end
    return true, nil, saved_token
  end)
  if not locked then
    return false, ok
  end
  return ok, err, new_token
end

--- Atomically verify, archive, and replace the current session.
--- @param opts? {next_document?: table}
--- @return table? next_document
--- @return string? archive_path
--- @return string? error
--- @return table? next_token
function M.archive(root, document, config, expected_token, opts)
  opts = opts or {}
  local paths = M.paths(root, config)
  local safe, safe_err = safe_storage_paths(root, paths)
  if not safe then
    return nil, nil, safe_err
  end
  local valid, validation_err = model.validate(document)
  if not valid then
    return nil, nil, validation_err
  end

  local excluded, exclude_err = M.ensure_git_excluded(root, config)
  if not excluded then
    util.notify(config, 'Could not update .git/info/exclude: ' .. exclude_err, vim.log.levels.WARN)
  end

  local next_document = opts.next_document or new_document(root)
  local next_valid, next_validation_err = model.validate(next_document)
  if not next_valid then
    return nil, nil, next_validation_err
  end
  local locked, next_result, archive_path, operation_err, next_token = with_lock(paths, function()
    local content, read_err = read_current(paths.current)
    if read_err then
      return nil, nil, read_err
    end
    local current_token = actual_token(content)
    if not tokens_match(expected_token, current_token) then
      return nil, nil, conflict_error(paths, document)
    end

    local backed_up, backup_err = backup_migration(paths, expected_token, document)
    if not backed_up then
      return nil, nil, backup_err
    end

    if
      not unchanged_from_disk(document, content)
      or (expected_token and expected_token.migration_content)
    then
      local previous = content and decode(content) or nil
      if previous and previous.schema_version ~= model.SCHEMA_VERSION then
        previous = model.upgrade(previous)
      end
      local saved_token, save_err = persist_document(paths.current, document, previous)
      if not saved_token then
        return nil, nil, save_err
      end
      content = util.read_file(paths.current)
      current_token = saved_token
    elseif content == nil then
      local saved_token, save_err = persist_document(paths.current, document)
      if not saved_token then
        return nil, nil, save_err
      end
      content = util.read_file(paths.current)
      current_token = saved_token
    end

    local mkdir_ok, mkdir_err = util.ensure_directory(paths.archive)
    if not mkdir_ok then
      return nil, nil, mkdir_err, current_token
    end
    local archive_name = string.format(
      '%s-%s.json',
      util.filename_timestamp(),
      document.session.id:gsub('[^%w_-]', '_')
    )
    local target = util.unique_path(util.join(paths.archive, archive_name))
    local uv = vim.uv or vim.loop
    local renamed, rename_err = uv.fs_rename(paths.current, target)
    if not renamed then
      return nil, nil, 'Could not archive current review: ' .. tostring(rename_err), current_token
    end

    local created_token, create_err = persist_document(paths.current, next_document)
    if not created_token then
      local rolled_back, rollback_err = uv.fs_rename(target, paths.current)
      if not rolled_back then
        return nil,
          nil,
          string.format(
            'Could not create the next review session (%s) or restore the archived session (%s)',
            tostring(create_err),
            tostring(rollback_err)
          )
      end
      return nil, nil, create_err, current_token
    end
    return next_document, target, nil, created_token
  end)
  if not locked then
    return nil, nil, next_result
  end
  return next_result, archive_path, operation_err, next_token
end

return M
