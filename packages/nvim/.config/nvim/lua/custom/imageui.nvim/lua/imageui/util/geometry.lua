local M = {}

---@class ImageUI.Rect
---@field top integer
---@field left integer
---@field bottom integer
---@field right integer

---@param rect ImageUI.Rect
---@return integer
function M.width(rect)
  return math.max(0, rect.right - rect.left + 1)
end

---@param rect ImageUI.Rect
---@return integer
function M.height(rect)
  return math.max(0, rect.bottom - rect.top + 1)
end

---@param rect ImageUI.Rect
---@return boolean
function M.empty(rect)
  return rect.right < rect.left or rect.bottom < rect.top
end

---@param a ImageUI.Rect
---@param b ImageUI.Rect
---@return ImageUI.Rect?
function M.intersect(a, b)
  local rect = {
    top = math.max(a.top, b.top),
    left = math.max(a.left, b.left),
    bottom = math.min(a.bottom, b.bottom),
    right = math.min(a.right, b.right),
  }
  if M.empty(rect) then
    return nil
  end
  return rect
end

---@param outer ImageUI.Rect
---@param inner ImageUI.Rect
---@return boolean
function M.contains(outer, inner)
  return inner.top >= outer.top
    and inner.left >= outer.left
    and inner.bottom <= outer.bottom
    and inner.right <= outer.right
end

---Subtract one rectangle from another, returning up to four non-overlapping pieces.
---@param source ImageUI.Rect
---@param cut ImageUI.Rect
---@return ImageUI.Rect[]
function M.subtract(source, cut)
  local overlap = M.intersect(source, cut)
  if not overlap then
    return { vim.deepcopy(source) }
  end

  local pieces = {}
  local function add(rect)
    if not M.empty(rect) then
      pieces[#pieces + 1] = rect
    end
  end

  add({
    top = source.top,
    left = source.left,
    bottom = overlap.top - 1,
    right = source.right,
  })
  add({
    top = overlap.bottom + 1,
    left = source.left,
    bottom = source.bottom,
    right = source.right,
  })
  add({
    top = overlap.top,
    left = source.left,
    bottom = overlap.bottom,
    right = overlap.left - 1,
  })
  add({
    top = overlap.top,
    left = overlap.right + 1,
    bottom = overlap.bottom,
    right = source.right,
  })

  return pieces
end

---@param sources ImageUI.Rect[]
---@param cuts ImageUI.Rect[]
---@return ImageUI.Rect[]
function M.subtract_all(sources, cuts)
  local result = sources
  for _, cut in ipairs(cuts) do
    local next_result = {}
    for _, source in ipairs(result) do
      vim.list_extend(next_result, M.subtract(source, cut))
    end
    result = next_result
    if #result == 0 then
      break
    end
  end
  return result
end

---@param rect ImageUI.Rect
---@return string
function M.key(rect)
  return table.concat({ rect.top, rect.left, rect.bottom, rect.right }, ':')
end

return M
