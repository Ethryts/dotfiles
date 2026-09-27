local M = {}
local window_geometry = require('imageui.util.window')

local namespace = vim.api.nvim_create_namespace('imageui.nvim:anchors')

---@param win integer
---@return boolean
local function window_is_visible(win)
  return vim.api.nvim_win_is_valid(win) and not vim.api.nvim_win_get_config(win).hide
end

---@class ImageUI.Anchor
---@field kind 'buffer'|'window'|'screen'|'cursor'
---@field buffer? integer
---@field window? integer
---@field mark? integer
---@field row? integer
---@field col? integer

---@param spec table
---@return ImageUI.Anchor
function M.create(spec)
  vim.validate('anchor', spec, 'table')
  local kind = spec.kind or 'buffer'
  assert(vim.tbl_contains({ 'buffer', 'window', 'screen', 'cursor' }, kind), 'invalid anchor kind')

  if kind == 'buffer' then
    local buffer = spec.buffer or spec.buf or 0
    buffer = buffer == 0 and vim.api.nvim_get_current_buf() or buffer
    assert(vim.api.nvim_buf_is_valid(buffer), 'invalid anchor buffer')
    local mark = vim.api.nvim_buf_set_extmark(buffer, namespace, assert(spec.row), spec.col or 0, {
      right_gravity = spec.right_gravity == true,
      undo_restore = spec.undo_restore ~= false,
      invalidate = spec.invalidate ~= false,
      strict = true,
    })
    return {
      kind = kind,
      buffer = buffer,
      window = spec.window or spec.win,
      mark = mark,
    }
  end

  if kind == 'window' then
    local origin = spec.origin or 'window'
    assert(
      origin == 'window' or origin == 'content',
      'window anchor origin must be window or content'
    )
    return {
      kind = kind,
      window = spec.window or spec.win or 0,
      row = spec.row or 0,
      col = spec.col or 0,
      origin = origin,
    }
  end

  if kind == 'cursor' then
    return {
      kind = kind,
      window = spec.window or spec.win or 0,
      row = spec.row or 0,
      col = spec.col or 0,
    }
  end

  return {
    kind = kind,
    row = assert(spec.row, 'screen anchor requires row'),
    col = assert(spec.col, 'screen anchor requires col'),
  }
end

---@param anchor ImageUI.Anchor
function M.delete(anchor)
  if
    anchor.kind == 'buffer'
    and anchor.buffer
    and anchor.mark
    and vim.api.nvim_buf_is_valid(anchor.buffer)
  then
    pcall(vim.api.nvim_buf_del_extmark, anchor.buffer, namespace, anchor.mark)
  end
end

---@param anchor ImageUI.Anchor
---@return integer[]
function M.windows(anchor)
  if anchor.kind == 'screen' then
    return { 0 }
  end
  if anchor.window and anchor.window ~= 0 then
    if not window_is_visible(anchor.window) then
      return {}
    end
    if anchor.kind == 'buffer' and vim.api.nvim_win_get_buf(anchor.window) ~= anchor.buffer then
      return {}
    end
    return { anchor.window }
  end
  if anchor.kind == 'cursor' or anchor.kind == 'window' then
    local win = vim.api.nvim_get_current_win()
    return window_is_visible(win) and { win } or {}
  end

  local result = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if window_is_visible(win) and vim.api.nvim_win_get_buf(win) == anchor.buffer then
      result[#result + 1] = win
    end
  end
  return result
end

---@param anchor ImageUI.Anchor
---@param win integer
---@return {row: integer, col: integer}?
function M.screen_position(anchor, win)
  if anchor.kind == 'screen' then
    return { row = anchor.row, col = anchor.col }
  end
  if not window_is_visible(win) then
    return nil
  end

  if anchor.kind == 'window' then
    if anchor.origin == 'content' then
      local rect = window_geometry.content_rect(win)
      return rect and { row = rect.top + anchor.row, col = rect.left + anchor.col } or nil
    end
    local pos = vim.fn.win_screenpos(win)
    return { row = pos[1] + anchor.row, col = pos[2] + anchor.col }
  end
  if anchor.kind == 'cursor' then
    local cursor = vim.api.nvim_win_get_cursor(win)
    local pos = vim.fn.screenpos(win, cursor[1], cursor[2] + 1)
    if pos.row == 0 then
      return nil
    end
    return { row = pos.row + anchor.row, col = pos.col + anchor.col }
  end

  if not anchor.buffer or not anchor.mark or not vim.api.nvim_buf_is_valid(anchor.buffer) then
    return nil
  end
  local extmark = vim.api.nvim_buf_get_extmark_by_id(anchor.buffer, namespace, anchor.mark, {
    details = true,
  })
  if #extmark == 0 or (extmark[3] and extmark[3].invalid) then
    return nil
  end
  local line = extmark[1] + 1
  local fold_start = vim.api.nvim_win_call(win, function()
    return vim.fn.foldclosed(line)
  end)
  if fold_start ~= -1 and fold_start ~= line then
    return nil
  end
  local pos = vim.fn.screenpos(win, line, extmark[2] + 1)
  if pos.row == 0 or pos.col == 0 then
    return nil
  end
  return { row = pos.row, col = pos.col }
end

---@return integer
function M.namespace()
  return namespace
end

return M
