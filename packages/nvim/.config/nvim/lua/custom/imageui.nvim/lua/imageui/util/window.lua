local M = {}

---@param border any
---@param index integer
---@return boolean
function M.has_border_side(border, index)
  if type(border) ~= 'table' then
    return false
  end
  local value = border[index]
  if type(value) == 'table' then
    value = value[1]
  end
  return type(value) == 'string' and value ~= ''
end

---@param win integer
---@return ImageUI.Rect?
function M.content_rect(win)
  if not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return nil
  end
  local win_config = vim.api.nvim_win_get_config(win)
  if win_config.hide then
    return nil
  end
  local border = win_config.relative ~= '' and win_config.border or nil
  local border_left = M.has_border_side(border, 8) and 1 or 0
  local border_top = M.has_border_side(border, 2) and 1 or 0
  local top = info.winrow + border_top + (info.winbar or 0)
  return {
    top = top,
    left = info.wincol + border_left + (info.textoff or 0),
    bottom = top + info.height - 1,
    right = info.wincol + border_left + info.width - 1,
  }
end

---@param win integer
---@return ImageUI.Rect?
function M.float_rect(win)
  if not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local win_config = vim.api.nvim_win_get_config(win)
  if win_config.relative == '' or win_config.hide then
    return nil
  end
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return nil
  end
  local border = win_config.border
  local border_top = M.has_border_side(border, 2) and 1 or 0
  local border_right = M.has_border_side(border, 4) and 1 or 0
  local border_bottom = M.has_border_side(border, 6) and 1 or 0
  local border_left = M.has_border_side(border, 8) and 1 or 0
  return {
    top = info.winrow,
    left = info.wincol,
    bottom = info.winrow + win_config.height + border_top + border_bottom - 1,
    right = info.wincol + info.width + border_left + border_right - 1,
  }
end

return M
