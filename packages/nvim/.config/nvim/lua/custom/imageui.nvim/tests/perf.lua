local failures = 0
local count = 0
local test_root = vim.env.IMAGEUI_TEST_TMP
  or vim.fs.joinpath(vim.fn.stdpath('cache'), 'imageui-perf-tests')
local make_buffer
local create_widgets

local function test_path(name)
  return vim.fs.joinpath(test_root, name)
end

local function eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      (message or 'values differ')
        .. '\nexpected: '
        .. vim.inspect(expected)
        .. '\nactual:   '
        .. vim.inspect(actual)
    )
  end
end

local function at_most(limit, actual, message)
  if actual > limit then
    error(('%s: expected <= %s, got %s'):format(message or 'limit exceeded', limit, actual))
  end
end

local function test(name, callback)
  count = count + 1
  local started = vim.uv.hrtime()
  local ok, result = xpcall(callback, debug.traceback)
  local elapsed_ms = (vim.uv.hrtime() - started) / 1e6
  if ok then
    print(('ok - %s (%.2fms) %s'):format(name, elapsed_ms, result and vim.inspect(result) or ''))
  else
    failures = failures + 1
    print(('not ok - %s (%.2fms)\n%s'):format(name, elapsed_ms, result))
  end
end

local function setup(name, opts)
  pcall(vim.cmd, 'silent! only!')
  package.loaded.imageui = nil
  local max_assets = vim.tbl_get(opts or {}, 'render', 'cache', 'max_entries') or 64
  local max_bytes = vim.tbl_get(opts or {}, 'render', 'cache', 'max_bytes') or 64 * 1024 * 1024
  local backend = require('imageui.backend.kitty_pool').new({
    send = function() end,
    available = function()
      return true
    end,
    supported = function()
      return true
    end,
    max_assets = max_assets,
    max_bytes = max_bytes,
    seed = 1000,
  })
  local ui = require('imageui').setup(vim.tbl_deep_extend('force', {
    backend = backend,
    placement = {
      debounce = 0,
      scroll_debounce = 0,
      partial = 'clip',
      occlusion = 'allow',
    },
    render = { cache = { directory = test_path(name) } },
    integrations = { codelens = { enabled = false } },
  }, opts or {}))
  return ui, backend
end

local function png_content(label, width)
  return {
    kind = 'png',
    bytes = ('png:%s:'):format(label) .. string.rep(label, 2048),
    width_cells = width or 10,
    height_cells = 1,
    pixel_width = (width or 10) * 9,
    pixel_height = 18,
  }
end

make_buffer = function(line_count)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for row = 1, line_count do
    lines[row] = ('local value_%04d = %d'):format(row, row)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  vim.cmd('redraw')
  return buf
end

create_widgets = function(ui, buf, rows, content_factory)
  local ids = {}
  for index, row in ipairs(rows) do
    ids[#ids + 1] = ui.create({
      tag = 'perf-stress',
      anchor = { kind = 'buffer', buffer = buf, row = row, col = 0 },
      offset_row = -1,
      content = content_factory and content_factory(index)
        or png_content(('lens-%02d'):format(index), 12),
    })
  end
  assert(
    vim.wait(10000, function()
      ui.flush()
      local state = ui.inspect()
      if state.renderer.pending ~= 0 then
        return false
      end
      for _, id in ipairs(ids) do
        local widget = state.widgets[id]
        if widget and widget.rendering > 0 then
          return false
        end
      end
      return true
    end, 10),
    'widget renders did not settle'
  )
  ui.flush()
  vim.wait(20)
  ui.flush()
  return ids
end

