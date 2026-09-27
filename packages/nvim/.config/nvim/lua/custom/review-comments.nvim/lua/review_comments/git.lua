local util = require('review_comments.util')

local M = {}

local function trim(value)
  return (value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function command_error(action, result)
  local detail = trim(result.stderr)
  if detail == '' then
    detail = string.format('git exited with status %s', tostring(result.code))
  end
  return string.format('%s: %s', action, detail)
end

local function normalized_root(root)
  if type(root) ~= 'string' or root == '' or root:find('%z') then
    return nil, 'Git repository root must be a non-empty path'
  end
  local normalized = util.normalize(root)
  if not normalized or vim.fn.isdirectory(normalized) ~= 1 then
    return nil, 'Git repository root is not a directory'
  end
  return normalized
end

local function run(root, args)
  local normalized, root_err = normalized_root(root)
  if not normalized then
    return nil, root_err
  end

  local command = { 'git', '-C', normalized }
  vim.list_extend(command, args)
  local ok, process = pcall(vim.system, command)
  if not ok then
    return nil, 'Could not start git: ' .. tostring(process)
  end
  local waited, result = pcall(function()
    return process:wait()
  end)
  if not waited then
    return nil, 'Could not wait for git: ' .. tostring(result)
  end
  return result
end

local function unsupported_end_of_options(result)
  local stderr = (result.stderr or ''):lower()
  return stderr:find('end%-of%-options') ~= nil
    and (
      stderr:find('unknown option') ~= nil
      or stderr:find('unrecognized option') ~= nil
      or stderr:find('unknown switch') ~= nil
    )
end

local function full_object_id(value)
  value = trim(value)
  if value:match('^[0-9a-fA-F]+$') and (#value == 40 or #value == 64) then
    return value:lower()
  end
  return nil
end

local function safe_relative(path)
  if
    not util.is_safe_relative(path)
    or path:find('%z')
    or path:find('\\', 1, true)
    or path:match('^%a:')
    or path:find('//', 1, true)
    or path:sub(-1) == '/'
  then
    return false
  end
  for part in path:gmatch('[^/]+') do
    if part == '.' or part == '..' then
      return false
    end
  end
  return true
end

local function nul_fields(output)
  local fields = {}
  local offset = 1
  while offset <= #output do
    local boundary = output:find('\0', offset, true)
    if not boundary then
      return nil, 'Git returned malformed NUL-delimited output'
    end
    fields[#fields + 1] = output:sub(offset, boundary - 1)
    offset = boundary + 1
  end
  return fields
end

--- Resolve a revision expression to a full commit object ID.
---
--- The revision is always passed as one argv entry. Modern Git receives
--- `--end-of-options`; the compatibility path rejects option-like revisions
--- before invoking older Git versions without that guard.
--- @param root string
--- @param ref string
--- @return string? commit
--- @return string? error
function M.resolve_commit(root, ref)
  if type(ref) ~= 'string' or ref == '' or ref:find('[%z\r\n]') then
    return nil, 'Git revision must be a non-empty single-line string'
  end

  local revision = ref .. '^{commit}'
  local result, run_err = run(root, { 'rev-parse', '--verify', '--end-of-options', revision })
  if not result then
    return nil, run_err
  end

  if result.code ~= 0 and unsupported_end_of_options(result) then
    if ref:sub(1, 1) == '-' then
      return nil, 'Option-like Git revisions require support for --end-of-options'
    end
    result, run_err = run(root, { 'rev-parse', '--verify', revision })
    if not result then
      return nil, run_err
    end
  end

  if result.code ~= 0 then
    return nil, command_error(string.format('Could not resolve Git revision %q', ref), result)
  end
  local commit = full_object_id(result.stdout or '')
  if not commit then
    return nil, 'Git returned an invalid commit object ID'
  end
  return commit
end

--- Build immutable scope metadata for a review of a Git diff.
--- @param root string
--- @param base_ref string
--- @return table? scope
--- @return string? error
function M.session_scope(root, base_ref)
  local base, base_err = M.resolve_commit(root, base_ref)
  if not base then
    return nil, base_err
  end

  local target = { kind = 'worktree' }
  local head = M.resolve_commit(root, 'HEAD')
  if head then
    target.head_commit_at_start = head
  end

  local branch, branch_err = run(root, { 'symbolic-ref', '--quiet', '--short', 'HEAD' })
  if not branch then
    return nil, branch_err
  end
  if branch.code == 0 then
    local name = trim(branch.stdout)
    if name ~= '' then
      target.branch_at_start = name
    end
  elseif branch.code ~= 1 then
    return nil, command_error('Could not inspect the current Git branch', branch)
  end

  return {
    kind = 'git_diff',
    base = {
      requested = base_ref,
      commit = base,
    },
    target = target,
  }
end

--- Find renames between a commit and the current index/worktree.
--- @param root string
--- @param base_commit string commit ID or revision expression
--- @return table? map old path to `{ new = string, score = integer }`
--- @return string? error
function M.rename_map(root, base_commit)
  local commit, commit_err = M.resolve_commit(root, base_commit)
  if not commit then
    return nil, commit_err
  end

  local result, run_err = run(root, {
    'diff',
    '--no-ext-diff',
    '--no-textconv',
    '--find-renames=50%',
    '--diff-filter=R',
    '--name-status',
    '-z',
    commit,
    '--',
  })
  if not result then
    return nil, run_err
  end
  if result.code ~= 0 then
    return nil, command_error('Could not inspect Git renames', result)
  end

  local fields, fields_err = nul_fields(result.stdout or '')
  if not fields then
    return nil, fields_err
  end
  local renames = {}
  local index = 1
  while index <= #fields do
    local status = fields[index]
    local score = status and status:match('^R(%d%d?%d?)$') or nil
    local old_path = fields[index + 1]
    local new_path = fields[index + 2]
    score = score and tonumber(score) or nil
    if
      not score
      or score < 0
      or score > 100
      or not old_path
      or not new_path
      or not safe_relative(old_path)
      or not safe_relative(new_path)
    then
      return nil, 'Git returned an invalid rename record'
    end
    if renames[old_path] and renames[old_path].new ~= new_path then
      return nil, 'Git returned ambiguous rename records for ' .. old_path
    end
    renames[old_path] = { new = new_path, score = score }
    index = index + 3
  end
  return renames
end

--- List current tracked and untracked, non-ignored repository paths.
--- @param root string
--- @return string[]? files
--- @return string? error
function M.files(root)
  local result, run_err = run(root, {
    'ls-files',
    '-z',
    '--cached',
    '--others',
    '--exclude-standard',
    '--',
  })
  if not result then
    return nil, run_err
  end
  if result.code ~= 0 then
    return nil, command_error('Could not list Git files', result)
  end

  local fields, fields_err = nul_fields(result.stdout or '')
  if not fields then
    return nil, fields_err
  end
  local seen = {}
  local paths = {}
  for _, path in ipairs(fields) do
    if not safe_relative(path) then
      return nil, 'Git returned an unsafe repository path'
    end
    if not seen[path] then
      seen[path] = true
      paths[#paths + 1] = path
    end
  end
  table.sort(paths)
  return paths
end

local function repository_has_head_path(root, commit, path)
  -- The full object ID prefix prevents the object expression from being
  -- interpreted as an option; everything after the first colon is a tree path.
  local result, run_err = run(root, { 'cat-file', '-e', commit .. ':' .. path })
  if not result then
    return nil, run_err
  end
  if result.code == 0 then
    return true
  end
  if result.code == 128 then
    return false
  end
  return nil, command_error('Could not inspect the tracked Git path', result)
end

--- Capture the HEAD path which identifies a current worktree file.
---
--- For a unique staged or intent-to-add rename, this reverse-maps the current
--- destination to its path at HEAD. Untracked files intentionally have no
--- commit so callers do not infer history which Git cannot prove.
--- @param root string
--- @param file string repository-relative current path
--- @return table? tracking `{ path = string, commit? = string }`
--- @return string? error
function M.current_tracking(root, file)
  if not safe_relative(file) then
    return nil, 'File must be a safe repository-relative path'
  end

  local probe, probe_err = run(root, { 'rev-parse', '--is-inside-work-tree' })
  if not probe then
    return nil, probe_err
  end
  if probe.code ~= 0 or trim(probe.stdout) ~= 'true' then
    return nil, command_error('Path is not inside a Git worktree', probe)
  end

  local head = M.resolve_commit(root, 'HEAD')
  if not head then
    return { path = file }
  end

  local tracked, tracked_err = repository_has_head_path(root, head, file)
  if tracked == nil then
    return nil, tracked_err
  end
  if tracked then
    return { path = file, commit = head }
  end

  local renames, rename_err = M.rename_map(root, head)
  if not renames then
    return nil, rename_err
  end
  local previous
  local matches = 0
  for old_path, rename in pairs(renames) do
    if rename.new == file then
      previous = old_path
      matches = matches + 1
    end
  end
  if matches == 1 then
    return { path = previous, commit = head }
  end
  return { path = file }
end

return M
