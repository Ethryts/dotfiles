local M = {}

local active

---@param configured 'auto'|'nvim_img'|table
---@param config? table
---@return table
function M.setup(configured, config)
  if configured == 'auto' then
    active = require('imageui.backend.kitty_pool').setup({
      max_assets = config and config.render.cache.max_entries or 256,
      max_bytes = config and config.render.cache.max_bytes or 64 * 1024 * 1024,
      tmux = config and config.transport.tmux or 'auto',
      safe_reposition = config and config.transport.safe_reposition or 'auto',
    })
  elseif configured == 'nvim_img' then
    active = require('imageui.backend.nvim_img')
  elseif type(configured) == 'table' then
    for _, method in ipairs({ 'available', 'set', 'update', 'delete' }) do
      assert(
        type(configured[method]) == 'function',
        ('imageui backend requires %s()'):format(method)
      )
    end
    active = configured
  else
    error('imageui.nvim: backend must be "auto", "nvim_img", or a backend table')
  end
  return active
end

---@return table
function M.get()
  return active or M.setup('auto')
end

return M
