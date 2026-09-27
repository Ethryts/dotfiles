local M = {}

local id_counter = 0
local git_root_cache = {}
local git_common_dir_cache = {}

local function trim(value)
  return (value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function M.join(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end
  return table.concat({ ... }, '/'):gsub('/+', '/')
end

function M.normalize(path)
  if not path or path == '' then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

function M.timestamp()
  return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

function M.filename_timestamp()
  return os.date('!%Y%m%dT%H%M%SZ')
end

function M.new_id(prefix)
  id_counter = id_counter + 1
  local uv = vim.uv or vim.loop
  local entropy = table.concat({
    M.timestamp(),
    tostring(uv.hrtime()),
    tostring(uv.os_getpid()),
    tostring(id_counter),
  }, ':')
  local digest = vim.fn.sha256(entropy)
  return string.format('%s_%s', prefix or 'id', digest:sub(1, 20))
end

function M.notify(config, message, level)
  if config.notify ~= false then
    vim.notify(message, level or vim.log.levels.INFO, { title = 'review-comments.nvim' })
  end
end

function M.system(args, opts)
  opts = opts or {}
  local started, process = pcall(vim.system, args, {
    cwd = opts.cwd,
    text = true,
  })
  if not started then
    return { code = -1, stdout = '', stderr = tostring(process) }
  end
  local waited, result = pcall(function()
    return process:wait()
  end)
  if not waited then
    return { code = -1, stdout = '', stderr = tostring(result) }
  end
  return {
    code = result.code,
    stdout = trim(result.stdout),
    stderr = trim(result.stderr),
  }
end

function M.git_root(path)
  local uv = vim.uv or vim.loop
  local candidate = M.normalize(path)
  if not candidate then
    return nil
  end

  local stat = uv.fs_stat(candidate)
  local directory = stat and stat.type == 'directory' and candidate or vim.fs.dirname(candidate)
  if not directory or vim.fn.isdirectory(directory) ~= 1 then
    return nil
  end

  local cached = git_root_cache[directory]
  if cached and vim.fn.isdirectory(cached) == 1 then
    return cached
  end

  local result = M.system({ 'git', '-C', directory, 'rev-parse', '--show-toplevel' })
  if result.code ~= 0 or result.stdout == '' then
    return nil
  end
  local root = M.normalize(result.stdout)
  if root then
    git_root_cache[directory] = root
  end
  return root
end

function M.git_common_dir(root)
  local cached = git_common_dir_cache[root]
  if cached and vim.fn.isdirectory(cached) == 1 then
    return cached
  end
  local result = M.system({
    'git',
    '-C',
    root,
    'rev-parse',
    '--path-format=absolute',
    '--git-common-dir',
  })
  if result.code == 0 and result.stdout ~= '' then
    local common = M.normalize(result.stdout)
    git_common_dir_cache[root] = common
    return common
  end

  result = M.system({ 'git', '-C', root, 'rev-parse', '--git-common-dir' })
  if result.code ~= 0 or result.stdout == '' then
    return nil
  end
  if vim.startswith(result.stdout, '/') then
    local common = M.normalize(result.stdout)
    git_common_dir_cache[root] = common
    return common
  end
  local common = M.normalize(M.join(root, result.stdout))
  git_common_dir_cache[root] = common
  return common
end

function M.clear_git_cache()
  git_root_cache = {}
  git_common_dir_cache = {}
end

--- Capture immutable Git provenance for a newly-created review session.
--- Missing fields are intentionally omitted for unborn or detached branches.
--- @param root string
--- @return {commit?: string, branch?: string}
function M.git_session_context(root)
  local context = vim.empty_dict()
  local commit = M.system({ 'git', '-C', root, 'rev-parse', '--verify', 'HEAD' })
  if commit.code == 0 and commit.stdout ~= '' then
    context.commit = commit.stdout
  end
  local branch = M.system({ 'git', '-C', root, 'symbolic-ref', '--quiet', '--short', 'HEAD' })
  if branch.code == 0 and branch.stdout ~= '' then
    context.branch = branch.stdout
  end
  return context
end

function M.sha256(content)
  return vim.fn.sha256(content)
end

--- Check whether a configured register can actually reach a system clipboard.
--- Ordinary Vim registers are always local to Neovim. The `+` and `*`
--- registers silently accept setreg() calls when no clipboard provider exists,
--- so pcall(setreg) alone cannot establish that a copy succeeded.
--- @param register string
--- @return boolean available
--- @return string? error
--- @return string? provider
function M.clipboard_available(register)
  if register ~= '+' and register ~= '*' then
    return true
  end

  local ok, provider = pcall(vim.fn['provider#clipboard#Executable'])
  if ok and type(provider) == 'string' and provider ~= '' then
    return true, nil, provider
  end

  local detail
  local error_ok, provider_error = pcall(vim.fn['provider#clipboard#Error'])
  if error_ok and type(provider_error) == 'string' and provider_error ~= '' then
    detail = provider_error
  elseif not ok then
    detail = tostring(provider)
  else
    detail = 'No clipboard provider is available'
  end
  return false, detail
end

function M.is_within(root, path)
  root = M.normalize(root)
  path = M.normalize(path)
  if not root or not path then
    return false
  end
  return path == root or vim.startswith(path, root .. '/')
end

function M.relative_path(root, path)
  root = M.normalize(root)
  path = M.normalize(path)
  if not root or not path or not M.is_within(root, path) then
    return nil
  end
  if path == root then
    return '.'
  end
  return path:sub(#root + 2)
end

function M.is_safe_relative(path)
  if
    type(path) ~= 'string'
    or path == ''
    or path:sub(1, 1) == '/'
    or path:find('%z')
    or path:find('[\r\n]')
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

function M.read_file(path)
  local file, err = io.open(path, 'rb')
  if not file then
    return nil, err
  end
  local content = file:read('*a')
  file:close()
  return content
end

function M.ensure_directory(path)
  local ok = vim.fn.mkdir(path, 'p')
  if ok == 0 and vim.fn.isdirectory(path) ~= 1 then
    return false, 'Could not create directory: ' .. path
  end
  return true
end

function M.encode_json(value)
  local ok, encoded = pcall(vim.json.encode, value, { indent = true, sort_keys = true })
  if ok then
    return encoded
  end
  return vim.json.encode(value)
end

function M.write_atomic(path, content)
  local directory = vim.fs.dirname(path)
  local ok, err = M.ensure_directory(directory)
  if not ok then
    return false, err
  end

  local temporary = string.format('%s.tmp.%s', path, M.new_id('write'))
  local file, open_err = io.open(temporary, 'wb')
  if not file then
    return false, open_err
  end

  local write_ok, write_err = file:write(content)
  local close_ok, close_err = file:close()
  if not write_ok or not close_ok then
    os.remove(temporary)
    return false, write_err or close_err
  end

  local uv = vim.uv or vim.loop
  local renamed, rename_err = uv.fs_rename(temporary, path)
  if not renamed then
    os.remove(temporary)
    return false, rename_err
  end
  return true
end

function M.unique_path(path)
  local uv = vim.uv or vim.loop
  if not uv.fs_stat(path) then
    return path
  end
  local stem, extension = path:match('^(.*)(%.[^./]+)$')
  stem = stem or path
  extension = extension or ''
  local index = 2
  while uv.fs_stat(string.format('%s-%d%s', stem, index, extension)) do
    index = index + 1
  end
  return string.format('%s-%d%s', stem, index, extension)
end

local function normalized_resolved(path)
  if not path or path == '' then
    return nil
  end
  return M.normalize(vim.fn.resolve(path))
end

local function buffer_sha256(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return M.sha256(table.concat(lines, '\n'))
end

local function difftool_source(root, difftool, bufnr)
  local expected = normalized_resolved(M.join(root, difftool.file))
  local side_path = difftool.view == 'left' and difftool.left or difftool.right
  local actual = normalized_resolved(side_path)
  if expected and actual and expected == actual then
    return { kind = 'worktree' }
  end
  return {
    kind = 'snapshot',
    side = difftool.view,
    content_sha256 = buffer_sha256(bufnr),
  }
end

function M.current_difftool_target(bufnr)
  local info = vim.fn.getqflist({ idx = 0, items = 1, title = 1 })
  if not info.items or not info.idx or info.idx < 1 then
    return nil
  end

  local item = info.items[info.idx]
  local data = item and item.user_data
  if type(data) ~= 'table' or data.diff ~= true or not M.is_safe_relative(data.rel) then
    return nil
  end

  local buffer_path = normalized_resolved(vim.api.nvim_buf_get_name(bufnr))
  local left = normalized_resolved(data.left)
  local right = normalized_resolved(data.right)
  local view
  if buffer_path and left and buffer_path == left then
    view = 'left'
  elseif buffer_path and right and buffer_path == right then
    view = 'right'
  else
    return nil
  end

  return {
    file = data.rel,
    view = view,
    left = data.left,
    right = data.right,
    title = info.title,
  }
end

local function configured_root(config, ctx)
  local value = config.repository_root
  if type(value) == 'function' then
    value = value(ctx)
  end
  if type(value) == 'string' and value ~= '' then
    return M.git_root(value)
  end
  return nil
end

function M.resolve_target(bufnr, config)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, 'The selected buffer is no longer valid'
  end

  local buffer_path = M.normalize(vim.api.nvim_buf_get_name(bufnr))
  local ctx = {
    bufnr = bufnr,
    buffer_path = buffer_path,
    cwd = M.normalize(vim.fn.getcwd()),
    difftool = M.current_difftool_target(bufnr),
  }

  if type(config.resolve_target) == 'function' then
    local ok, custom = pcall(config.resolve_target, ctx)
    if not ok then
      return nil, 'resolve_target failed: ' .. tostring(custom)
    end
    if custom ~= nil then
      if
        type(custom) ~= 'table'
        or type(custom.root) ~= 'string'
        or not M.is_safe_relative(custom.file)
      then
        return nil, 'resolve_target must return { root = ..., file = ... }'
      end
      custom.root = M.git_root(custom.root)
      if not custom.root then
        return nil, 'resolve_target returned a root outside a Git repository'
      end
      custom.source = custom.source or { kind = 'worktree' }
      custom.buffer_path = buffer_path
      return custom
    end
  end

  if ctx.difftool then
    local root = configured_root(config, ctx)
      or M.git_root(ctx.difftool.right)
      or M.git_root(ctx.difftool.left)
      or M.git_root(ctx.cwd)
    if root then
      return {
        root = root,
        file = ctx.difftool.file,
        view = ctx.difftool.view,
        source = difftool_source(root, ctx.difftool, bufnr),
        buffer_path = buffer_path,
        difftool = true,
      }
    end
    return nil, 'Could not resolve the Git repository for this DiffTool buffer'
  end

  if buffer_path then
    local root = M.git_root(buffer_path)
    local relative = root and M.relative_path(root, buffer_path)
    if root and relative then
      return {
        root = root,
        file = relative,
        source = { kind = 'worktree' },
        buffer_path = buffer_path,
      }
    end
  end

  return nil, 'Review comments require a file inside a Git repository'
end

return M
