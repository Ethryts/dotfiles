local M = {}

---@class ImageUI.Cache
---@field max_entries integer
---@field max_weight number?
---@field weigh fun(key: string, value: any): number
---@field entries table<string, { value: any, used: integer, weight: number }>
---@field clock integer
---@field total_weight number
local Cache = {}
Cache.__index = Cache

---@param max_entries integer
---@param opts? {max_weight?: number, weigh?: fun(key: string, value: any): number}
---@return ImageUI.Cache
function M.new(max_entries, opts)
  opts = opts or {}
  return setmetatable({
    max_entries = max_entries,
    max_weight = opts.max_weight,
    weigh = opts.weigh or function()
      return 1
    end,
    entries = {},
    clock = 0,
    total_weight = 0,
  }, Cache)
end

---@param key string
---@return any?
function Cache:get(key)
  local entry = self.entries[key]
  if not entry then
    return nil
  end
  self.clock = self.clock + 1
  entry.used = self.clock
  return entry.value
end

---@param key string
---@param value any
function Cache:set(key, value)
  self.clock = self.clock + 1
  local previous = self.entries[key]
  if previous then
    self.total_weight = self.total_weight - previous.weight
  end
  local weight = self.weigh(key, value)
  assert(type(weight) == 'number' and weight >= 0, 'cache weight must be non-negative')
  self.entries[key] = { value = value, used = self.clock, weight = weight }
  self.total_weight = self.total_weight + weight
  self:prune()
end

function Cache:prune()
  local count = vim.tbl_count(self.entries)
  while
    count > self.max_entries or (self.max_weight ~= nil and self.total_weight > self.max_weight)
  do
    local oldest_key
    local oldest_used = math.huge
    for key, entry in pairs(self.entries) do
      if entry.used < oldest_used then
        oldest_key = key
        oldest_used = entry.used
      end
    end
    if not oldest_key then
      return
    end
    self.total_weight = self.total_weight - self.entries[oldest_key].weight
    self.entries[oldest_key] = nil
    count = count - 1
  end
end

function Cache:clear()
  self.entries = {}
  self.total_weight = 0
end

---@return integer
function Cache:size()
  return vim.tbl_count(self.entries)
end

---@return number
function Cache:weight()
  return self.total_weight
end

return M
