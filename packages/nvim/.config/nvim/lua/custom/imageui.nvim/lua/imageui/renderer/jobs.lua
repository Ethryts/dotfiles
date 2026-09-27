local M = {}

local limit = 4
local queue_limit = 256
local running = 0
local queued = {}
local active = {}
local generation = 0
local runner = vim.system
local counters = {}

local function reset_counters()
  counters = {
    submitted = 0,
    completed = 0,
    cancelled = 0,
    peak_running = 0,
    peak_queued = 0,
  }
end

reset_counters()

local function finish(job, result)
  if job.finished then
    return
  end
  job.finished = true
  if job.started then
    running = running - 1
    active[job] = nil
  end
  if job.cancelled then
    counters.cancelled = counters.cancelled + 1
  else
    counters.completed = counters.completed + 1
  end
  job.callback(result)
end

local drain
drain = function()
  while running < limit and #queued > 0 do
    local job = table.remove(queued, 1)
    if job.generation ~= generation or job.cancelled then
      finish(job, { code = -1, signal = 0, stdout = '', stderr = 'render job cancelled' })
    else
      job.started = true
      running = running + 1
      active[job] = true
      counters.peak_running = math.max(counters.peak_running, running)
      local ok, handle = pcall(runner, job.command, job.opts, function(result)
        finish(job, result)
        drain()
      end)
      if ok then
        job.handle = handle
      else
        finish(job, { code = -1, signal = 0, stdout = '', stderr = tostring(handle) })
      end
    end
  end
end

local function cancel(job, reason)
  if not job or job.finished then
    return false
  end
  job.cancelled = true
  if not job.started then
    for index, queued_job in ipairs(queued) do
      if queued_job == job then
        table.remove(queued, index)
        break
      end
    end
    finish(job, {
      code = -1,
      signal = 0,
      stdout = '',
      stderr = reason or 'render job cancelled',
    })
    drain()
  else
    if job.handle and type(job.handle.kill) == 'function' then
      pcall(job.handle.kill, job.handle, 15)
    end
    -- Keep the concurrency slot until vim.system reports that the killed
    -- child actually exited. Starting a replacement immediately can exceed
    -- the configured process limit under rapid viewport cancellation.
  end
  return true
end

---@param opts table
---@param custom_runner? function
function M.setup(opts, custom_runner)
  generation = generation + 1
  for _, job in ipairs(queued) do
    job.cancelled = true
    finish(job, { code = -1, signal = 0, stdout = '', stderr = 'render queue reconfigured' })
  end
  queued = {}
  local active_jobs = vim.tbl_keys(active)
  for _, job in ipairs(active_jobs) do
    job.cancelled = true
    if job.handle and type(job.handle.kill) == 'function' then
      pcall(job.handle.kill, job.handle, 15)
    end
    finish(job, { code = -1, signal = 15, stdout = '', stderr = 'render job reconfigured' })
  end
  active = {}
  running = 0
  limit = opts.render.max_jobs
  queue_limit = opts.render.max_queue
  runner = custom_runner or vim.system
  reset_counters()
end

---@param command string[]
---@param opts table
---@param callback fun(result: table)
---@return table
function M.run(command, opts, callback)
  while #queued >= queue_limit do
    cancel(queued[1], 'render queue saturated; superseded by newer work')
  end
  local job = {
    command = command,
    opts = opts,
    callback = callback,
    generation = generation,
  }
  counters.submitted = counters.submitted + 1
  queued[#queued + 1] = job
  counters.peak_queued = math.max(counters.peak_queued, #queued)
  drain()
  return job
end

function M.cancel(job)
  return cancel(job)
end

function M.stats()
  return vim.tbl_extend('force', vim.deepcopy(counters), {
    running = running,
    queued = #queued,
    limit = limit,
    queue_limit = queue_limit,
  })
end

return M