test('large offscreen registries use viewport-selective reconciliation', function()
  local ui, backend = setup('selective-registry', {
    placement = { partial = 'allow' },
  })
  local buf = make_buffer(12000)
  for row = 100, 10099 do
    ui.create({
      tag = 'selective-registry',
      anchor = { kind = 'buffer', buffer = buf, row = row, col = 0 },
      content = {
        kind = 'png',
        bytes = 'registry-' .. row,
        width_cells = 1,
        height_cells = 1,
      },
    })
  end
  local started = vim.uv.hrtime()
  ui.flush()
  local cold_ms = (vim.uv.hrtime() - started) / 1e6
  eq(0, backend.stats().transmissions, 'offscreen registry entries were rendered')
  at_most(10, cold_ms, '10k-widget offscreen reconciliation in milliseconds')
  local hit_started = vim.uv.hrtime()
  for _ = 1, 10000 do
    eq(nil, ui.hit_target(1, 1))
  end
  local hit_ms = (vim.uv.hrtime() - hit_started) / 1e6
  local hit_stats = ui.inspect().performance.interactions
  eq(0, hit_stats.candidates, 'passive widgets entered the interaction index')
  at_most(25, hit_ms, '10k hit queries with 10k passive widgets in milliseconds')

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(win, { 5000, 0 })
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zt')
  end)
  vim.cmd('redraw')
  ui.refresh()
  ui.flush()
  local visible = backend.stats()
  assert(visible.active_placements > 0, 'visible registry page produced no placements')
  at_most(100, visible.active_placements, 'selective visible working set')
  at_most(100, visible.transmissions, 'selective visible transmissions')
  ui.disable()
  return {
    widgets = 10000,
    cold_reconcile_ms = cold_ms,
    hit_query_ms = hit_ms,
    visible = visible.active_placements,
  }
end)

test('interactive hit queries inspect only row-local targets', function()
  local ui, backend = setup('interaction-index', {
    placement = { partial = 'allow' },
  })
  for row = 1, 1000 do
    ui.create({
      anchor = { kind = 'screen', row = row, col = 1 },
      content = { kind = 'png', bytes = 'shared-hit', width_cells = 1, height_cells = 1 },
      actions = { click = function() end },
    })
  end
  ui.flush()
  eq(1, backend.stats().transmissions, 'shared interactive pixels were retransmitted')
  local before = ui.inspect().performance.interactions
  local started = vim.uv.hrtime()
  for row = 1, 1000 do
    local target = ui.hit_target(row, 1)
    assert(target and target.widget_id, 'row-local interactive target was not found')
  end
  local elapsed = (vim.uv.hrtime() - started) / 1e6
  local after = ui.inspect().performance.interactions
  eq(1000, after.candidates - before.candidates, 'hit queries scanned unrelated rows')
  eq(1, after.max_candidates, 'row-local interaction buckets overlap unexpectedly')
  at_most(15, elapsed, '1000 indexed interactive hit queries in milliseconds')
  ui.disable()
  return { targets = 1000, query_ms = elapsed, max_candidates = after.max_candidates }
end)

