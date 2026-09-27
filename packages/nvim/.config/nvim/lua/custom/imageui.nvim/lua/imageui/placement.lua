local anchor = require('imageui.anchor')
local geometry = require('imageui.util.geometry')
local window_geometry = require('imageui.util.window')

local M = {}

local config

---@param border string|table|nil
---@param index integer
---@return boolean
---@param opts table
function M.setup(opts)
  config = opts
end

---@return ImageUI.Rect
local function editor_rect()
  return { top = 1, left = 1, bottom = vim.o.lines, right = vim.o.columns }
end

---@param win integer
---@return ImageUI.Rect?
local function window_rect(win)
  return window_geometry.content_rect(win)
end

---@param win integer
---@return ImageUI.Rect?
local function float_rect(win)
  return window_geometry.float_rect(win)
end

---@param owner integer
---@return ImageUI.Rect[]
local function obstacles(owner)
  local result = {}
  local owner_zindex = -math.huge
  if owner ~= 0 and vim.api.nvim_win_is_valid(owner) then
    local owner_config = vim.api.nvim_win_get_config(owner)
    if owner_config.relative ~= '' then
      owner_zindex = owner_config.zindex or 50
    end
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= owner then
      local rect = float_rect(win)
      local win_config = rect and vim.api.nvim_win_get_config(win) or nil
      if rect and (win_config.zindex or 50) >= owner_zindex then
        result[#result + 1] = rect
      end
    end
  end
  local popup = vim.fn.pum_getpos()
  if
    popup
    and popup.visible == 1
    and popup.width > 0
    and popup.height > 0
    and owner_zindex <= 100
  then
    result[#result + 1] = {
      top = popup.row + 1,
      left = popup.col + 1,
      bottom = popup.row + popup.height,
      right = popup.col + popup.width,
    }
  end
  return result
end

---@param widget table
---@param asset table
---@param target_win? integer
---@return table[]
function M.resolve(widget, asset, target_win)
  local result = {}
  local details = {}
  local spec = widget.spec
  local clip_policy = spec.clip or config.placement.clip
  local partial = spec.partial or config.placement.partial
  local occlusion = spec.occlusion or config.placement.occlusion
  local zindex = spec.zindex or config.placement.zindex

  local windows = target_win ~= nil and { target_win } or anchor.windows(widget.anchor)
  for _, win in ipairs(windows) do
    if target_win == nil or win == target_win then
      local position = anchor.screen_position(widget.anchor, win)
      local detail = { win = win, reason = 'anchor_hidden', fragments = 0 }
      details[win] = detail
      if position then
        detail.position = vim.deepcopy(position)
        local desired = {
          top = position.row + (spec.offset_row or 0),
          left = position.col + (spec.offset_col or 0),
          bottom = position.row + (spec.offset_row or 0) + asset.height_cells - 1,
          right = position.col + (spec.offset_col or 0) + asset.width_cells - 1,
        }
        local bounds = clip_policy == 'none' and desired
          or (clip_policy == 'editor' or win == 0) and editor_rect()
          or window_rect(win)
        detail.desired = vim.deepcopy(desired)
        detail.bounds = bounds and vim.deepcopy(bounds) or nil

        local fragments = {}
        if bounds then
          if partial == 'allow' then
            fragments = { desired }
          elseif partial == 'hide' then
            fragments = geometry.contains(bounds, desired) and { desired } or {}
            if #fragments == 0 then
              detail.reason = 'partial_hidden'
            end
          else
            local visible = geometry.intersect(desired, bounds)
            fragments = visible and { visible } or {}
            if #fragments == 0 then
              detail.reason = 'outside_clip'
            end
          end
        else
          detail.reason = 'no_clip_bounds'
        end

        local obs = obstacles(win)
        if occlusion == 'hide' then
          for _, obstacle in ipairs(obs) do
            if geometry.intersect(desired, obstacle) then
              fragments = {}
              detail.reason = 'occluded'
              break
            end
          end
        elseif occlusion == 'clip' then
          local before = #fragments
          fragments = geometry.subtract_all(fragments, obs)
          if before > 0 and #fragments == 0 then
            detail.reason = 'occluded'
          end
        end

        if #fragments <= config.placement.max_fragments then
          for _, fragment in ipairs(fragments) do
            local crop = {
              top = fragment.top - desired.top,
              left = fragment.left - desired.left,
              width = geometry.width(fragment),
              height = geometry.height(fragment),
            }
            result[#result + 1] = {
              win = win,
              rect = fragment,
              crop = crop,
              opts = {
                row = fragment.top,
                col = fragment.left,
                width = crop.width,
                height = crop.height,
                zindex = zindex,
              },
              key = table.concat({
                win,
                crop.top,
                crop.left,
                crop.width,
                crop.height,
              }, ':'),
            }
          end
          if #fragments > 0 then
            detail.reason = 'placed'
            detail.fragments = #fragments
          end
        else
          detail.reason = 'fragment_limit'
          detail.fragments = #fragments
        end
      end
    end
  end
  return result, details
end

M.window_rect = window_rect
M.float_rect = float_rect
M.editor_rect = editor_rect

return M
