local M = {}

---@class ImageUI.Scheduler
---@field timer uv.uv_timer_t
---@field delay integer
---@field callback function
---@field pending boolean
---@field requested_at integer?
---@field counters table
local Scheduler = {}
Scheduler.__index = Scheduler

---@param delay integer
---@param callback function
---@return ImageUI.Scheduler
function M.new(delay, callback)
  return setmetatable({
    timer = assert(vim.uv.new_timer()),
    delay = delay,
    callback = callback,
    pending = false,
    requested_at = nil,
    counters = {
      requests = 0,
      coalesced = 0,
      runs = 0,
      total_wait_ms = 0,
      max_wait_ms = 0,
    },
  }, Scheduler)
end

---@param delay? integer
function Scheduler:schedule(delay)
  if self.timer:is_closing() then
    return
  end
  self.counters.requests = self.counters.requests + 1
  -- Frame throttle instead of a trailing-edge debounce: once a frame is
  -- pending, later events update editor state but never postpone that frame.
  -- The callback therefore always observes the newest geometry without being
  -- starved by continuous scrolling.
  if self.pending then
    self.counters.coalesced = self.counters.coalesced + 1
    return
  end
  self.pending = true
  self.requested_at = vim.uv.hrtime()
  self.timer:start(
    delay or self.delay,
    0,
    vim.schedule_wrap(function()
      local wait_ms = self.requested_at and (vim.uv.hrtime() - self.requested_at) / 1e6 or 0
      self.pending = false
      self.requested_at = nil
      self.counters.runs = self.counters.runs + 1
      self.counters.total_wait_ms = self.counters.total_wait_ms + wait_ms
      self.counters.max_wait_ms = math.max(self.counters.max_wait_ms, wait_ms)
      self.callback()
    end)
  )
end

function Scheduler:flush()
  if self.timer:is_closing() or not self.pending then
    return
  end
  self.timer:stop()
  self.pending = false
  local wait_ms = self.requested_at and (vim.uv.hrtime() - self.requested_at) / 1e6 or 0
  self.requested_at = nil
  self.counters.runs = self.counters.runs + 1
  self.counters.total_wait_ms = self.counters.total_wait_ms + wait_ms
  self.counters.max_wait_ms = math.max(self.counters.max_wait_ms, wait_ms)
  self.callback()
end

function Scheduler:stats()
  local result = vim.deepcopy(self.counters)
  result.pending = self.pending
  result.average_wait_ms = result.runs > 0 and result.total_wait_ms / result.runs or 0
  result.current_wait_ms = self.pending
      and self.requested_at
      and (vim.uv.hrtime() - self.requested_at) / 1e6
    or 0
  return result
end

function Scheduler:close()
  if self.timer:is_closing() then
    return
  end
  self.timer:stop()
  self.pending = false
  self.requested_at = nil
  self.timer:close()
end

return M
