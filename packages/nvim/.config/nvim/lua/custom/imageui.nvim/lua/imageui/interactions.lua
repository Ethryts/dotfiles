local manager = require('imageui.manager')
local log = require('imageui.util.log')

local M = {}

local config
local augroup
local mousemove_before
local mappings = {}

local function install_click(mode)
  local existing = vim.fn.maparg('<LeftMouse>', mode, false, true)
  if existing and not vim.tbl_isempty(existing) then
    log.warn(('not installing %s <LeftMouse>: a mapping already exists'):format(mode), true)
    return
  end
  local callback = function()
    if manager.dispatch('click') then
      return vim.keycode('<Ignore>')
    end
    return vim.keycode('<LeftMouse>')
  end
  vim.keymap.set(mode, '<LeftMouse>', callback, {
    expr = true,
    replace_keycodes = false,
    desc = 'ImageUI click dispatch',
  })
  mappings[#mappings + 1] = { mode = mode, callback = callback }
end

---@param opts table
function M.setup(opts)
  config = opts
end

function M.enable()
  if config.interactions.mouse then
    install_click('n')
    install_click('i')
  end
  if config.interactions.hover then
    mousemove_before = vim.o.mousemoveevent
    vim.o.mousemoveevent = true
    augroup = vim.api.nvim_create_augroup('ImageUIInteractions', { clear = true })
    vim.api.nvim_create_autocmd('MouseMove', {
      group = augroup,
      callback = function()
        manager.dispatch_hover()
      end,
    })
  end
end

function M.disable()
  for _, mapping in ipairs(mappings) do
    local current = vim.fn.maparg('<LeftMouse>', mapping.mode, false, true)
    if current and current.callback == mapping.callback then
      pcall(vim.keymap.del, mapping.mode, '<LeftMouse>')
    end
  end
  mappings = {}
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  if mousemove_before ~= nil then
    vim.o.mousemoveevent = mousemove_before
    mousemove_before = nil
  end
end

return M