test('overlapping scene regions cannot explode collision diagnostics', function()
  local interaction = require('imageui.interaction_geometry')
  interaction.clear_cache()
  local regions = {}
  local interactive = {}
  for index = 1, 10000 do
    local id = 'target-' .. index
    regions[index] = { id = id, visual = { x = 0, y = 0, width = 1, height = 1 } }
    interactive[id] = true
  end
  collectgarbage('collect')
  local baseline_lua = collectgarbage('count')
  local started = vim.uv.hrtime()
  local collisions = interaction.collisions(regions, interactive)
  local elapsed = (vim.uv.hrtime() - started) / 1e6
  collectgarbage('collect')
  local lua_growth = collectgarbage('count') - baseline_lua
  eq(64, #collisions, 'overlap diagnostics were not capped')
  eq(true, collisions.truncated)
  at_most(50, elapsed, '10k-region overlap validation in milliseconds')
  at_most(4096, lua_growth, 'overlap diagnostic Lua growth in KiB')
  return { regions = #regions, collisions = #collisions, elapsed_ms = elapsed, lua_kib = lua_growth }
end)

test('closed folds do not activate their hidden widget population', function()
  local ui, backend = setup('fold-selective', {
    placement = { partial = 'allow' },
  })
  local buf = make_buffer(1200)
  vim.wo.foldmethod = 'manual'
  vim.cmd('2,1001fold')
  for row = 1, 1000 do
    ui.create({
      tag = 'fold-selective',
      anchor = { kind = 'buffer', buffer = buf, row = row, col = 0 },
      content = {
        kind = 'png',
        bytes = 'fold-' .. row,
        width_cells = 1,
        height_cells = 1,
      },
    })
  end
  ui.flush()
  local stats = backend.stats()
  eq(1, stats.transmissions, 'folded hidden rows transmitted image assets')
  eq(1, stats.active_placements, 'folded hidden rows created overlapping placements')
  ui.disable()
  return stats
end)

test('manager assets follow the visible working set instead of visited history', function()
  local ui, backend = setup('manager-assets', {
    placement = { partial = 'allow' },
    render = { cache = { max_entries = 32 } },
  })
  local buf = make_buffer(800)
  local rows = {}
  for row = 1, 600 do
    rows[#rows + 1] = row
  end
  local ids = create_widgets(ui, buf, rows, function(index)
    return {
      kind = 'png',
      bytes = 'visited-' .. index,
      width_cells = 1,
      height_cells = 1,
    }
  end)
  local win = vim.api.nvim_get_current_win()
  for top = 1, 581, 20 do
    vim.api.nvim_win_set_cursor(win, { top, 0 })
    vim.api.nvim_win_call(win, function()
      vim.cmd('normal! zt')
    end)
    vim.cmd('redraw')
    ui.refresh()
    ui.flush()
  end
  local inspected = ui.inspect()
  local retained_assets = 0
  for _, id in ipairs(ids) do
    retained_assets = retained_assets + inspected.widgets[id].assets
  end
  at_most(100, retained_assets, 'manager asset references after visiting 600 widgets')
  local terminal_assets = backend.stats().assets
  at_most(32, terminal_assets, 'terminal pool after visiting 600 widgets')
  ui.disable()
  return { visited = #ids, manager_assets = retained_assets, terminal_assets = terminal_assets }
end)

test('cold viewport churn keeps render work bounded', function()
  local ui = setup('cold-queue-perf', {
    placement = { partial = 'allow' },
    render = { max_jobs = 1, max_queue = 32 },
  })
  local jobs = require('imageui.renderer.jobs')
  jobs.setup(ui.config, function()
    return { kill = function() end }
  end)
  local buf = make_buffer(2000)
  for row = 0, 1999 do
    ui.create({
      anchor = { kind = 'buffer', buffer = buf, row = row, col = 0 },
      content = {
        kind = 'text',
        highlight = 'Comment',
        spans = { { text = 'cold-' .. row, highlight = 'Comment' } },
      },
    })
  end
  local win = vim.api.nvim_get_current_win()
  local peak_pending = 0
  for top = 1, 1981, 20 do
    vim.api.nvim_win_set_cursor(win, { top, 0 })
    vim.api.nvim_win_call(win, function()
      vim.cmd('normal! zt')
    end)
    vim.cmd('redraw')
    ui.refresh()
    ui.flush()
    local renderer = require('imageui.renderer.rasterizer').stats()
    peak_pending = math.max(peak_pending, renderer.pending)
    at_most(32, jobs.stats().queued, 'cold render queue')
    at_most(64, renderer.pending, 'cold pending render subscriptions')
  end
  local stats = require('imageui.renderer.rasterizer').stats()
  assert(stats.cancelled > 0, 'cold scroll did not cancel obsolete work')
  ui.disable()
  jobs.setup(require('imageui.config').normalize())
  return {
    widgets = 2000,
    transitions = 100,
    peak_pending = peak_pending,
    cancelled = stats.cancelled,
  }
end)

test('visible position updates do not retransmit image bytes', function()
  local ui, backend = setup('position-only', {
    placement = { partial = 'allow' },
  })
  local buf = make_buffer(200)
  create_widgets(ui, buf, { 2, 4, 6, 8, 10 })
  local initial = backend.stats()
  eq(5, initial.transmissions)
  for step = 1, 1000 do
    for id, widget in pairs(require('imageui.manager').all()) do
      ui.update(id, { offset_col = step % 2 })
      assert(widget)
    end
    ui.flush()
  end
  local after = backend.stats()
  eq(initial.transmissions, after.transmissions, 'moves retransmitted PNG data')
  eq(initial.transmitted_bytes, after.transmitted_bytes, 'move byte traffic grew')
  eq(0, after.unplaces, 'moves unplaced terminal images')
  at_most(5, after.active_placements, 'active terminal placements')
  ui.disable()
  return after
end)

test('visible-offscreen churn has bounded terminal allocations', function()
  local ui, backend = setup('offscreen-churn')
  local buf = make_buffer(400)
  local win = vim.api.nvim_get_current_win()
  create_widgets(ui, buf, { 2, 4, 6, 8, 10 })
  local initial = backend.stats()
  local function transition(cycle, verify)
    local topline = cycle % 2 == 0 and 1 or 200
    vim.api.nvim_win_set_cursor(win, { topline, 0 })
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = topline })
    end)
    vim.cmd('redraw')
    ui.refresh()
    ui.flush()
    if verify and topline == 200 then
      eq(0, backend.stats().active_placements, 'offscreen images left ghost placements')
    elseif verify then
      eq(5, backend.stats().active_placements, 'visible images were not restored')
    end
  end
  for cycle = 1, 100 do
    transition(cycle, true)
  end
  collectgarbage('collect')
  local baseline_lua = collectgarbage('count')
  local baseline_rss = vim.uv.resident_set_memory()
  local durations = {}
  for cycle = 1, 5000 do
    local started = vim.uv.hrtime()
    transition(cycle, cycle <= 10 or cycle > 4990)
    durations[#durations + 1] = (vim.uv.hrtime() - started) / 1e6
  end
  collectgarbage('collect')
  local lua_growth = collectgarbage('count') - baseline_lua
  local rss_growth = vim.uv.resident_set_memory() - baseline_rss
  table.sort(durations)
  local p95 = durations[math.ceil(#durations * 0.95)]
  at_most(2048, lua_growth, 'Lua heap growth in KiB')
  at_most(32 * 1024 * 1024, rss_growth, 'Neovim RSS growth in bytes')
  at_most(5, p95, 'settled viewport transition p95 in milliseconds')
  local after = backend.stats()
  at_most(
    initial.transmissions,
    after.transmissions,
    'offscreen cycles allocated new terminal images'
  )
  at_most(initial.transmitted_bytes, after.transmitted_bytes, 'offscreen byte traffic grew')
  at_most(5, after.assets, 'terminal image assets')
  at_most(5, after.active_placements, 'active terminal placements')
  after.benchmark = {
    transitions = #durations,
    p95_ms = p95,
    lua_growth_kib = lua_growth,
    rss_growth_bytes = rss_growth,
  }
  ui.disable()
  return after
end)

test('same-buffer split focus churn preserves both image sets', function()
  local ui, backend = setup('split-focus', {
    placement = { partial = 'allow' },
  })
  local buf = make_buffer(200)
  local first = vim.api.nvim_get_current_win()
  local second = vim.api.nvim_open_win(buf, false, { split = 'right' })
  vim.cmd('redraw')
  create_widgets(ui, buf, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, function(index)
    return {
      kind = 'text',
      highlight = 'LspCodeLens',
      font_scale = 0.52,
      position = 'bottom',
      height_cells = 1,
      padding = { left = 0, right = 1, top = 0, bottom = 0 },
      spans = { { text = index .. ' references', highlight = 'LspCodeLens' } },
    }
  end)
  local initial = backend.stats()
  eq(24, initial.active_placements, 'each widget should have one image per split')
  for cycle = 1, 200 do
    vim.api.nvim_set_current_win(cycle % 2 == 0 and first or second)
    vim.api.nvim_exec_autocmds('WinEnter', {})
    ui.flush()
  end
  local after = backend.stats()
  eq(initial.transmissions, after.transmissions, 'focus changes retransmitted split images')
  eq(initial.transmitted_bytes, after.transmitted_bytes, 'focus byte traffic grew')
  eq(0, after.unplaces, 'focus changes unplaced split images')
  eq(24, after.active_placements, 'both splits lost stable image placements')
  ui.disable()
  return after
end)

test('CodeLens-shaped text widgets scroll across two splits without retransmission', function()
  local ui, backend = setup('text-split-scroll')
  local buf = make_buffer(400)
  local first = vim.api.nvim_get_current_win()
  local second = vim.api.nvim_open_win(buf, false, { split = 'right' })
  vim.cmd('redraw')
  local rows = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
  create_widgets(ui, buf, rows, function(index)
    return {
      kind = 'text',
      highlight = 'LspCodeLens',
      font_scale = 0.52,
      position = 'bottom',
      height_cells = 1,
      padding = { left = 0, right = 1, top = 0, bottom = 0 },
      spans = {
        {
          text = ({ '1 reference', '2 references', '4 references', '8 references' })[((index - 1) % 4) + 1],
          highlight = 'LspCodeLens',
        },
      },
    }
  end)
  local initial = backend.stats()
  eq(24, initial.active_placements)
  local function move(topline)
    for _, win in ipairs({ first, second }) do
      vim.api.nvim_win_set_cursor(win, { topline, 0 })
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = topline })
      end)
    end
    vim.cmd('redraw')
    ui.refresh()
    ui.flush()
  end
  for _ = 1, 250 do
    move(200)
    eq(0, backend.stats().active_placements, 'offscreen text left ghost placements')
    move(1)
    eq(24, backend.stats().active_placements, 'text placements did not return to both splits')
  end
  local after = backend.stats()
  eq(initial.transmissions, after.transmissions, 'text scroll retransmitted raster assets')
  eq(initial.transmitted_bytes, after.transmitted_bytes, 'text scroll PNG byte traffic grew')
  eq(initial.assets, after.assets, 'text scroll grew the terminal asset pool')
  ui.disable()
  return after
end)

test('CodeLens integration redraw relayout stays bounded across a large result set', function()
  local ui, backend = setup('codelens-integration', {
    placement = { partial = 'allow' },
    integrations = {
      codelens = {
        enabled = false,
        debounce = 60000,
        relayout_debounce = 0,
        placement_order = { 'overlay' },
      },
    },
  })
  local buf = make_buffer(5200)
  local codelens = require('imageui.integrations.codelens')
  codelens.enable()
  local apply
  for index = 1, 64 do
    local name, value = debug.getupvalue(codelens.refresh, index)
    if not name then
      break
    end
    if name == 'apply' then
      apply = value
      break
    end
  end
  assert(apply, 'could not locate CodeLens reconciler')
  local results = {}
  for row = 1, 5000 do
    results[#results + 1] = {
      client_id = 999999,
      lens = {
        range = { start = { line = row, character = 0 } },
        command = { title = '3 references', command = 'test.references' },
      },
    }
  end
  apply(buf, results)
  assert(
    vim.wait(10000, function()
      ui.flush()
      return ui.inspect().renderer.pending == 0
    end, 10),
    'initial CodeLens renders did not settle'
  )
  local initial = backend.stats()
  local win = vim.api.nvim_get_current_win()
  local manager = require('imageui.manager')
  local observer = manager._redraw_observers().codelens
  assert(type(observer) == 'function', 'CodeLens redraw observer is unavailable')
  local durations = {}
  for cycle = 1, 200 do
    local top = ((cycle - 1) % 20) * 20 + 1
    vim.api.nvim_win_set_cursor(win, { top, 0 })
    vim.api.nvim_win_call(win, function()
      vim.cmd('normal! zt')
    end)
    vim.cmd('redraw')
    local started = vim.uv.hrtime()
    observer()
    codelens._flush_relayout()
    durations[#durations + 1] = (vim.uv.hrtime() - started) / 1e6
  end
  table.sort(durations)
  local p95 = durations[math.ceil(#durations * 0.95)]
  at_most(10, p95, '5000-result CodeLens redraw relayout p95 in milliseconds')
  local after = backend.stats()
  eq(initial.transmissions, after.transmissions, 'CodeLens relayout retransmitted shared text')
  eq(initial.transmitted_bytes, after.transmitted_bytes, 'CodeLens relayout byte traffic grew')
  codelens.disable()
  ui.disable()
  return { results = #results, transitions = #durations, p95_ms = p95, assets = after.assets }
end)

test('CodeLens redraw relayout skips large closed-fold interiors', function()
  local ui, backend = setup('codelens-folded-integration', {
    placement = { partial = 'allow' },
    integrations = {
      codelens = {
        enabled = false,
        debounce = 60000,
        relayout_debounce = 0,
        placement_order = { 'overlay' },
      },
    },
  })
  local buf = make_buffer(5200)
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].foldmethod = 'manual'
  vim.cmd('2,5001fold')
  vim.cmd('redraw')
  eq(2, vim.fn.foldclosed(2), 'stress fold was not closed')

  local codelens = require('imageui.integrations.codelens')
  codelens.enable()
  local apply
  for index = 1, 64 do
    local name, value = debug.getupvalue(codelens.refresh, index)
    if not name then
      break
    end
    if name == 'apply' then
      apply = value
      break
    end
  end
  assert(apply, 'could not locate CodeLens reconciler')
  local results = {}
  for row = 1, 5000 do
    results[#results + 1] = {
      client_id = 999999,
      lens = {
        range = { start = { line = row, character = 0 } },
        command = { title = '3 references', command = 'test.references' },
      },
    }
  end
  apply(buf, results)
  assert(
    vim.wait(10000, function()
      ui.flush()
      return ui.inspect().renderer.pending == 0
    end, 10),
    'initial folded CodeLens render did not settle'
  )
  local info = vim.fn.getwininfo(win)[1] or {}
  assert((info.botline or 0) > 5000, 'closed fold did not span the measured buffer range')
  local initial = backend.stats()
  at_most(1, initial.active_placements, 'closed fold activated hidden CodeLens widgets')

  local manager = require('imageui.manager')
  local observer = manager._redraw_observers().codelens
  assert(type(observer) == 'function', 'CodeLens redraw observer is unavailable')
  local durations = {}
  for _ = 1, 200 do
    local started = vim.uv.hrtime()
    observer()
    codelens._flush_relayout()
    durations[#durations + 1] = (vim.uv.hrtime() - started) / 1e6
  end
  table.sort(durations)
  local p95 = durations[math.ceil(#durations * 0.95)]
  at_most(10, p95, '5000-result closed-fold CodeLens relayout p95 in milliseconds')
  local after = backend.stats()
  eq(initial.transmissions, after.transmissions, 'folded CodeLens relayout retransmitted text')
  eq(initial.transmitted_bytes, after.transmitted_bytes, 'folded CodeLens byte traffic grew')
  eq(initial.active_placements, after.active_placements, 'folded CodeLens placements grew')
  codelens.disable()
  ui.disable()
  return {
    results = #results,
    transitions = #durations,
    p95_ms = p95,
    fold_bottom = info.botline,
    active_placements = after.active_placements,
  }
end)

test('pooled Kitty transport separates assets from placements', function()
  local wire = {}
  local backend = require('imageui.backend.kitty_pool').new({
    send = function(data)
      wire[#wire + 1] = data
    end,
    available = function()
      return true
    end,
    max_assets = 4,
    seed = 500,
  })
  local first = backend.set('shared-png', { row = 2, col = 3, width = 4, height = 1 }, {
    key = 'shared',
  })
  local second = backend.set('shared-png', { row = 4, col = 8, width = 4, height = 1 }, {
    key = 'shared',
  })
  local warm = backend.stats()
  eq(1, warm.transmissions)
  eq(2, warm.active_placements)
  backend.update(first, { row = 3 })
  backend.delete(first)
  local asset = backend._assets().shared
  local delete_command = table.concat(wire)
  assert(
    delete_command:find(('a=d,d=i,i=%d,p=%d,q=2'):format(asset.image_id, first), 1, true),
    'placement delete did not target the exact image/placement pair'
  )
  local reused = backend.set('shared-png', { row = 6, col = 2, width = 4, height = 1 }, {
    key = 'shared',
  })
  eq(first, reused, 'dormant placement ID was not reused')
  local after = backend.stats()
  eq(1, after.transmissions)
  eq(2, after.active_placements)
  eq(1, after.unplaces)
  eq(1, after.updates)
  local protocol = table.concat(wire)
  assert(protocol:find('a=t', 1, true), 'wire trace has no image transmission')
  assert(protocol:find('d=i', 1, true), 'wire trace has no placement-only delete')
  assert(not protocol:find('N=1', 1, true), 'pooled assets were incorrectly marked transient')
  assert(not protocol:find('?25', 1, true), 'image placement changed Neovim cursor visibility')
  backend.delete(reused)
  backend.delete(second)
  backend.clear()
  protocol = table.concat(wire)
  assert(protocol:find('d=I', 1, true), 'wire trace has no hard asset release')
  return after
end)

test('tmux pane-origin churn moves placements without upload growth', function()
  local origin = 0
  local wire_calls = 0
  local backend = require('imageui.backend.kitty_pool').new({
    tmux = 'on',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_geometry = function()
      return { valid = true, row = origin, col = origin % 3 }
    end,
    send = function()
      wire_calls = wire_calls + 1
    end,
    available = function()
      return true
    end,
    max_assets = 32,
    seed = 800,
  })
  for index = 1, 12 do
    backend.set('tmux-png-' .. index, { row = index, col = index }, { key = 'tmux-' .. index })
  end
  local warm = backend.stats()
  local started = vim.uv.hrtime()
  for transition = 1, 500 do
    origin = transition % 7
    local ok, err = backend.refresh_transport()
    assert(ok, err)
  end
  local elapsed_ms = (vim.uv.hrtime() - started) / 1e6
  local after = backend.stats()
  eq(warm.transmissions, after.transmissions, 'tmux origin changes retransmitted image data')
  eq(warm.transmitted_bytes, after.transmitted_bytes, 'tmux origin changes grew PNG traffic')
  eq(12, after.active_placements)
  eq(12 * 500, after.updates)
  eq(24 + 500, wire_calls, 'tmux geometry updates were not batched per transition')
  eq(500, after.control_batches - warm.control_batches)
  eq(500, after.tmux_envelopes - warm.tmux_envelopes)
  eq(12, after.max_batch_commands)
  at_most(1000, elapsed_ms, '500 tmux geometry transitions in milliseconds')
  backend.clear()
  return {
    transitions = 500,
    placements = 12,
    transmissions = after.transmissions,
    updates = after.updates,
    control_batches = after.control_batches - warm.control_batches,
    tmux_envelopes = after.tmux_envelopes - warm.tmux_envelopes,
    elapsed_ms = elapsed_ms,
  }
end)

test('WezTerm-safe reposition churn stays batched and upload-stable', function()
  local checking_updates = false
  local wire_calls = 0
  local backend = require('imageui.backend.kitty_pool').new({
    term_program = 'WezTerm',
    safe_reposition = 'auto',
    send = function(data)
      wire_calls = wire_calls + 1
      if checking_updates and data:find('a=p', 1, true) then
        local _, places = data:gsub('a=p', '')
        local _, deletes = data:gsub('d=i', '')
        eq(places, deletes, 'a WezTerm placement was replaced without first being deleted')
      end
    end,
    available = function()
      return true
    end,
    max_assets = 32,
    seed = 810,
  })
  local ids = {}
  for index = 1, 12 do
    ids[index] = backend.set(
      'wezterm-png-' .. index,
      { row = index, col = index },
      { key = 'wezterm-' .. index }
    )
  end
  local warm = backend.stats()
  checking_updates = true
  local started = vim.uv.hrtime()
  for transition = 1, 1000 do
    backend.begin_batch()
    for index, id in ipairs(ids) do
      backend.update(id, { row = ((index + transition) % 20) + 1 })
    end
    backend.end_batch()
  end
  local elapsed_ms = (vim.uv.hrtime() - started) / 1e6
  local after = backend.stats()
  eq(warm.transmissions, after.transmissions)
  eq(warm.transmitted_bytes, after.transmitted_bytes)
  eq(12 * 1000, after.updates)
  eq(12 * 1000, after.safe_repositions)
  eq(1000, after.control_batches - warm.control_batches)
  eq(24 + 1000, wire_calls)
  at_most(1000, elapsed_ms, '1000 WezTerm-safe placement frames in milliseconds')
  checking_updates = false
  backend.clear()
  return {
    transitions = 1000,
    placements = 12,
    safe_repositions = after.safe_repositions,
    control_batches = after.control_batches - warm.control_batches,
    elapsed_ms = elapsed_ms,
  }
end)

test('pooled Kitty protocol IDs remain unique past upstream collision threshold', function()
  collectgarbage('collect')
  local baseline_lua = collectgarbage('count')
  local transmitted_ids = {}
  local placement_ids = {}
  local backend = require('imageui.backend.kitty_pool').new({
    send = function(data)
      if data:find('a=t', 1, true) then
        local id = tonumber(data:match('[,]i=(%d+)') or data:match('i=(%d+)'))
        assert(id and not transmitted_ids[id], 'image protocol ID was reused')
        transmitted_ids[id] = true
      elseif data:find('a=p', 1, true) then
        local id = tonumber(data:match('[,]p=(%d+)') or data:match('p=(%d+)'))
        assert(id and not placement_ids[id], 'placement protocol ID was reused')
        placement_ids[id] = true
      end
    end,
    available = function()
      return true
    end,
    max_assets = 1,
    seed = 0x7fff,
  })
  local seen = {}
  for index = 1, 20000 do
    local id = backend.set('x', { row = 1, col = 1 }, { key = 'asset-' .. index })
    assert(not seen[id], ('placement ID collided at allocation %d'):format(index))
    seen[id] = true
    backend.delete(id)
  end
  local stats = backend.stats()
  eq(20000, stats.transmissions)
  at_most(1, stats.assets, 'pooled asset cache')
  eq(0, stats.active_placements)
  at_most(2, stats.live_protocol_ids, 'live protocol ID bookkeeping')
  collectgarbage('collect')
  at_most(4096, collectgarbage('count') - baseline_lua, '20k-allocation Lua growth in KiB')
  backend.clear()
  return {
    allocations = 20000,
    image_ids = vim.tbl_count(transmitted_ids),
    placement_ids = vim.tbl_count(placement_ids),
    hard_deletes = stats.hard_deletes,
  }
end)

test('decoded terminal asset budget remains bounded under unique churn', function()
  local function u32(value)
    return string.char(
      math.floor(value / 0x1000000) % 256,
      math.floor(value / 0x10000) % 256,
      math.floor(value / 0x100) % 256,
      value % 256
    )
  end
  local png = '\137PNG\r\n\26\n' .. u32(13) .. 'IHDR' .. u32(128) .. u32(128)
  local backend = require('imageui.backend.kitty_pool').new({
    send = function() end,
    available = function()
      return true
    end,
    max_assets = 128,
    max_bytes = 64 * 1024,
    seed = 9000,
  })
  for index = 1, 5000 do
    local id = backend.set(png, { row = 1, col = 1 }, { key = 'decoded-' .. index })
    backend.delete(id)
  end
  local stats = backend.stats()
  eq(1, stats.assets)
  eq(64 * 1024, stats.resident_decoded_bytes)
  at_most(2, stats.live_protocol_ids, 'decoded-budget live IDs')
  backend.clear()
  return stats
end)

test('runtime vim.ui.img wire behavior is measured when available', function()
  if not (vim.ui and vim.ui.img and type(vim.ui.img.set) == 'function') then
    return { skipped = 'vim.ui.img unavailable' }
  end
  local original_send = vim.api.nvim_ui_send
  local wire = {}
  vim.api.nvim_ui_send = function(data)
    wire[#wire + 1] = data
  end
  local ok, result = xpcall(function()
    local id = vim.ui.img.set('runtime-wire-probe', { row = 2, col = 3, width = 2, height = 1 })
    vim.ui.img.set(id, { row = 4 })
    vim.ui.img.del(id)
    local protocol = table.concat(wire)
    return {
      calls = #wire,
      transmits = select(2, protocol:gsub('a=t', '')),
      places = select(2, protocol:gsub('a=p', '')),
      soft_delete = protocol:find('d=i', 1, true) ~= nil,
      hard_delete = protocol:find('d=I', 1, true) ~= nil,
      wire_bytes = #protocol,
    }
  end, debug.traceback)
  vim.api.nvim_ui_send = original_send
  if not ok then
    error(result)
  end
  eq(1, result.transmits, 'runtime set did not transmit exactly once')
  eq(2, result.places, 'runtime update did not reuse the placement')
  return result
end)

print(('1..%d'):format(count))
if failures > 0 then
  error(('%d performance tests failed'):format(failures))
end
print(('all %d performance tests passed'):format(count))
