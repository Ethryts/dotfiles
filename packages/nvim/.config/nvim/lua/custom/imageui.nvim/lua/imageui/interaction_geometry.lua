local geometry = require('imageui.util.geometry')

local M = {}

local DEFAULT_COLLISION_LIMIT = 64
local MAX_COLLISION_LIMIT = 1024
local MAX_CACHED_SIGNATURES = 8
local collision_cache = setmetatable({}, { __mode = 'k' })
local collision_stats = { calculations = 0, cache_hits = 0 }

local function computed_hit(visual)
  if not visual or visual.width <= 0 or visual.height <= 0 then
    return nil
  end
  return {
    top = math.floor(visual.y),
    left = math.floor(visual.x),
    bottom = math.max(math.floor(visual.y), math.ceil(visual.y + visual.height) - 1),
    right = math.max(math.floor(visual.x), math.ceil(visual.x + visual.width) - 1),
  }
end

---@param region table
---@return table?
function M.hit_rect(region)
  local explicit = region.hit_rect
  if explicit then
    local top = explicit.row or explicit.top or 0
    local left = explicit.col or explicit.left or 0
    local rows = explicit.rows or explicit.height
    local cols = explicit.cols or explicit.width
    local result = {
      top = top,
      left = left,
      bottom = explicit.bottom or (top + assert(rows, 'hit_rect requires rows/height') - 1),
      right = explicit.right or (left + assert(cols, 'hit_rect requires cols/width') - 1),
    }
    for name, value in pairs(result) do
      assert(
        type(value) == 'number' and value % 1 == 0,
        ('hit_rect.%s must resolve to an integer cell'):format(name)
      )
    end
    assert(result.bottom >= result.top and result.right >= result.left, 'hit_rect cannot be empty')
    return result
  end
  return computed_hit(region.visual)
end

