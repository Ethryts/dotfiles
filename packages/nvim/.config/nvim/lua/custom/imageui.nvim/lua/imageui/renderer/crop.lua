local Cache = require('imageui.cache')
local fs = require('imageui.util.fs')
local rasterizer = require('imageui.renderer.rasterizer')
local jobs = require('imageui.renderer.jobs')

local M = {}

local config
local cache
local pending = {}
local executable
local generation = 0
local counters = {}

---@param opts table
function M.setup(opts)
  config = opts
  cache = Cache.new(math.max(32, math.floor(opts.render.cache.max_entries / 2)))
  pending = {}
  generation = generation + 1
  counters = {
    requests = 0,
    cache_hits = 0,
    joined = 0,
    jobs = 0,
    completed = 0,
    failures = 0,
    cancelled = 0,
    peak_pending = 0,
    peak_waiters = 0,
  }
  executable = vim.fn.executable('magick') == 1 and 'magick'
    or (vim.fn.executable('convert') == 1 and 'convert' or false)
end

---@return boolean
function M.available()
  return executable ~= false
end

---@param asset table
---@param crop {top: integer, left: integer, width: integer, height: integer}
---@param callback fun(asset?: table, err?: string)
---@return fun()? cancel
function M.get(asset, crop, callback)
  counters.requests = counters.requests + 1
  if
    crop.left == 0
    and crop.top == 0
    and crop.width == asset.width_cells
    and crop.height == asset.height_cells
  then
    callback(asset)
    return nil
  end

  if not executable then
    callback(nil, 'partial clipping requires ImageMagick')
    return nil
  end
  if not asset.path or not asset.pixel_width or not asset.pixel_height then
    callback(nil, 'partial clipping requires a file-backed image with pixel dimensions')
    return nil
  end

  local key = table.concat({
    asset.key,
    crop.top,
    crop.left,
    crop.width,
    crop.height,
    asset.width_cells,
    asset.height_cells,
    asset.pixel_width,
    asset.pixel_height,
  }, ':')
  local existing = cache:get(key)
  if existing and fs.exists(existing.path) then
    counters.cache_hits = counters.cache_hits + 1
    callback(existing)
    return nil
  end
  local subscriber = { callback = callback, active = true }
  if pending[key] then
    local request = pending[key]
    request.subscribers[#request.subscribers + 1] = subscriber
    counters.joined = counters.joined + 1
    local waiters = 0
    for _, current in pairs(pending) do
      waiters = waiters + #current.subscribers
    end
    counters.peak_waiters = math.max(counters.peak_waiters, waiters)
    return function()
      subscriber.active = false
      local active = false
      for _, current in ipairs(request.subscribers) do
        active = active or current.active
      end
      if not active and pending[key] == request then
        pending[key] = nil
        counters.cancelled = counters.cancelled + 1
        jobs.cancel(request.job)
      end
    end
  end
  local request = { subscribers = { subscriber } }
  pending[key] = request
  counters.jobs = counters.jobs + 1
  counters.peak_pending = math.max(counters.peak_pending, vim.tbl_count(pending))
  counters.peak_waiters = math.max(counters.peak_waiters, 1)
  local crop_generation = generation
  local crop_pending = pending
  local crop_cache = cache

  local px_per_col = asset.pixel_width / asset.width_cells
  local px_per_row = asset.pixel_height / asset.height_cells
  local x = math.floor(crop.left * px_per_col)
  local y = math.floor(crop.top * px_per_row)
  local right = math.floor((crop.left + crop.width) * px_per_col)
  local bottom = math.floor((crop.top + crop.height) * px_per_row)
  local width = math.max(1, right - x)
  local height = math.max(1, bottom - y)
  local output =
    vim.fs.joinpath(config.render.cache.directory, 'crop-' .. vim.fn.sha256(key) .. '.png')
  local command = {
    executable,
    asset.path,
    '-crop',
    ('%dx%d+%d+%d'):format(width, height, x, y),
    '+repage',
    output,
  }

  request.job = jobs.run(command, { timeout = config.render.timeout }, function(result)
    vim.schedule(function()
      if crop_pending[key] == request then
        crop_pending[key] = nil
      end
      local subscribers = request.subscribers
      local has_active = false
      for _, current in ipairs(subscribers) do
        has_active = has_active or current.active
      end
      if not has_active then
        return
      end
      if crop_generation ~= generation then
        for _, current in ipairs(subscribers) do
          if current.active then
            current.callback(nil, 'crop invalidated by reconfiguration')
          end
        end
        return
      end
      local cropped
      local err
      if result.code ~= 0 or not fs.exists(output) then
        counters.failures = counters.failures + 1
        err = ('image crop failed: %s'):format(vim.trim(result.stderr or 'unknown error'))
      else
        counters.completed = counters.completed + 1
        cropped = {
          key = key,
          path = output,
          width_cells = crop.width,
          height_cells = crop.height,
          pixel_width = width,
          pixel_height = height,
          render_scale = asset.render_scale,
        }
        crop_cache:set(key, cropped)
      end
      for _, current in ipairs(subscribers) do
        if current.active then
          current.callback(cropped, err)
        end
      end
    end)
  end)
  return function()
    subscriber.active = false
    local active = false
    for _, current in ipairs(request.subscribers) do
      active = active or current.active
    end
    if not active and pending[key] == request then
      pending[key] = nil
      counters.cancelled = counters.cancelled + 1
      jobs.cancel(request.job)
    end
  end
end

---@param asset table
---@return string
function M.bytes(asset)
  return rasterizer.bytes(asset)
end

function M.clear()
  if cache then
    cache:clear()
  end
end

function M.stats()
  return vim.tbl_extend('force', vim.deepcopy(counters), {
    entries = cache and cache:size() or 0,
    pending = vim.tbl_count(pending),
  })
end

return M
