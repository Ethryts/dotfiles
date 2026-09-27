local config = require('review_comments.config')
local model = require('review_comments.model')
local storage = require('review_comments.storage')
local util = require('review_comments.util')

local M = {}

local health = vim.health or require('health')

local function current_root()
  local name = vim.api.nvim_buf_get_name(0)
  return util.git_root(name ~= '' and name or vim.fn.getcwd())
end

function M.check()
  health.start('review-comments.nvim')

  local valid, config_err = config.validate(config.options)
  if valid then
    health.ok('Configuration is valid')
  else
    health.error('Configuration is invalid: ' .. tostring(config_err))
  end

  local git_available = vim.fn.executable('git') == 1
  if git_available then
    health.ok('Git is available')
  else
    health.error('Git is required but was not found in PATH')
  end

  local register = config.options.clipboard.register
  local clipboard_ok, clipboard_err, provider = util.clipboard_available(register)
  if clipboard_ok then
    local suffix = provider and ' via ' .. provider or ''
    health.ok(string.format('Clipboard register %q is available%s', register, suffix))
  else
    health.warn(
      string.format('Clipboard register %q is not available: %s', register, tostring(clipboard_err))
    )
  end

  if not git_available then
    return
  end

  local root = current_root()
  if not root then
    health.info('The current buffer is not inside a Git repository')
    return
  end
  health.ok('Repository root: ' .. root)

  local paths = storage.paths(root, config.options)
  local lock = (vim.uv or vim.loop).fs_stat(paths.lock)
  if lock then
    health.warn(
      'A review storage lock exists: '
        .. paths.lock
        .. '. Locks are never deleted automatically; verify that no Neovim process is using '
        .. 'this repository before removing it manually.'
    )
  else
    health.ok('No review storage lock is present')
  end

  local current_stat = (vim.uv or vim.loop).fs_stat(paths.current)
  if not current_stat then
    health.info('No persisted review session exists yet')
    return
  end
  local content, read_err = util.read_file(paths.current)
  if not content then
    health.error('current.json exists but could not be read: ' .. tostring(read_err))
    return
  end
  local decoded_ok, document = pcall(vim.json.decode, content)
  if not decoded_ok then
    health.error(
      'current.json is not valid JSON; the next plugin load will preserve it in recovery/'
    )
    return
  end
  local upgraded, migration, err = model.upgrade(document)
  if not upgraded then
    health.error('Review state is invalid: ' .. tostring(err))
  elseif migration then
    health.warn(
      string.format('Review state will migrate from v%d to v%d', migration.from, migration.to)
    )
  else
    health.ok(string.format('Review state schema v%d is valid', document.schema_version))
  end
end

return M
