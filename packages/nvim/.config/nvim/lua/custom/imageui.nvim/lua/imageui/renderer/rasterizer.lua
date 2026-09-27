local Cache = require('imageui.cache')
local fs = require('imageui.util.fs')
local log = require('imageui.util.log')
local jobs = require('imageui.renderer.jobs')

local M = {}

local config
local cache
local byte_cache
local pending = {}
local selected
local generation = 0
local counters = {}

local candidates = {
  resvg = function(input, output, width, height)
    return { 'resvg', '--width', tostring(width), '--height', tostring(height), input, output }
  end,
  inkscape = function(input, output, width, height)
    return {
      'inkscape',
      input,
      '--export-filename=' .. output,
      '--export-width=' .. width,
      '--export-height=' .. height,
    }
  end,
  ['rsvg-convert'] = function(input, output, width, height)
    return { 'rsvg-convert', '-w', tostring(width), '-h', tostring(height), '-o', output, input }
  end,
  magick = function(input, output, width, height)
    return {
      'magick',
      input,
      '-background',
      'none',
      '-resize',
      width .. 'x' .. height .. '!',
      output,
    }
  end,
  convert = function(input, output, width, height)
    return {
      'convert',
      input,
      '-background',
      'none',
      '-resize',
      width .. 'x' .. height .. '!',
      output,
    }
  end,
}

local order = { 'resvg', 'inkscape', 'rsvg-convert', 'magick', 'convert' }

local function select_rasterizer()
  if selected then
    return selected
  end
  if config.render.rasterizer ~= 'auto' then
    selected = vim.fn.executable(config.render.rasterizer) == 1 and config.render.rasterizer
      or false
    return selected
  end
  for _, name in ipairs(order) do
    if vim.fn.executable(name) == 1 then
      selected = name
      return name
    end
  end
  selected = false
  return false
end

---@param opts table
function M.setup(opts)
  config = opts
  cache = Cache.new(config.render.cache.max_entries)
  byte_cache = Cache.new(config.render.cache.max_entries, {
    max_weight = config.render.cache.max_bytes,
    weigh = function(_, bytes)
      return #bytes
    end,
  })
  fs.ensure_dir(config.render.cache.directory)
  pending = {}
  selected = nil
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
    byte_reads = 0,
    byte_cache_hits = 0,
  }
end

---@return string|false
function M.executable()
  return select_rasterizer()
end

---@param svg string
---@param metrics table
---@param callback fun(asset?: table, err?: string)
---@return fun()? cancel
function M.render(svg, metrics, callback)
  counters.requests = counters.requests + 1
  local executable = select_rasterizer()
  if not executable then
    callback(nil, 'no SVG rasterizer found (install resvg, Inkscape, librsvg, or ImageMagick)')
    return nil
  end

  local key = vim.fn.sha256(table.concat({
    executable,
    svg,
    metrics.width_cells,
    metrics.height_cells,
    metrics.pixel_width,
    metrics.pixel_height,
    metrics.render_scale or 1,
  }, '\0'))
  local existing = cache:get(key)
  if existing and fs.exists(existing.path) then
    counters.cache_hits = counters.cache_hits + 1
    callback(existing)
    return nil
  end
  local subscriber = { callback = callback, active = true }
  if pending[key] then
    counters.joined = counters.joined + 1
    local request = pending[key]
    request.subscribers[#request.subscribers + 1] = subscriber
    counters.peak_waiters = math.max(counters.peak_waiters, #request.subscribers)
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
  local render_generation = generation
  local render_pending = pending
  local render_cache = cache

  local input = vim.fs.joinpath(config.render.cache.directory, key .. '.svg')
  local output = vim.fs.joinpath(config.render.cache.directory, key .. '.png')
  fs.write_text(input, svg)
  local command = candidates[executable](input, output, metrics.pixel_width, metrics.pixel_height)

  request.job = jobs.run(command, { timeout = config.render.timeout }, function(result)
    vim.schedule(function()
      if render_pending[key] == request then
        render_pending[key] = nil
      end
      local subscribers = request.subscribers
      local has_active = false
      for _, current in ipairs(subscribers) do
        has_active = has_active or current.active
      end
      if not has_active then
        return
      end
      if render_generation ~= generation then
        for _, current in ipairs(subscribers) do
          if current.active then
            current.callback(nil, 'render invalidated by reconfiguration')
          end
        end
        return
      end
      local asset
      local err
      if result.code ~= 0 or not fs.exists(output) then
        counters.failures = counters.failures + 1
        err = ('%s failed: %s'):format(executable, vim.trim(result.stderr or 'unknown error'))
        log.error(err)
      else
        counters.completed = counters.completed + 1
        asset = vim.tbl_extend('force', vim.deepcopy(metrics), {
          key = key,
          path = output,
          svg_path = input,
        })
        render_cache:set(key, asset)
      end
      for _, current in ipairs(subscribers) do
        if current.active then
          current.callback(asset, err)
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
  if asset.bytes then
    return asset.bytes
  end
  local byte_key = table.concat({ asset.key or '', asset.path or '' }, '\0')
  local existing = byte_cache:get(byte_key)
  if existing then
    counters.byte_cache_hits = counters.byte_cache_hits + 1
    asset.bytes = existing
    return existing
  end
  counters.byte_reads = counters.byte_reads + 1
  asset.bytes = fs.read_binary(asset.path)
  byte_cache:set(byte_key, asset.bytes)
  return asset.bytes
end

function M.clear()
  if cache then
    cache:clear()
  end
  if byte_cache then
    byte_cache:clear()
  end
end

---@return table
function M.stats()
  return vim.tbl_extend('force', vim.deepcopy(counters), {
    executable = select_rasterizer(),
    entries = cache and cache:size() or 0,
    byte_entries = byte_cache and byte_cache:size() or 0,
    byte_size = byte_cache and byte_cache:weight() or 0,
    pending = vim.tbl_count(pending),
    directory = config and config.render.cache.directory or nil,
  })
end

return M