local function collision_signature(regions, interactive, limit)
  local parts = { tostring(limit) }
  if not interactive then
    parts[#parts + 1] = '*'
  else
    for _, region in ipairs(regions) do
      parts[#parts + 1] = interactive[region.id] and '1' or '0'
    end
  end
  return table.concat(parts, '\0')
end

local function update_max_bottom(node)
  if not node then
    return
  end
  node.max_bottom = node.rect.bottom
  if node.left then
    node.max_bottom = math.max(node.max_bottom, node.left.max_bottom)
  end
  if node.right then
    node.max_bottom = math.max(node.max_bottom, node.right.max_bottom)
  end
end

local function rotate_left(node)
  local right = node.right
  node.right = right.left
  right.left = node
  update_max_bottom(node)
  update_max_bottom(right)
  return right
end

local function rotate_right(node)
  local left = node.left
  node.left = left.right
  left.right = node
  update_max_bottom(node)
  update_max_bottom(left)
  return left
end

local function key_before(first, second)
  return first.rect.top < second.rect.top
    or (first.rect.top == second.rect.top and first.index < second.index)
end

local function insert(root, node)
  if not root then
    return node
  end
  if key_before(node, root) then
    root.left = insert(root.left, node)
    if root.left.priority < root.priority then
      root = rotate_right(root)
    end
  else
    root.right = insert(root.right, node)
    if root.right.priority < root.priority then
      root = rotate_left(root)
    end
  end
  update_max_bottom(root)
  return root
end

local function remove(root, node)
  if not root then
    return nil
  end
  if root == node then
    if not root.left then
      return root.right
    elseif not root.right then
      return root.left
    elseif root.left.priority < root.right.priority then
      root = rotate_right(root)
      root.right = remove(root.right, node)
    else
      root = rotate_left(root)
      root.left = remove(root.left, node)
    end
  elseif key_before(node, root) then
    root.left = remove(root.left, node)
  else
    root.right = remove(root.right, node)
  end
  update_max_bottom(root)
  return root
end

local function query_overlaps(root, candidate, callback)
  if not root or root.max_bottom < candidate.rect.top then
    return false
  end
  if root.left and root.left.max_bottom >= candidate.rect.top then
    if query_overlaps(root.left, candidate, callback) then
      return true
    end
  end
  if
    root.rect.top <= candidate.rect.bottom
    and root.rect.bottom >= candidate.rect.top
    and callback(root)
  then
    return true
  end
  if root.rect.top <= candidate.rect.bottom then
    return query_overlaps(root.right, candidate, callback)
  end
  return false
end

local function heap_before(first, second)
  return first.rect.right < second.rect.right
    or (first.rect.right == second.rect.right and first.index < second.index)
end

local function heap_push(heap, value)
  local index = #heap + 1
  while index > 1 do
    local parent = math.floor(index / 2)
    if not heap_before(value, heap[parent]) then
      break
    end
    heap[index] = heap[parent]
    index = parent
  end
  heap[index] = value
end

local function heap_pop(heap)
  local first = heap[1]
  local last = table.remove(heap)
  if #heap > 0 then
    local index = 1
    while index * 2 <= #heap do
      local child = index * 2
      if child < #heap and heap_before(heap[child + 1], heap[child]) then
        child = child + 1
      end
      if not heap_before(heap[child], last) then
        break
      end
      heap[index] = heap[child]
      index = child
    end
    heap[index] = last
  end
  return first
end

local function calculate_collisions(regions, interactive, limit)
  local candidates = {}
  local priority = 1
  for index, region in ipairs(regions) do
    if not interactive or interactive[region.id] then
      local rect = M.hit_rect(region)
      if rect then
        -- A deterministic pseudo-random priority keeps the interval treap
        -- balanced without depending on process-global random state.
        priority = (priority * 48271) % 2147483647
        candidates[#candidates + 1] = {
          index = index,
          region = region,
          rect = rect,
          priority = priority,
          max_bottom = rect.bottom,
        }
      end
    end
  end
  table.sort(candidates, function(first, second)
    return first.rect.left < second.rect.left
      or (first.rect.left == second.rect.left and first.index < second.index)
  end)

  local result = {}
  local root
  local by_right = {}
  for position, candidate in ipairs(candidates) do
    while by_right[1] and by_right[1].rect.right < candidate.rect.left do
      root = remove(root, heap_pop(by_right))
    end
    local capped = query_overlaps(root, candidate, function(other)
      local first = other.index < candidate.index and other or candidate
      local second = other.index < candidate.index and candidate or other
      result[#result + 1] = {
        first = first.region.id,
        second = second.region.id,
        rect = geometry.intersect(first.rect, second.rect),
      }
      return #result >= limit
    end)
    if capped then
      result.truncated = true
      result.limit = limit
      result.remaining_regions = #candidates - position
      return result
    end
    root = insert(root, candidate)
    heap_push(by_right, candidate)
  end
  result.truncated = false
  result.limit = limit
  result.remaining_regions = 0
  return result
end

---@param regions table[]
---@param interactive? table<string, boolean>
---@param opts? {max_results?: integer}
---@return table[]
function M.collisions(regions, interactive, opts)
  opts = opts or {}
  local requested_limit = opts.max_results or DEFAULT_COLLISION_LIMIT
  assert(
    type(requested_limit) == 'number' and requested_limit >= 1 and requested_limit % 1 == 0,
    'max_results must be a positive integer'
  )
  local limit = math.min(requested_limit, MAX_COLLISION_LIMIT)
  local signature = collision_signature(regions, interactive, limit)
  local cached = collision_cache[regions]
  if cached and cached.values[signature] then
    collision_stats.cache_hits = collision_stats.cache_hits + 1
    return cached.values[signature]
  end
  collision_stats.calculations = collision_stats.calculations + 1
  local result = calculate_collisions(regions, interactive, limit)
  cached = cached or { values = {}, order = {} }
  while #cached.order >= MAX_CACHED_SIGNATURES do
    cached.values[table.remove(cached.order, 1)] = nil
  end
  cached.order[#cached.order + 1] = signature
  cached.values[signature] = result
  collision_cache[regions] = cached
  return result
end

---@param region table
---@param view {rect: table, crop: table}
---@return table?
function M.project(region, view)
  local hit = M.hit_rect(region)
  if not hit then
    return nil
  end
  local crop = {
    top = view.crop.top,
    left = view.crop.left,
    bottom = view.crop.top + view.crop.height - 1,
    right = view.crop.left + view.crop.width - 1,
  }
  local visible = geometry.intersect(hit, crop)
  if not visible then
    return nil
  end
  return {
    top = view.rect.top + visible.top - crop.top,
    left = view.rect.left + visible.left - crop.left,
    bottom = view.rect.top + visible.bottom - crop.top,
    right = view.rect.left + visible.right - crop.left,
  }
end

function M.clear_cache()
  collision_cache = setmetatable({}, { __mode = 'k' })
  collision_stats = { calculations = 0, cache_hits = 0 }
end

function M.stats()
  return vim.deepcopy(collision_stats)
end

return M
