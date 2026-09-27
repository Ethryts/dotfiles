local M = {}

local TAG = 'imageui-benchmark'
local session

local function imageui()
  return require('imageui')
end

local function numeric_delta(current, baseline)
  local result = {}
  for key, value in pairs(current or {}) do
    if type(value) == 'number' then
      result[key] = value - (type(baseline and baseline[key]) == 'number' and baseline[key] or 0)
    end
  end
  return result
end

local function snapshot()
  collectgarbage('collect')
  local inspected = imageui().inspect()
  return {
    at = vim.uv.hrtime(),
    lua_kib = collectgarbage('count'),
    rss_bytes = vim.uv.resident_set_memory(),
    reconciles = inspected.performance.reconciles,
    backend = vim.deepcopy(inspected.performance.backend),
    transport = vim.deepcopy(inspected.performance.transport or {}),
    renderer = vim.deepcopy(inspected.renderer),
    crop = vim.deepcopy(inspected.crop),
    jobs = vim.deepcopy(inspected.jobs),
    scheduler = vim.deepcopy(inspected.performance.scheduler or {}),
  }
end

local function nonblank_at(buf, row)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  local col = line:find('%S')
  return col and { row = row, col = col - 1 } or nil
end

local function distributed_rows(buf, count)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local rows = {}
  local seen = {}
  local stride = math.max(1, line_count / count)
  for index = 0, count - 1 do
    local first = math.min(line_count - 1, math.floor(index * stride))
    local last = math.min(line_count - 1, math.floor((index + 1) * stride) - 1)
    for row = first, math.max(first, last) do
      local location = nonblank_at(buf, row)
      if location and not seen[row] then
        rows[#rows + 1] = location
        seen[row] = true
        break
      end
    end
  end
  return rows
end

local function wait_for_baseline(deadline)
  if not session then
    return
  end
  local inspected = imageui().inspect()
  if inspected.renderer.pending == 0 and inspected.crop.pending == 0 then
    session.baseline = snapshot()
    vim.notify(
      'ImageUI benchmark ready; scroll normally, then run :ImageUI benchmark report',
      vim.log.levels.INFO,
      { title = 'imageui.nvim' }
    )
    return
  end
  if vim.uv.hrtime() >= deadline then
    vim.notify('ImageUI benchmark assets did not settle', vim.log.levels.WARN, {
      title = 'imageui.nvim',
    })
    return
  end
  vim.defer_fn(function()
    wait_for_baseline(deadline)
  end, 25)
end

---@param count? integer
function M.start(count)
  count = count or 12
  assert(count > 0, 'benchmark count must be positive')
  imageui().clear({ tag = TAG })
  local buf = vim.api.nvim_get_current_buf()
  local top = math.max(0, vim.fn.line('w0') - 1)
  local bottom = vim.fn.line('w$') - 1
  local rows = {}
  for row = top, bottom do
    local location = nonblank_at(buf, row)
    if location then
      rows[#rows + 1] = location
    end
  end
  if count > #rows then
    rows = distributed_rows(buf, count)
  end
  local labels = { '1 reference', '2 references', '4 references', '8 references' }
  local ids = {}
  local step = math.max(1, math.floor(#rows / math.min(count, math.max(1, #rows))))
  local cursor = 1
  while #ids < math.min(count, #rows) do
    local location = rows[cursor]
    ids[#ids + 1] = imageui().create({
      tag = TAG,
      anchor = { kind = 'buffer', buffer = buf, row = location.row, col = location.col },
      offset_row = -1,
      content = {
        kind = 'text',
        highlight = 'LspCodeLens',
        font_scale = 0.52,
        position = 'bottom',
        height_cells = 1,
        padding = { left = 0, right = 1, top = 0, bottom = 0 },
        spans = {
          {
            text = labels[((#ids - 1) % #labels) + 1],
            highlight = 'LspCodeLens',
          },
        },
      },
    })
    cursor = math.min(#rows, cursor + step)
  end
  imageui().flush()
  session = { ids = ids, buffer = buf }
  wait_for_baseline(vim.uv.hrtime() + 5e9)
  return #ids
end

function M.report()
  assert(session, 'no ImageUI benchmark session; run :ImageUI benchmark start')
  local current = snapshot()
  local baseline = session.baseline
  local inspected = imageui().inspect()
  local result = {
    ready = baseline ~= nil,
    widgets = #session.ids,
    active_views = 0,
    elapsed_seconds = baseline and (current.at - baseline.at) / 1e9 or 0,
    lua_kib = baseline and current.lua_kib - baseline.lua_kib or 0,
    rss_bytes = baseline and current.rss_bytes - baseline.rss_bytes or 0,
    reconciles = baseline and current.reconciles - baseline.reconciles or 0,
    backend_calls = baseline and numeric_delta(current.backend, baseline.backend) or {},
    transport = baseline and numeric_delta(current.transport, baseline.transport) or {},
    renderer = baseline and numeric_delta(current.renderer, baseline.renderer) or {},
    crop = baseline and numeric_delta(current.crop, baseline.crop) or {},
    jobs = baseline and numeric_delta(current.jobs, baseline.jobs) or {},
    reconcile_ms = inspected.performance.reconcile_ms,
    scheduler = inspected.performance.scheduler,
  }
  for _, id in ipairs(session.ids) do
    local widget = inspected.widgets[id]
    result.active_views = result.active_views + (widget and widget.views or 0)
  end
  if not vim.g.imageui_benchmark_quiet then
    vim.print(result)
  end
  return result
end

function M.stop()
  local result = session and M.report() or nil
  imageui().clear({ tag = TAG })
  session = nil
  return result
end

return M
