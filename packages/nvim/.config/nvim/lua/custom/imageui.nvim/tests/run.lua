local failures = 0
local count = 0
local test_root = vim.env.IMAGEUI_TEST_TMP
  or vim.fs.joinpath(vim.fn.stdpath('cache'), 'imageui-tests')

local function test_path(name)
  return vim.fs.joinpath(test_root, name)
end

local function inspect(value)
  return vim.inspect(value)
end

local function eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      (message or 'values differ')
        .. '\nexpected: '
        .. inspect(expected)
        .. '\nactual:   '
        .. inspect(actual)
    )
  end
end

local function truthy(value, message)
  if not value then
    error(message or 'expected a truthy value')
  end
end

local function test(name, callback)
  count = count + 1
  local ok, err = xpcall(callback, debug.traceback)
  if ok then
    print('ok - ' .. name)
  else
    failures = failures + 1
    print('not ok - ' .. name .. '\n' .. err)
  end
end

test('geometry intersects and subtracts without overlap', function()
  local geometry = require('imageui.util.geometry')
  local source = { top = 1, left = 1, bottom = 5, right = 5 }
  local cut = { top = 2, left = 2, bottom = 4, right = 4 }
  eq({ top = 2, left = 2, bottom = 4, right = 4 }, geometry.intersect(source, cut))
  local pieces = geometry.subtract(source, cut)
  eq(4, #pieces)
  local area = 0
  for _, piece in ipairs(pieces) do
    area = area + geometry.width(piece) * geometry.height(piece)
    eq(nil, geometry.intersect(piece, cut))
  end
  eq(16, area)
end)

test('config deep-merges and validates enums', function()
  local config = require('imageui.config').normalize({
    placement = { debounce = 3 },
    integrations = { codelens = { enabled = true } },
  })
  eq(3, config.placement.debounce)
  eq('clip', config.placement.partial)
  eq(32, config.placement.scroll_debounce)
  eq('auto', config.transport.safe_reposition)
  eq(4, config.render.max_jobs)
  eq(256, config.render.max_queue)
  eq(64 * 1024 * 1024, config.render.cache.max_bytes)
  eq(true, config.integrations.codelens.enabled)
  eq('smart', config.integrations.codelens.layout)
  eq(50, config.integrations.codelens.relayout_debounce)
  eq(false, config.integrations.codelens.right.always)
  eq('window', config.integrations.codelens.right.anchor)
  eq('before', config.integrations.codelens.right.side)
  eq(2, config.integrations.codelens.right.distance)
  local ok = pcall(require('imageui.config').normalize, { placement = { partial = 'broken' } })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, { placement = { debounce = -1 } })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, {
    integrations = { codelens = { right = { anchor = 'cursor' } } },
  })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, {
    integrations = { codelens = { right = { distance = 1.5 } } },
  })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, {
    integrations = { codelens = { right = { side = 'center' } } },
  })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, {
    integrations = { codelens = { relayout_debounce = -1 } },
  })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, { placement = { scroll_debounce = -1 } })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, {
    transport = { safe_reposition = 'broken' },
  })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, { render = { max_jobs = 1.5 } })
  eq(false, ok)
  ok = pcall(require('imageui.config').normalize, { render = { max_queue = 0 } })
  eq(false, ok)
end)

test('scheduler frame throttle coalesces without restarting pending work', function()
  local runs = 0
  local scheduler = require('imageui.util.scheduler').new(1000, function()
    runs = runs + 1
  end)
  scheduler:schedule()
  scheduler:schedule()
  scheduler:schedule()
  local pending = scheduler:stats()
  eq(true, pending.pending)
  eq(3, pending.requests)
  eq(2, pending.coalesced)
  scheduler:flush()
  local finished = scheduler:stats()
  eq(1, runs)
  eq(1, finished.runs)
  eq(false, finished.pending)
  scheduler:close()
end)

test('health check runs before plugin setup', function()
  package.loaded.imageui = nil
  local plugin = require('imageui')
  eq(false, plugin.is_configured())
  local ok, err = pcall(require('imageui.health').check)
  truthy(ok, err)
end)

test('weighted caches evict by memory budget as well as entry count', function()
  local cache = require('imageui.cache').new(10, {
    max_weight = 5,
    weigh = function(_, value)
      return #value
    end,
  })
  cache:set('first', 'abc')
  cache:set('second', 'def')
  eq(nil, cache:get('first'))
  eq('def', cache:get('second'))
  eq(3, cache:weight())
  cache:set('oversized', '123456')
  eq(0, cache:size(), 'an individually oversized cache value was retained')
  eq(0, cache:weight())
end)

test('renderer job queue enforces global process backpressure', function()
  local jobs = require('imageui.renderer.jobs')
  local config = require('imageui.config').normalize({ render = { max_jobs = 2 } })
  local started = {}
  local callbacks = 0
  jobs.setup(config, function(_, _, callback)
    started[#started + 1] = callback
    return { kill = function() end }
  end)
  for index = 1, 10 do
    jobs.run({ 'job', tostring(index) }, {}, function()
      callbacks = callbacks + 1
    end)
  end
  local stats = jobs.stats()
  eq(2, stats.running)
  eq(8, stats.queued)
  eq(2, stats.peak_running)
  started[1]({ code = 0, signal = 0, stdout = '', stderr = '' })
  stats = jobs.stats()
  eq(2, stats.running)
  eq(7, stats.queued)
  eq(1, callbacks)
  jobs.setup(require('imageui.config').normalize())
end)

test('pooled Kitty backend rolls back failed terminal writes', function()
  local sends = 0
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 42,
    send = function()
      sends = sends + 1
      if sends == 2 then
        error('forced placement write failure')
      end
    end,
    available = function()
      return true
    end,
  })
  local ok = pcall(backend.set, 'png', { row = 1, col = 1 }, { key = 'failed' })
  eq(false, ok)
  local stats = backend.stats()
  eq(0, stats.assets)
  eq(0, stats.active_placements)
  eq(0, stats.live_protocol_ids)

  local fail_first = require('imageui.backend.kitty_pool').new({
    seed = 52,
    send = function()
      error('forced transmission write failure')
    end,
    available = function()
      return true
    end,
  })
  ok = pcall(fail_first.set, 'png', { row = 1, col = 1 }, { key = 'failed-first' })
  eq(false, ok)
  stats = fail_first.stats()
  eq(0, stats.assets)
  eq(0, stats.live_protocol_ids)
end)

test('tmux transport projects pane cells and wraps cursor placement atomically', function()
  local tmux = require('imageui.transport.tmux')
  eq(false, tmux.detected(''))
  eq(true, tmux.detected('/tmp/tmux-1000/default,1,0'))
  eq(false, tmux.resolve('auto', ''))
  eq(true, tmux.resolve('auto', '/tmp/tmux-1000/default,1,0'))

  local status = tmux.status({
    env = '/tmp/tmux-1000/default,1,0',
    pane = '%7',
    executable = function()
      return true
    end,
    run = function(command)
      eq('tmux', command[1])
      truthy(command[3] == '-pAv' or command[3] == '-sv')
      if command[3] == '-pAv' then
        eq('-t', command[4])
        eq('%7', command[5])
        eq('allow-passthrough', command[6])
      end
      return { code = 0, stdout = 'on\n', stderr = '' }
    end,
  })
  eq(true, status.enabled)
  eq('on', status.value)
  eq('pane', status.scope)
  eq(true, status.focus_events)

  local geometry = tmux.geometry({
    env = '/tmp/tmux-1000/default,1,0',
    pane = '%7',
    executable = function()
      return true
    end,
    run = function(command)
      eq('display-message', command[2])
      eq('-t', command[4])
      eq('%7', command[5])
      return {
        code = 0,
        stdout = '11\t3\t2\t1\t2\ttop\t/dev/pts/2\t120\t40\t1\twezterm\tRGB,ccolour,sync\n',
        stderr = '',
      }
    end,
  })
  eq(true, geometry.valid)
  eq(4, geometry.row)
  eq(9, geometry.col)
  eq('wezterm', geometry.client_termname)
  eq('RGB,ccolour,sync', geometry.client_termfeatures)
  eq({ 8, 16 }, { tmux.project(geometry, 4, 7) })

  local wire = {}
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 40,
    tmux = 'on',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_geometry = geometry,
    send = function(data)
      wire[#wire + 1] = data
    end,
    available = function()
      return true
    end,
  })
  local id = backend.set('png', {
    row = 4,
    col = 7,
    width = 2,
    height = 1,
  }, { key = 'tmux' })
  eq(true, backend.stats().tmux_passthrough)
  eq(2, #wire)
  truthy(wire[1]:find('\027Ptmux;\027\027_G', 1, true) == 1)
  truthy(wire[1]:find('\027\027\\\027\\', 1, true) ~= nil)
  truthy(wire[2]:find('\027Ptmux;\027\0277\027\027[8;16H\027\027_G', 1, true) == 1)
  truthy(wire[2]:sub(-8) == '\027\027\\\027\0278\027\\')

  backend.delete(id)
  truthy(wire[3]:find('\027Ptmux;\027\027_G', 1, true) == 1)
  backend.clear()
end)

test('tmux transport pauses hidden-pane writes and resumes without losing pool state', function()
  local wire = {}
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 48,
    tmux = 'on',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_geometry = { valid = true, row = 0, col = 0 },
    send = function(data)
      wire[#wire + 1] = data
    end,
    available = function()
      return true
    end,
  })
  local id = backend.set('first', { row = 1, col = 1 }, { key = 'first' })
  eq(true, backend.set_focus(false))
  local hidden, reason = backend.set('hidden', { row = 2, col = 1 }, { key = 'hidden' })
  eq(nil, hidden)
  truthy(reason:find('deferred', 1, true))
  eq(1, backend.stats().assets)
  eq(2, #wire)
  eq(true, backend.set_focus(true))
  eq(true, backend.delete(id))
  eq(true, backend.clear())
end)

test('tmux geometry changes move placements without retransmitting image data', function()
  local wire = {}
  local origin_row = 0
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 49,
    tmux = 'on',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_geometry = function()
      return { valid = true, row = origin_row, col = 3 }
    end,
    send = function(data)
      wire[#wire + 1] = data
    end,
    available = function()
      return true
    end,
  })
  backend.set('first', { row = 2, col = 4 }, { key = 'first' })
  truthy(wire[2]:find('\027\027[2;7H', 1, true) ~= nil)
  origin_row = 5
  eq(true, backend.refresh_transport())
  truthy(wire[3]:find('\027\027[7;7H', 1, true) ~= nil)
  local stats = backend.stats()
  eq(1, stats.transmissions)
  eq(1, stats.updates)
  eq(3, #wire)
  backend.clear()
end)

test('tmux batches and coalesces warm placement moves into one envelope', function()
  local wire = {}
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 50,
    tmux = 'on',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_geometry = { valid = true, row = 0, col = 0 },
    safe_reposition = 'off',
    send = function(data)
      wire[#wire + 1] = data
    end,
    available = function()
      return true
    end,
  })
  local ids = {}
  for index = 1, 12 do
    ids[index] = backend.set(
      'batch-' .. index,
      { row = index, col = index },
      { key = 'batch-' .. index }
    )
  end
  eq(24, #wire)
  backend.begin_batch()
  for index, id in ipairs(ids) do
    backend.update(id, { row = index + 1 })
  end
  backend.update(ids[1], { row = 99 })
  backend.update(ids[1], { row = 100 })
  backend.end_batch()
  eq(25, #wire)
  local _, placements = wire[25]:gsub('a=p', '')
  eq(12, placements)
  truthy(wire[25]:find('\027\027[100;1H', 1, true))
  local stats = backend.stats()
  eq(12, stats.transmissions)
  eq(14, stats.updates)
  eq(24, stats.control_commands)
  eq(2, stats.coalesced_control_commands)
  eq(13, stats.control_batches)
  eq(25, stats.tmux_envelopes)
  backend.clear()
end)

test('tmux control batches respect the configured escape-sequence ceiling', function()
  local wire = {}
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 501,
    tmux = 'on',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_geometry = { valid = true, row = 0, col = 0 },
    safe_reposition = 'off',
    max_control_batch_bytes = 180,
    send = function(data)
      wire[#wire + 1] = data
    end,
    available = function()
      return true
    end,
  })
  local ids = {}
  for index = 1, 12 do
    ids[index] = backend.set(
      'bounded-' .. index,
      { row = index, col = index },
      { key = 'bounded-' .. index }
    )
  end
  local warm = backend.stats()
  local warm_writes = #wire
  backend.begin_batch()
  for index, id in ipairs(ids) do
    backend.update(id, { row = index + 20 })
  end
  backend.end_batch()
  local stats = backend.stats()
  local batches = stats.control_batches - warm.control_batches
  truthy(batches > 1)
  eq(batches, #wire - warm_writes)
  eq(batches, stats.tmux_envelopes - warm.tmux_envelopes)
  truthy(stats.max_batch_bytes <= 180)
  backend.clear()
end)

test('WezTerm-safe moves delete an old placement before replacing it', function()
  local wire = {}
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 51,
    term_program = 'WezTerm',
    safe_reposition = 'auto',
    send = function(data)
      wire[#wire + 1] = data
    end,
    available = function()
      return true
    end,
  })
  local id = backend.set('safe', { row = 1, col = 1 }, { key = 'safe' })
  backend.begin_batch()
  backend.update(id, { row = 2 })
  backend.update(id, { row = 3 })
  backend.end_batch()
  eq(3, #wire)
  local delete_at = wire[3]:find('d=i', 1, true)
  local place_at = wire[3]:find('a=p', 1, true)
  truthy(delete_at and place_at and delete_at < place_at)
  local _, deletes = wire[3]:gsub('d=i', '')
  local _, places = wire[3]:gsub('a=p', '')
  eq(1, deletes)
  eq(1, places)
  truthy(wire[3]:find('\027[3;1H', 1, true))
  local stats = backend.stats()
  eq(true, stats.wezterm_detected)
  eq(true, stats.safe_reposition)
  eq(2, stats.safe_repositions)
  eq(2, stats.coalesced_control_commands)
  backend.clear()
end)

test('tmux auto transport refuses blocked passthrough and explicit on can force it', function()
  local unavailable = require('imageui.backend.kitty_pool').new({
    tmux = 'auto',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_status = { detected = true, executable = true, enabled = false, value = 'off' },
    tmux_geometry = { valid = true, row = 0, col = 0 },
    available = function()
      return true
    end,
  })
  local available, reason = unavailable.available()
  eq(false, available)
  truthy(reason:find('allow%-passthrough'))

  local forced = require('imageui.backend.kitty_pool').new({
    tmux = 'on',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_status = { detected = true, executable = true, enabled = false, value = 'off' },
    tmux_geometry = { valid = true, row = 0, col = 0 },
    available = function()
      return true
    end,
    send = function() end,
  })
  eq(true, forced.available())
  eq(true, forced.stats().tmux_passthrough)
end)

test('tmux refresh caches option checks while updating pane geometry', function()
  local status_reads = 0
  local geometry_reads = 0
  local backend = require('imageui.backend.kitty_pool').new({
    tmux = 'auto',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_status = function()
      status_reads = status_reads + 1
      return { detected = true, executable = true, enabled = true, value = 'on' }
    end,
    tmux_geometry = function()
      geometry_reads = geometry_reads + 1
      return { valid = true, row = geometry_reads, col = 0 }
    end,
    available = function()
      return true
    end,
    send = function() end,
  })
  eq(1, status_reads)
  eq(1, geometry_reads)
  eq(true, backend.refresh_transport())
  eq(1, status_reads)
  eq(2, geometry_reads)
  eq(true, backend.refresh_transport(true))
  eq(2, status_reads)
  eq(3, geometry_reads)
end)

test('tmux passthrough detection falls back to the global option on older versions', function()
  local commands = {}
  local status = require('imageui.transport.tmux').status({
    env = '/tmp/tmux-1000/default,1,0',
    pane = '%3',
    executable = function()
      return true
    end,
    run = function(command)
      commands[#commands + 1] = vim.deepcopy(command)
      if command[3] == '-pAv' or command[3] == '-Av' then
        return { code = 1, stdout = '', stderr = 'invalid option scope' }
      end
      return { code = 0, stdout = 'on\n', stderr = '' }
    end,
  })
  eq(true, status.enabled)
  eq('global', status.scope)
  eq('-pAv', commands[1][3])
  eq('-Av', commands[2][3])
  eq('-gv', commands[3][3])
  eq('allow-passthrough', commands[3][4])
  eq('-sv', commands[4][3])
end)

test('pooled Kitty backend retains failed deletes for retry', function()
  local fail_soft = false
  local fail_hard = false
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 57,
    send = function(data)
      if fail_soft and data:find('d=i', 1, true) then
        error('forced placement delete failure')
      end
      if fail_hard and data:find('d=I', 1, true) then
        error('forced asset delete failure')
      end
    end,
    available = function()
      return true
    end,
  })
  local id = backend.set('png', { row = 1, col = 1 }, { key = 'retry' })
  fail_soft = true
  local ok = pcall(backend.delete, id)
  eq(false, ok)
  eq(1, backend.stats().active_placements)
  eq(2, backend.stats().live_protocol_ids)
  fail_soft = false
  eq(true, backend.delete(id))

  fail_hard = true
  local cleared, err = backend.clear()
  eq(false, cleared)
  truthy(err)
  eq(1, backend.stats().assets)
  eq(2, backend.stats().live_protocol_ids)
  fail_hard = false
  eq(true, backend.clear())
  eq(0, backend.stats().assets)
  eq(0, backend.stats().live_protocol_ids)
end)

test('pooled Kitty backend quarantines and recovers a failed partial upload', function()
  local calls = 0
  local fail = true
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 59,
    send = function()
      calls = calls + 1
      if fail and calls >= 2 then
        error('forced mid-upload and abort failure')
      end
    end,
    available = function()
      return true
    end,
  })
  local ok = pcall(backend.set, string.rep('x', 5000), { row = 1, col = 1 }, { key = 'partial' })
  eq(false, ok)
  local stats = backend.stats()
  eq(false, stats.healthy)
  eq(1, stats.quarantined_ids)
  ok = pcall(backend.set, 'later', { row = 1, col = 1 }, { key = 'later' })
  eq(false, ok)

  fail = false
  eq(true, backend.clear())
  stats = backend.stats()
  eq(true, stats.healthy)
  eq(0, stats.quarantined_ids)
  local id = backend.set('recovered', { row = 1, col = 1 }, { key = 'recovered' })
  truthy(id)
  backend.delete(id)
  backend.clear()
end)

test('pooled Kitty backend applies backpressure when placement rollback cannot release', function()
  local fail_placement = true
  local fail_release = true
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 61,
    send = function(data)
      if fail_placement and data:find('a=p', 1, true) then
        error('forced placement failure')
      end
      if fail_release and data:find('d=I', 1, true) then
        error('forced placement rollback failure')
      end
    end,
    available = function()
      return true
    end,
  })
  local ok = pcall(backend.set, 'png', { row = 1, col = 1 }, { key = 'rollback' })
  eq(false, ok)
  local stats = backend.stats()
  eq(false, stats.healthy)
  eq(1, stats.assets)
  eq(0, stats.active_placements)
  eq(1, stats.live_protocol_ids)

  ok = pcall(backend.set, 'more', { row = 1, col = 1 }, { key = 'blocked' })
  eq(false, ok)
  eq(1, backend.stats().assets)

  fail_placement = false
  fail_release = false
  eq(true, backend.clear())
  stats = backend.stats()
  eq(true, stats.healthy)
  eq(0, stats.assets)
  eq(0, stats.live_protocol_ids)
end)

test('pooled Kitty backend bounds decoded assets and protocol IDs', function()
  local function u32(value)
    return string.char(
      math.floor(value / 0x1000000) % 256,
      math.floor(value / 0x10000) % 256,
      math.floor(value / 0x100) % 256,
      value % 256
    )
  end
  local png = '\137PNG\r\n\26\n' .. u32(13) .. 'IHDR' .. u32(100) .. u32(100)
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 62,
    max_assets = 10,
    max_bytes = 50000,
    max_dormant_placements = 2,
    send = function() end,
    available = function()
      return true
    end,
  })
  for index = 1, 1000 do
    local id = backend.set(png, { row = 1, col = 1 }, { key = 'asset-' .. index })
    backend.delete(id)
  end
  local stats = backend.stats()
  eq(1, stats.assets)
  eq(40000, stats.resident_decoded_bytes)
  truthy(stats.live_protocol_ids <= 2, 'protocol ID state grew beyond the live working set')
  truthy(stats.peak_resident_decoded_bytes <= 80000)
  backend.clear()
  eq(0, backend.stats().live_protocol_ids)
end)

test('pooled Kitty backend rejects assets beyond the decoded memory budget', function()
  local function u32(value)
    return string.char(
      math.floor(value / 0x1000000) % 256,
      math.floor(value / 0x10000) % 256,
      math.floor(value / 0x100) % 256,
      value % 256
    )
  end
  local oversized = '\137PNG\r\n\26\n' .. u32(13) .. 'IHDR' .. u32(4096) .. u32(4096)
  local sends = 0
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 63,
    max_assets = 4,
    max_bytes = 1024,
    send = function()
      sends = sends + 1
    end,
    available = function()
      return true
    end,
  })
  local ok, id, err = pcall(backend.set, oversized, { row = 1, col = 1 }, { key = 'oversized' })
  eq(true, ok)
  eq(nil, id)
  truthy(tostring(err):find('budget is full', 1, true))
  eq(0, sends)
  local stats = backend.stats()
  eq(0, stats.assets)
  eq(0, stats.resident_decoded_bytes)
  eq(1, stats.capacity_rejections)
  eq(true, stats.healthy)
end)

test('pooled Kitty backend applies backpressure after failed eviction', function()
  local fail_eviction = true
  local backend = require('imageui.backend.kitty_pool').new({
    seed = 65,
    max_assets = 4,
    max_bytes = 64,
    send = function(data)
      if fail_eviction and data:find('d=I', 1, true) then
        error('forced eviction failure')
      end
    end,
    available = function()
      return true
    end,
  })
  for index = 1, 4 do
    local id = backend.set('x', { row = 1, col = 1 }, { key = 'evict-' .. index })
    backend.delete(id)
  end
  local fifth = backend.set('x', { row = 1, col = 1 }, { key = 'evict-5' })
  local stats = backend.stats()
  eq(nil, fifth)
  eq(false, stats.healthy)
  eq(4, stats.assets)
  local ok = pcall(backend.set, 'x', { row = 1, col = 1 }, { key = 'blocked' })
  eq(false, ok)
  eq(4, backend.stats().assets)

  fail_eviction = false
  eq(true, backend.clear())
  eq(true, backend.stats().healthy)
  eq(0, backend.stats().assets)
end)

test('right CodeLens placement resolves against colorcolumn per window', function()
  local right = require('imageui.integrations.codelens_right')
  local win = vim.api.nvim_get_current_win()
  local previous_colorcolumn = vim.wo[win].colorcolumn
  local split = vim.api.nvim_open_win(vim.api.nvim_get_current_buf(), false, { split = 'right' })
  vim.wo[win].colorcolumn = '25'
  vim.wo[split].colorcolumn = '30'
  local opts, metadata = right.resolve(win, { { text = 'lens!' } }, {
    anchor = 'colorcolumn',
    side = 'before',
    distance = 3,
  })
  eq(16, opts.virt_text_win_col)
  eq('colorcolumn', metadata.anchor)
  local split_opts = right.resolve(split, { { text = 'lens!' } }, {
    anchor = 'colorcolumn',
    side = 'before',
    distance = 3,
  })
  eq(21, split_opts.virt_text_win_col)

  opts, metadata = right.resolve(win, { { text = 'lens!' } }, {
    anchor = 'colorcolumn',
    side = 'after',
    distance = 3,
  })
  eq(28, opts.virt_text_win_col)
  eq('after', metadata.side)

  vim.wo[win].colorcolumn = ''
  opts, metadata = right.resolve(win, { { text = 'lens!' } }, {
    anchor = 'colorcolumn',
    side = 'after',
    distance = 3,
  })
  eq('eol_right_align', opts.virt_text_pos)
  eq('window', metadata.anchor)
  eq('colorcolumn_unset', metadata.fallback_reason)
  eq('   ', opts.virt_text[#opts.virt_text][1])
  vim.wo[win].colorcolumn = previous_colorcolumn
  vim.api.nvim_win_close(split, true)
end)

test('right CodeLens channel can remain visible beside an above image', function()
  local right = require('imageui.integrations.codelens_right')
  local previous_buf = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', 'function example() {}' })
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()
  local right_config = { always = true, anchor = 'window', side = 'before', distance = 4 }
  local states = {
    [buf] = {
      entries = {
        [1] = {
          row = 1,
          mode = 'above_blank',
          spans = { { text = '3 references', highlight = 'LspCodeLens' } },
        },
      },
      fallback_modes = {},
    },
  }
  right.enable({
    states = function()
      return states
    end,
    config = function()
      return right_config
    end,
  })
  local ok, err = xpcall(function()
    vim.api.nvim__redraw({ buf = buf, valid = false, flush = true })
    truthy(states[buf].right_windows[win][1], 'always=true did not render the right channel')

    right_config.always = false
    vim.api.nvim__redraw({ buf = buf, valid = false, flush = true })
    eq(nil, states[buf].right_windows[win][1])
    states[buf].entries[1].mode = 'right'
    vim.api.nvim__redraw({ buf = buf, valid = false, flush = true })
    truthy(states[buf].right_windows[win][1], 'right placement did not render the right channel')
  end, debug.traceback)
  right.disable()
  vim.api.nvim_set_current_buf(previous_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  if not ok then
    error(err)
  end
end)

test('SVG renderer escapes text and produces stable cell metrics', function()
  local svg = require('imageui.renderer.svg')
  local source, metrics = svg.text({
    kind = 'text',
    spans = { { text = '<A&B>' } },
    style = {
      fg = '#ffffff',
      font_family = 'Mono & Sans',
      cell_width = 10,
      cell_height = 20,
    },
    font_scale = 0.5,
    render_scale = 2,
    padding = { left = 0, right = 0 },
  })
  truthy(source:find('&lt;A&amp;B&gt;', 1, true))
  truthy(source:find('Mono &amp; Sans', 1, true))
  eq(3, metrics.width_cells)
  eq(1, metrics.height_cells)
  eq(60, metrics.pixel_width)
  eq(40, metrics.pixel_height)
  truthy(source:find('xml:space="preserve"', 1, true))
end)

test('scene layout keeps pixel geometry separate from cell hit geometry', function()
  local scene = require('imageui.scene')
  local layout = require('imageui.scene.layout')
  local interaction = require('imageui.interaction_geometry')
  local root = scene.row({
    gap = 0.25,
    children = {
      scene.text({ id = 'small', text = 'A', font_scale = 0.5, focusable = true }),
      scene.spacer({ width = 0.25, height = 1 }),
      scene.text({ id = 'wide', text = '界', focusable = true }),
    },
  })
  root = scene.normalize(root)
  local compiled = layout.compile(root, {
    tabstop = 8,
    resolve_border = function()
      return nil
    end,
  })
  eq(4, compiled.width_cells)
  eq(1, compiled.height_cells)
  eq({ top = 0, left = 0, bottom = 0, right = 0 }, interaction.hit_rect(compiled.regions[1]))
  eq({ top = 0, left = 1, bottom = 0, right = 3 }, interaction.hit_rect(compiled.regions[2]))
  eq(
    nil,
    interaction.hit_rect({ visual = { x = 0, y = 0, width = 0, height = 1 } }),
    'zero-area visuals must not capture a Neovim cell'
  )
  eq(
    nil,
    interaction.project({ visual = { x = 0, y = 0, width = 0, height = 1 } }, {
      crop = { top = 0, left = 0, width = 1, height = 1 },
      rect = { top = 1, left = 1, bottom = 1, right = 1 },
    })
  )

  local projected = interaction.project(compiled.regions[2], {
    crop = { top = 0, left = 2, width = 1, height = 1 },
    rect = { top = 6, left = 20, bottom = 6, right = 20 },
  })
  eq({ top = 6, left = 20, bottom = 6, right = 20 }, projected)
  local ok = pcall(interaction.hit_rect, {
    visual = { x = 0, y = 0, width = 1, height = 1 },
    hit_rect = { row = 0.5, col = 0, rows = 1, cols = 1 },
  })
  eq(false, ok, 'explicit interaction bounds must use Neovim cells')
end)

test('scene collision validation is spatial, cached, and bounded', function()
  local interaction = require('imageui.interaction_geometry')
  interaction.clear_cache()
  local regions = {}
  local interactive = {}
  for index = 1, 2000 do
    local id = 'overlap-' .. index
    regions[index] = {
      id = id,
      visual = { x = 0, y = 0, width = 1, height = 1 },
    }
    interactive[id] = true
  end
  local collisions = interaction.collisions(regions, interactive)
  eq(64, #collisions, 'collision diagnostics exceeded their safety cap')
  eq(true, collisions.truncated)
  eq(64, collisions.limit)
  eq(collisions, interaction.collisions(regions, interactive))
  local stats = interaction.stats()
  eq(1, stats.calculations, 'the same manifest was validated more than once')
  eq(1, stats.cache_hits)
end)

test('scene renderer shares pixels while preserving semantic manifests', function()
  local config = require('imageui.config').normalize({
    render = { cache = { directory = test_path('scene-renderer') } },
  })
  local renderer = require('imageui.renderer')
  renderer.setup(config)
  if not renderer.rasterizer.executable() then
    print('# scene renderer test skipped: no supported executable')
    return
  end
  local function render(id)
    local asset
    local render_error
    renderer.render(
      {
        kind = 'scene',
        root = require('imageui.scene').text({
          id = id,
          text = 'native',
          highlight = 'Comment',
          font_scale = 0.75,
          focusable = true,
        }),
      },
      vim.api.nvim_get_current_win(),
      function(result, err)
        asset = result
        render_error = err
      end
    )
    truthy(vim.wait(10000, function()
      return asset ~= nil or render_error ~= nil
    end, 10))
    eq(nil, render_error)
    return asset
  end
  local first = render('first')
  local second = render('second')
  eq(first.key, second.key, 'node identity must not prevent visual asset sharing')
  eq('first', first.manifest.regions[1].id)
  eq('second', second.manifest.regions[1].id)
  local before_bytes = renderer.rasterizer.stats()
  renderer.rasterizer.bytes(first)
  renderer.rasterizer.bytes(second)
  local after_bytes = renderer.rasterizer.stats()
  eq(
    1,
    after_bytes.byte_reads - before_bytes.byte_reads,
    'semantic wrappers reread the same cached PNG'
  )
  eq(1, after_bytes.byte_cache_hits - before_bytes.byte_cache_hits)
end)

test('theme resolution follows namespace and winhighlight precedence', function()
  local theme = require('imageui.theme')
  local config = require('imageui.config').normalize()
  local win = vim.api.nvim_get_current_win()
  local previous_winhighlight = vim.wo[win].winhighlight
  local previous_namespace = vim.api.nvim_get_hl_ns({ winid = win })
  local previous_target = vim.api.nvim_get_hl(0, { name = 'ImageUIThemeTarget', link = false })
  local previous_mapped = vim.api.nvim_get_hl(0, { name = 'ImageUIThemeMapped', link = false })
  local namespace = vim.api.nvim_create_namespace('imageui.nvim:test-theme-precedence')
  local ok, err = xpcall(function()
    vim.api.nvim_win_set_hl_ns(win, -1)
    vim.api.nvim_set_hl(0, 'ImageUIThemeTarget', { fg = '#112233' })
    vim.api.nvim_set_hl(0, 'ImageUIThemeMapped', { fg = '#445566' })
    vim.wo[win].winhighlight = 'IMAGEUITHEMETARGET:ImageUIThemeMapped'
    eq('#445566', theme.resolve(win, 'ImageUIThemeTarget', config).fg)

    vim.api.nvim_set_hl(namespace, 'UnrelatedImageUIGroup', { fg = '#ffffff' })
    vim.api.nvim_win_set_hl_ns(win, namespace)
    eq(
      '#112233',
      theme.resolve(win, 'ImageUIThemeTarget', config).fg,
      'a window namespace must disable winhighlight and fall back globally by the same name'
    )

    vim.api.nvim_win_set_hl_ns(win, -1)
    vim.wo[win].winhighlight = 'ImageUIThemeTarget:'
    local normal = theme.resolve(win, 'Normal', config)
    eq(normal.fg, theme.resolve(win, 'ImageUIThemeTarget', config).fg)
  end, debug.traceback)
  vim.api.nvim_win_set_hl_ns(win, previous_namespace)
  vim.wo[win].winhighlight = previous_winhighlight
  vim.api.nvim_set_hl(0, 'ImageUIThemeTarget', previous_target)
  vim.api.nvim_set_hl(0, 'ImageUIThemeMapped', previous_mapped)
  if not ok then
    error(err)
  end
end)

test(
  'scene borders inherit native float chars, highlights, and asymmetric shadow insets',
  function()
    local theme = require('imageui.theme')
    local config = require('imageui.config').normalize()
    local previous_edge = vim.api.nvim_get_hl(0, { name = 'ImageUIBorderEdge', link = false })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_hl(0, 'ImageUIBorderEdge', { fg = '#224466' })
    local win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      row = 2,
      col = 3,
      width = 20,
      height = 4,
      border = {
        { '+', 'ImageUIBorderEdge' },
        { '-', 'ImageUIBorderEdge' },
        { '+', 'ImageUIBorderEdge' },
        { '|', 'ImageUIBorderEdge' },
      },
    })
    local ok, err = xpcall(function()
      local inherited = theme.resolve_border(win, { style = 'editor' }, config)
      eq('+', inherited.chars.top_left)
      eq('-', inherited.chars.horizontal)
      eq('|', inherited.chars.right)
      eq('ImageUIBorderEdge', inherited.highlights.horizontal)
      eq({ top = 1, right = 1, bottom = 1, left = 1 }, inherited.insets)

      local repeated = theme.resolve_border(win, { 'x' }, config)
      eq('x', repeated.chars.top_left)
      eq('x', repeated.chars.bottom)

      local shadow = theme.resolve_border(win, 'shadow', config)
      eq({ top = 0, right = 1, bottom = 1, left = 0 }, shadow.insets)
      eq('FloatShadow', shadow.highlights.right)
      eq('FloatShadowThrough', shadow.highlights.bottom_left)

      local first = theme.border_fingerprint(win, { { style = 'editor' } }, config)
      vim.api.nvim_set_hl(0, 'ImageUIBorderEdge', { fg = '#6688aa' })
      local second = theme.border_fingerprint(win, { { style = 'editor' } }, config)
      truthy(first ~= second, 'a native border highlight change must invalidate its scene asset')
    end, debug.traceback)
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.api.nvim_set_hl(0, 'ImageUIBorderEdge', previous_edge)
    if not ok then
      error(err)
    end
  end
)

test(
  'scene semantic appearances choose their native base independently of the anchor window',
  function()
    local theme = require('imageui.theme')
    local config = require('imageui.config').normalize()
    local win = vim.api.nvim_get_current_win()
    local previous_float = vim.api.nvim_get_hl(0, { name = 'NormalFloat', link = false })
    local previous_child = vim.api.nvim_get_hl(0, { name = 'ImageUISemanticChild', link = false })
    vim.api.nvim_set_hl(0, 'NormalFloat', { fg = '#ccddee', bg = '#123456' })
    vim.api.nvim_set_hl(0, 'ImageUISemanticChild', { fg = '#abcdef' })
    local style = theme.resolve(win, 'ImageUISemanticChild', config, 'NormalFloat')
    eq('#abcdef', style.fg)
    eq('#123456', style.bg)
    vim.api.nvim_set_hl(0, 'NormalFloat', previous_float)
    vim.api.nvim_set_hl(0, 'ImageUISemanticChild', previous_child)
  end
)

test('surfaces provide split-aware regions, focus, and native click passthrough', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('surfaces') } },
    integrations = { codelens = { enabled = false } },
  })
  if not require('imageui.renderer').rasterizer.executable() then
    print('# surface test skipped: no supported executable')
    imageui.disable()
    return
  end
  local events = { pass = 0, click = 0, enter = 0, hover = 0, leave = 0, activate = 0 }
  local scene = imageui.scene
  local surface = imageui.surface({
    anchor = { kind = 'screen', row = 2, col = 3 },
    scene = scene.row({
      children = {
        scene.text({
          id = 'pass',
          text = 'A',
          focusable = true,
          states = { focused = { highlight = 'Visual', background = true } },
        }),
        scene.spacer({ width = 1, height = 1 }),
        scene.text({
          id = 'apply',
          text = 'B',
          focusable = true,
          states = { focused = { highlight = 'PmenuSel', background = true } },
        }),
      },
    }),
    focus = { order = { 'pass', 'apply' }, initial = 'pass' },
    actions = {
      pass = {
        click = function()
          events.pass = events.pass + 1
        end,
        consume = false,
      },
      apply = {
        click = function()
          events.click = events.click + 1
        end,
        enter = function()
          events.enter = events.enter + 1
        end,
        hover = function()
          events.hover = events.hover + 1
        end,
        leave = function()
          events.leave = events.leave + 1
        end,
        activate = function()
          events.activate = events.activate + 1
        end,
      },
    },
  })
  truthy(
    vim.wait(10000, function()
      imageui.flush()
      return vim.tbl_count(fake._state()) == 1
    end, 10),
    'surface did not render'
  )

  eq('inline', require('imageui.manager').get(surface.widget_id).spec.content.root.role)
  eq(true, surface:update({ appearance = 'float' }))
  eq('float', require('imageui.manager').get(surface.widget_id).spec.content.root.role)
  eq(true, surface:update({ appearance = 'inline' }))
  truthy(vim.wait(10000, function()
    imageui.flush()
    return vim.tbl_count(fake._state()) == 1
  end, 10))

  eq('pass', imageui.hit_target(2, 3).node_id)
  eq(nil, imageui.hit_target(2, 4), 'transparent scene gaps must pass through')
  eq('apply', imageui.hit_target(2, 5).node_id)
  eq(false, imageui.dispatch('click', { screenrow = 2, screencol = 3 }))
  eq(1, events.pass)
  eq(true, imageui.dispatch('click', { screenrow = 2, screencol = 5 }))
  eq(1, events.click)

  local manager = require('imageui.manager')
  manager.dispatch_hover({ screenrow = 2, screencol = 5 })
  manager.dispatch_hover({ screenrow = 2, screencol = 5 })
  manager.dispatch_hover({ screenrow = 2, screencol = 4 })
  eq(1, events.enter)
  eq(2, events.hover)
  eq(1, events.leave)

  eq('pass', surface:focused())
  eq(true, surface:focus_next())
  eq('apply', surface:focused())
  eq(true, surface:activate())
  eq(1, events.activate)
  eq(true, surface:close())
  eq(false, surface:is_open())
  eq(nil, imageui.inspect().surfaces[surface.id])
  imageui.disable()
end)

test('surface updates reindex actions, z-order, focus, and node callback geometry', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('surface-updates') } },
    integrations = { codelens = { enabled = false } },
  })
  if not require('imageui.renderer').rasterizer.executable() then
    print('# surface update test skipped: no supported executable')
    imageui.disable()
    return
  end
  local scene = imageui.scene
  local focus_events = {}
  local removed_focus_events = {}
  local callback_rect
  local bottom = imageui.surface({
    anchor = { kind = 'screen', row = 2, col = 3 },
    zindex = 100,
    scene = scene.row({
      children = {
        scene.text({ id = 'first', text = 'A', focusable = true }),
        scene.spacer({ width = 2, height = 1 }),
        scene.text({ id = 'second', text = 'B', focusable = true }),
      },
    }),
    focus = { order = { 'first', 'second' }, initial = 'first' },
    actions = {
      first = {
        blur = function()
          focus_events[#focus_events + 1] = 'blur:first'
        end,
      },
      second = {
        focus = function()
          focus_events[#focus_events + 1] = 'focus:second'
        end,
        blur = function()
          removed_focus_events[#removed_focus_events + 1] = 'blur:second'
        end,
        activate = function(context)
          callback_rect = context.rect
        end,
      },
    },
  })
  local top = imageui.surface({
    anchor = { kind = 'screen', row = 2, col = 3 },
    zindex = 50,
    scene = scene.text({ id = 'top', text = 'A' }),
    actions = { top = { click = function() end } },
  })
  truthy(vim.wait(10000, function()
    imageui.flush()
    return vim.tbl_count(fake._state()) == 2
  end, 10))
  eq('first', imageui.hit_target(2, 3).node_id)
  truthy(top:update({ zindex = 200 }))
  imageui.flush()
  eq('top', imageui.hit_target(2, 3).node_id, 'zindex changes must reindex interaction targets')

  truthy(top:update({ actions = {} }))
  imageui.flush()
  eq('first', imageui.hit_target(2, 3).node_id, 'removing an action must remove its target')
  truthy(top:update({ actions = { top = { click = function() end } } }))
  imageui.flush()
  eq('top', imageui.hit_target(2, 3).node_id, 'adding an action must create its target')

  truthy(bottom:update({ focus = { order = { 'first', 'second' }, initial = 'second' } }))
  eq('second', bottom:focused())
  eq({ 'blur:first', 'focus:second' }, focus_events)
  truthy(bottom:activate())
  eq({ top = 2, left = 6, bottom = 2, right = 6 }, callback_rect)

  focus_events = {}
  truthy(bottom:update({
    focus = { order = { 'first', 'second' }, initial = 'first' },
    actions = {
      first = {
        focus = function()
          focus_events[#focus_events + 1] = 'focus:first:new'
        end,
      },
      second = {
        blur = function()
          focus_events[#focus_events + 1] = 'blur:second:old'
        end,
      },
    },
  }))
  eq({ 'focus:first:new' }, focus_events)
  eq({ 'blur:second' }, removed_focus_events)

  truthy(bottom:update({
    scene = scene.text({ id = 'replacement', text = 'A', focusable = true }),
    focus = { order = { 'replacement' } },
    actions = {
      replacement = {
        focus = function()
          focus_events[#focus_events + 1] = 'focus:replacement'
        end,
      },
    },
  }))
  eq(nil, bottom:focused())
  eq({ 'blur:second' }, removed_focus_events)
  top:close()
  bottom:close()
  imageui.disable()
end)

test('surface lifecycle validates hit geometry and tolerates reentrant callbacks', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('surface-lifecycle') } },
    integrations = { codelens = { enabled = false } },
  })
  local invalid = pcall(imageui.surface, {
    anchor = { kind = 'screen', row = 2, col = 3 },
    scene = imageui.scene.text({
      id = 'invalid',
      text = 'x',
      hit_rect = { row = 0.5, col = 0, rows = 1, cols = 1 },
    }),
    actions = { invalid = { click = function() end } },
  })
  eq(false, invalid, 'invalid hit geometry must fail before an image is placed')
  eq(0, vim.tbl_count(fake._state()))
  if not require('imageui.renderer').rasterizer.executable() then
    print('# surface lifecycle test skipped: no supported executable')
    imageui.disable()
    return
  end

  local leaves = 0
  local deletes = 0
  local surface
  surface = imageui.surface({
    anchor = { kind = 'screen', row = 2, col = 3 },
    scene = imageui.scene.text({ id = 'target', text = 'x' }),
    actions = {
      target = {
        hover = function() end,
        leave = function()
          leaves = leaves + 1
          surface:close()
        end,
      },
    },
    on_delete = function()
      deletes = deletes + 1
    end,
  })
  truthy(vim.wait(10000, function()
    imageui.flush()
    return imageui.hit_target(2, 3) ~= nil
  end, 10))
  local manager = require('imageui.manager')
  manager.dispatch_hover({ screenrow = 2, screencol = 3 })
  manager.dispatch_hover({ screenrow = 2, screencol = 4 })
  eq(1, leaves)
  eq(1, deletes)
  eq(false, surface:is_open())

  local hides = 0
  local nested_deletes = 0
  local nested
  nested = imageui.surface({
    anchor = { kind = 'screen', row = 3, col = 3 },
    scene = imageui.scene.text({ id = 'nested', text = 'x' }),
    on_hide = function()
      hides = hides + 1
      nested:close()
    end,
    on_delete = function()
      nested_deletes = nested_deletes + 1
    end,
  })
  truthy(vim.wait(10000, function()
    imageui.flush()
    return vim.tbl_count(fake._state()) == 1
  end, 10))
  eq(true, nested:close())
  eq(1, hides)
  eq(1, nested_deletes)
  imageui.disable()
end)

test('window-hosted surface updates move their derived anchor and lifetime', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('surface-host-update') } },
    integrations = { codelens = { enabled = false } },
  })
  local first_buf = vim.api.nvim_create_buf(false, true)
  local second_buf = vim.api.nvim_create_buf(false, true)
  local first = vim.api.nvim_open_win(first_buf, false, {
    relative = 'editor',
    row = 2,
    col = 2,
    width = 5,
    height = 1,
  })
  local second = vim.api.nvim_open_win(second_buf, false, {
    relative = 'editor',
    row = 5,
    col = 10,
    width = 5,
    height = 1,
  })
  local surface = imageui.surface({
    host = { kind = 'window', win = first },
    scene = imageui.scene.text({ id = 'target', text = 'x' }),
  })
  truthy(surface:update({ host = { kind = 'window', win = second } }))
  eq(second, require('imageui.manager').get(surface.widget_id).anchor.window)
  vim.api.nvim_win_close(first, true)
  eq(true, surface:is_open(), 'closing the previous host must not release a migrated surface')
  vim.api.nvim_win_close(second, true)
  eq(false, surface:is_open())
  vim.api.nvim_buf_delete(first_buf, { force = true })
  vim.api.nvim_buf_delete(second_buf, { force = true })
  imageui.disable()
end)

test('surface regions resolve independently in same-buffer splits', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('surface-splits') } },
    integrations = { codelens = { enabled = false } },
  })
  if not require('imageui.renderer').rasterizer.executable() then
    print('# surface split test skipped: no supported executable')
    imageui.disable()
    return
  end
  local previous = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'target' })
  vim.api.nvim_set_current_buf(buf)
  local left = vim.api.nvim_get_current_win()
  local right = vim.api.nvim_open_win(buf, false, { split = 'right' })
  vim.cmd('redraw')
  local surface = imageui.surface({
    anchor = { kind = 'buffer', buffer = buf, row = 0, col = 0 },
    scene = imageui.scene.text({ id = 'target', text = 'x' }),
    actions = { target = { click = function() end } },
  })
  truthy(
    vim.wait(10000, function()
      imageui.flush()
      return vim.tbl_count(fake._state()) == 2
    end, 10),
    'surface did not settle in both splits'
  )
  for _, win in ipairs({ left, right }) do
    local pos = vim.fn.screenpos(win, 1, 1)
    local target = imageui.hit_target(pos.row, pos.col)
    eq('target', target.node_id)
    eq(win, target.win)
  end
  surface:close()
  vim.api.nvim_win_close(right, true)
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(buf, { force = true })
  imageui.disable()
end)

test('window-hosted surfaces use native content origins without owning the window', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('surface-host') } },
    integrations = { codelens = { enabled = false } },
  })
  if not require('imageui.renderer').rasterizer.executable() then
    print('# surface host test skipped: no supported executable')
    imageui.disable()
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 3,
    col = 5,
    width = 12,
    height = 2,
    border = 'single',
  })
  local surface = imageui.surface({
    host = { kind = 'window', win = win },
    scene = imageui.scene.text({ id = 'hosted', text = 'native host' }),
    actions = { hosted = { click = function() end } },
  })
  truthy(vim.wait(10000, function()
    imageui.flush()
    return vim.tbl_count(fake._state()) == 1
  end, 10))
  local content = require('imageui.util.window').content_rect(win)
  local target = imageui.hit_target(content.top, content.left)
  eq('hosted', target.node_id)
  eq(win, target.win)
  eq(true, surface:close())
  eq(true, vim.api.nvim_win_is_valid(win), 'closing a surface must not close its native host')

  local follows_host = imageui.surface({
    host = { kind = 'window', window = win },
    scene = imageui.scene.text({ id = 'lifecycle', text = 'x' }),
  })
  vim.api.nvim_win_close(win, true)
  eq(false, follows_host:is_open(), 'a surface must release when its host closes')
  vim.api.nvim_buf_delete(buf, { force = true })
  imageui.disable()
end)

test('hidden native hosts suppress surfaces and restore their native z-order when shown', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('hidden-surface-host') } },
    integrations = { codelens = { enabled = false } },
  })
  if not require('imageui.renderer').rasterizer.executable() then
    print('# hidden surface host test skipped: no supported executable')
    imageui.disable()
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 3,
    col = 4,
    width = 20,
    height = 4,
    border = 'single',
    hide = true,
    zindex = 87,
  })
  local surface = imageui.surface({
    host = { kind = 'window', win = win },
    scene = imageui.scene.text({
      id = 'diagnostic',
      text = 'native diagnostic',
      role = 'diagnostic_error',
    }),
  })
  imageui.flush()
  eq(nil, require('imageui.util.window').content_rect(win))
  eq(
    {},
    require('imageui.anchor').windows(require('imageui.manager').get(surface.widget_id).anchor)
  )
  eq(0, imageui.inspect().widgets[surface.widget_id].views)
  eq(0, vim.tbl_count(fake._state()))

  vim.api.nvim_win_set_config(win, { hide = false })
  imageui.refresh()
  imageui.flush()
  truthy(vim.wait(10000, function()
    imageui.flush()
    return imageui.inspect().widgets[surface.widget_id].views == 1
  end, 10))
  local widget = require('imageui.manager').get(surface.widget_id)
  eq('DiagnosticFloatingError', widget.spec.content.root.highlight)
  eq(87, imageui.inspect().widgets[surface.widget_id].placements[1].opts.zindex)

  vim.api.nvim_win_set_config(win, { hide = true })
  imageui.refresh()
  imageui.flush()
  truthy(vim.wait(1000, function()
    return imageui.inspect().widgets[surface.widget_id].views == 0
  end, 10))
  eq(0, vim.tbl_count(fake._state()))
  surface:close()
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
  imageui.disable()
end)

test('text style fingerprints follow rendered highlight properties', function()
  local config = require('imageui.config').normalize()
  local renderer = require('imageui.renderer')
  renderer.setup(config)
  local content = {
    kind = 'text',
    highlight = 'ImageUIFingerprintTest',
    spans = { { text = 'styled', highlight = 'ImageUIFingerprintTest' } },
  }
  vim.api.nvim_set_hl(0, 'ImageUIFingerprintTest', { fg = '#112233' })
  local first = renderer.style_key(content, vim.api.nvim_get_current_win())
  vim.api.nvim_set_hl(0, 'ImageUIFingerprintTest', { fg = '#445566' })
  local second = renderer.style_key(content, vim.api.nvim_get_current_win())
  truthy(first ~= second, 'highlight changes must invalidate text assets')

  local original = vim.api.nvim_get_current_win()
  local split = vim.api.nvim_open_win(vim.api.nvim_get_current_buf(), false, {
    split = 'right',
  })
  local previous_normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local previous_normal_nc = vim.api.nvim_get_hl(0, { name = 'NormalNC', link = false })
  vim.api.nvim_set_hl(0, 'Normal', { fg = '#abcdef', bg = '#111111' })
  vim.api.nvim_set_hl(0, 'NormalNC', { fg = '#abcdef', bg = '#222222' })
  local normal = { kind = 'text', spans = { { text = 'normal' } } }
  local active_key = renderer.style_key(normal, original)
  local inactive_key = renderer.style_key(normal, split)
  eq(active_key, inactive_key, 'unused NormalNC background must not invalidate transparent text')
  vim.api.nvim_set_hl(0, 'NormalNC', { fg = '#fedcba', bg = '#222222' })
  inactive_key = renderer.style_key(normal, split)
  truthy(active_key ~= inactive_key, 'rendered NormalNC foreground must invalidate text')
  vim.api.nvim_win_close(split, true)
  vim.api.nvim_set_hl(0, 'ImageUIFingerprintTest', {})
  vim.api.nvim_set_hl(0, 'Normal', previous_normal)
  vim.api.nvim_set_hl(0, 'NormalNC', previous_normal_nc)
end)

test('custom SVG source failures are returned to the caller', function()
  local renderer = require('imageui.renderer')
  renderer.setup(require('imageui.config').normalize({
    render = { cache = { directory = test_path('svg-error') } },
  }))
  local asset
  local render_error
  renderer.render(
    {
      kind = 'svg',
      width_cells = 2,
      height_cells = 1,
      source = function()
        error('intentional source error')
      end,
    },
    vim.api.nvim_get_current_win(),
    function(result, err)
      asset = result
      render_error = err
    end
  )
  eq(nil, asset)
  truthy(render_error and render_error:find('intentional source error', 1, true))
end)

test('buffer anchors move with edits', function()
  local anchor = require('imageui.anchor')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'first', 'target' })
  local item = anchor.create({ kind = 'buffer', buffer = buf, row = 1, col = 0 })
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'inserted' })
  local marks = vim.api.nvim_buf_get_extmarks(buf, anchor.namespace(), 0, -1, {})
  eq(1, #marks)
  eq(2, marks[1][2])
  anchor.delete(item)
  eq(0, #vim.api.nvim_buf_get_extmarks(buf, anchor.namespace(), 0, -1, {}))
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('configured rasterizer produces valid PNG bytes', function()
  local rasterizer = require('imageui.renderer.rasterizer')
  local config = require('imageui.config').normalize({
    render = { cache = { directory = test_path('raster') } },
  })
  rasterizer.setup(config)
  if not rasterizer.executable() then
    print('# rasterizer test skipped: no supported executable')
    return
  end
  local source, metrics = require('imageui.renderer.svg').text({
    kind = 'text',
    spans = { { text = '3 references' } },
    style = {
      fg = '#8aadf4',
      font_family = 'monospace',
      cell_width = 9,
      cell_height = 18,
    },
    font_scale = 0.52,
    render_scale = 2,
  })
  local asset
  local render_error
  rasterizer.render(source, metrics, function(result, err)
    asset = result
    render_error = err
  end)
  truthy(
    vim.wait(10000, function()
      return asset ~= nil or render_error ~= nil
    end, 10),
    'rasterizer timed out'
  )
  eq(nil, render_error)
  truthy(asset and vim.uv.fs_stat(asset.path))
  local bytes = rasterizer.bytes(asset)
  eq('\137PNG\r\n\26\n', bytes:sub(1, 8))
end)

test('rasterizer cache identity includes output dimensions', function()
  local rasterizer = require('imageui.renderer.rasterizer')
  local config = require('imageui.config').normalize({
    render = { cache = { directory = test_path('raster-dimensions') } },
  })
  rasterizer.setup(config)
  if not rasterizer.executable() then
    print('# dimension cache test skipped: no supported executable')
    return
  end
  local source = '<svg xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%"/></svg>'
  local function render(metrics)
    local asset
    local render_error
    rasterizer.render(source, metrics, function(result, err)
      asset = result
      render_error = err
    end)
    truthy(vim.wait(10000, function()
      return asset ~= nil or render_error ~= nil
    end, 10))
    eq(nil, render_error)
    return asset
  end
  local small = render({
    width_cells = 2,
    height_cells = 1,
    pixel_width = 40,
    pixel_height = 40,
    render_scale = 2,
  })
  local large = render({
    width_cells = 5,
    height_cells = 3,
    pixel_width = 100,
    pixel_height = 120,
    render_scale = 2,
  })
  eq(2, small.width_cells)
  eq(5, large.width_cells)
  eq(3, large.height_cells)
  truthy(small.key ~= large.key)
end)

test('bordered float geometry clips to its content and occludes its border', function()
  local anchor = require('imageui.anchor')
  local placement = require('imageui.placement')
  placement.setup(require('imageui.config').normalize({
    placement = { partial = 'clip', occlusion = 'allow' },
  }))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '1234567890',
    '1234567890',
    '1234567890',
  })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 2,
    col = 4,
    width = 10,
    height = 3,
    border = 'single',
  })
  local first = vim.fn.screenpos(win, 1, 1)
  local last = vim.fn.screenpos(win, 3, 10)
  eq(
    { top = first.row, left = first.col, bottom = last.row, right = last.col },
    placement.window_rect(win)
  )

  local info = vim.fn.getwininfo(win)[1]
  eq({
    top = info.winrow,
    left = info.wincol,
    bottom = info.winrow + 4,
    right = info.wincol + 11,
  }, placement.float_rect(win))

  local item = anchor.create({ kind = 'buffer', buffer = buf, window = win, row = 2, col = 9 })
  local resolved = placement.resolve({
    anchor = item,
    spec = { partial = 'clip', occlusion = 'allow' },
  }, {
    width_cells = 1,
    height_cells = 1,
  }, win)
  eq(1, #resolved)
  eq(last.row, resolved[1].opts.row)
  eq(last.col, resolved[1].opts.col)
  anchor.delete(item)
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('native float occlusion follows visibility and zindex ordering', function()
  local anchor = require('imageui.anchor')
  local placement = require('imageui.placement')
  placement.setup(require('imageui.config').normalize({
    placement = { partial = 'allow', occlusion = 'hide' },
  }))
  local buf = vim.api.nvim_create_buf(false, true)
  local owner = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 3,
    col = 4,
    width = 20,
    height = 5,
    zindex = 80,
  })
  local below = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 3,
    col = 4,
    width = 20,
    height = 5,
    zindex = 40,
  })
  local item = anchor.create({
    kind = 'window',
    window = owner,
    origin = 'content',
    row = 0,
    col = 0,
  })
  local widget = {
    anchor = item,
    spec = { partial = 'allow', occlusion = 'hide' },
  }
  local asset = { width_cells = 2, height_cells = 1 }
  eq(1, #placement.resolve(widget, asset, owner), 'a lower float must not occlude its owner')

  local above = vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = 3,
    col = 4,
    width = 20,
    height = 5,
    zindex = 90,
  })
  eq(0, #placement.resolve(widget, asset, owner), 'a higher float must occlude its owner')
  vim.api.nvim_win_set_config(above, { hide = true })
  eq(1, #placement.resolve(widget, asset, owner), 'a hidden float must not occlude its owner')

  anchor.delete(item)
  vim.api.nvim_win_close(above, true)
  vim.api.nvim_win_close(below, true)
  vim.api.nvim_win_close(owner, true)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('manager creates, updates, hits, and deletes owned images', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('manager') } },
    integrations = { codelens = { enabled = false } },
  })
  local clicked = false
  local id = imageui.create({
    tag = 'test',
    anchor = { kind = 'screen', row = 2, col = 3 },
    content = {
      kind = 'png',
      bytes = '\137PNG\r\n\26\nmock',
      width_cells = 4,
      height_cells = 1,
      pixel_width = 36,
      pixel_height = 18,
    },
    actions = {
      click = function()
        clicked = true
      end,
    },
  })
  imageui.flush()
  eq(1, vim.tbl_count(fake._state()))
  local state = fake._state()[1]
  eq({ row = 2, col = 3, width = 4, height = 1, zindex = 50 }, state.opts)
  eq(id, imageui.hit_test(2, 4).id)
  eq(true, imageui.dispatch('click', { screenrow = 2, screencol = 4 }))
  eq(true, clicked)

  local exported = imageui.export(test_path('export'))
  eq(1, #exported)
  eq('\137PNG\r\n\26\nmock', require('imageui.util.fs').read_binary(exported[1]))

  local invalid_update = pcall(imageui.update, id, { anchor = { kind = 'screen', row = 3 } })
  eq(false, invalid_update)
  eq(id, imageui.hit_test(2, 4).id)

  imageui.update(id, { offset_col = 2 })
  imageui.flush()
  eq(5, fake._state()[1].opts.col)
  eq(true, imageui.delete(id))
  eq(0, vim.tbl_count(fake._state()))
  imageui.disable()
end)

test('equivalent widget updates reuse rendered and terminal images', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('equivalent-update') } },
    integrations = { codelens = { enabled = false } },
  })
  local spec = {
    anchor = { kind = 'screen', row = 2, col = 3 },
    content = {
      kind = 'png',
      bytes = 'same-png',
      width_cells = 2,
      height_cells = 1,
    },
  }
  local id = imageui.create(spec)
  imageui.flush()
  eq(1, imageui.inspect().performance.backend.set)
  eq(#spec.content.bytes, imageui.inspect().performance.backend.bytes)

  imageui.update(id, vim.deepcopy(spec))
  imageui.flush()
  eq(1, vim.tbl_count(fake._state()))
  eq(1, imageui.inspect().performance.backend.set)
  eq(0, imageui.inspect().performance.backend.delete)
  eq(#spec.content.bytes, imageui.inspect().performance.backend.bytes)
  imageui.disable()
end)

test('transport reset hard-releases and rebuilds visible assets', function()
  package.loaded.imageui = nil
  local backend = require('imageui.backend.kitty_pool').new({
    send = function() end,
    available = function()
      return true
    end,
    seed = 700,
  })
  local imageui = require('imageui').setup({
    backend = backend,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('transport-reset') } },
    integrations = { codelens = { enabled = false } },
  })
  imageui.create({
    anchor = { kind = 'screen', row = 1, col = 1 },
    content = { kind = 'png', bytes = 'reset-png', width_cells = 1, height_cells = 1 },
  })
  imageui.flush()
  eq(1, backend.stats().transmissions)
  imageui.reset_transport()
  imageui.flush()
  local stats = backend.stats()
  eq(2, stats.transmissions)
  eq(1, stats.hard_deletes)
  eq(1, stats.active_placements)
  imageui.disable()
end)

test('tmux focus recovery replays placements without retransmitting assets', function()
  package.loaded.imageui = nil
  local backend = require('imageui.backend.kitty_pool').new({
    tmux = 'on',
    tmux_env = '/tmp/tmux-1000/default,1,0',
    tmux_geometry = { valid = true, row = 0, col = 0 },
    safe_reposition = 'off',
    send = function() end,
    available = function()
      return true
    end,
    seed = 710,
  })
  local imageui = require('imageui').setup({
    backend = backend,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('tmux-focus-replay') } },
    integrations = { codelens = { enabled = false } },
  })
  imageui.create({
    anchor = { kind = 'screen', row = 1, col = 1 },
    content = { kind = 'png', bytes = 'focus-png', width_cells = 1, height_cells = 1 },
  })
  imageui.flush()
  eq(1, backend.stats().transmissions)
  vim.api.nvim_exec_autocmds('FocusLost', {})
  vim.api.nvim_exec_autocmds('FocusGained', {})
  imageui.flush()
  local stats = backend.stats()
  eq(1, stats.transmissions)
  eq(1, stats.updates)
  eq(1, stats.active_placements)
  imageui.disable()
end)

test('manager retries failed placement deletion without losing the widget ID', function()
  package.loaded.imageui = nil
  local fail_delete = false
  local backend = require('imageui.backend.kitty_pool').new({
    send = function(data)
      if fail_delete and data:find('d=i', 1, true) then
        error('forced manager delete failure')
      end
    end,
    available = function()
      return true
    end,
    seed = 730,
  })
  local imageui = require('imageui').setup({
    backend = backend,
    placement = { debounce = 0, scroll_debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('manager-delete-retry') } },
    integrations = { codelens = { enabled = false } },
  })
  local previous = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for index = 1, 100 do
    lines[index] = 'line ' .. index
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()
  local id = imageui.create({
    anchor = { kind = 'buffer', buffer = buf, row = 1, col = 0 },
    content = { kind = 'png', bytes = 'retry-png', width_cells = 1, height_cells = 1 },
  })
  imageui.flush()
  fail_delete = true
  vim.api.nvim_win_set_cursor(win, { 80, 0 })
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zt')
  end)
  vim.cmd('redraw')
  imageui.refresh()
  imageui.flush()
  eq(1, backend.stats().active_placements)
  truthy(require('imageui.manager').get(id), 'failed offscreen delete lost the widget')
  fail_delete = false
  imageui.refresh()
  imageui.flush()
  eq(0, backend.stats().active_placements)

  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.api.nvim_win_call(win, function()
    vim.cmd('normal! zt')
  end)
  vim.cmd('redraw')
  imageui.refresh()
  imageui.flush()
  eq(1, backend.stats().active_placements)
  fail_delete = true
  eq(false, imageui.delete(id))
  truthy(require('imageui.manager').get(id), 'public delete lost an unreleased placement')
  fail_delete = false
  eq(true, imageui.delete(id))
  eq(nil, require('imageui.manager').get(id))
  imageui.disable()
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('manager sanitizes successful assets after a partial cleanup failure', function()
  package.loaded.imageui = nil
  local next_id = 0
  local state = {}
  local fail_delete = true
  local partial_clear = true
  local backend = {}

  function backend.available()
    return true
  end

  function backend.set(_, opts)
    next_id = next_id + 1
    state[next_id] = vim.deepcopy(opts)
    return next_id
  end

  function backend.update(id, opts)
    state[id] = vim.tbl_extend('force', state[id], vim.deepcopy(opts))
  end

  function backend.delete(id)
    if fail_delete then
      error('forced placement cleanup failure')
    end
    local found = state[id] ~= nil
    state[id] = nil
    return found
  end

  function backend.get(id)
    return state[id] and vim.deepcopy(state[id]) or nil
  end

  function backend.clear()
    if partial_clear then
      local id = next(state)
      state[id] = nil
      return false, 'forced partial asset cleanup'
    end
    for id in pairs(state) do
      state[id] = nil
    end
    return true
  end

  local imageui = require('imageui').setup({
    backend = backend,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('manager-partial-cleanup') } },
    integrations = { codelens = { enabled = false } },
  })
  for row = 1, 2 do
    imageui.create({
      anchor = { kind = 'screen', row = row, col = 1 },
      content = {
        kind = 'png',
        bytes = 'partial-' .. row,
        width_cells = 1,
        height_cells = 1,
      },
    })
  end
  imageui.flush()
  eq(2, vim.tbl_count(state))
  eq(false, imageui.disable())
  eq(1, vim.tbl_count(state))
  local views = 0
  for _, widget in pairs(imageui.inspect().widgets) do
    views = views + widget.views
  end
  eq(1, views)

  fail_delete = false
  partial_clear = false
  eq(true, imageui.disable())
  eq(0, vim.tbl_count(state))
  eq(0, vim.tbl_count(require('imageui.manager').all()))
end)

test('live benchmark distributes fixtures and reports deltas', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('benchmark') } },
    integrations = { codelens = { enabled = false } },
  })
  local previous = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for index = 1, 200 do
    lines[index] = 'local benchmark_' .. index .. ' = ' .. index
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  vim.cmd('redraw')
  local benchmark = require('imageui.benchmark')
  vim.g.imageui_benchmark_quiet = true
  local original_print = vim.print
  local original_notify = vim.notify
  vim.print = function() end
  vim.notify = function() end
  eq(50, benchmark.start(50))
  local report
  truthy(
    vim.wait(10000, function()
      imageui.flush()
      local state = imageui.inspect()
      return state.renderer.pending == 0 and state.jobs.running == 0 and state.jobs.queued == 0
    end, 10),
    'benchmark render work did not settle'
  )
  truthy(
    vim.wait(10000, function()
      report = benchmark.report()
      return report.ready
    end, 10),
    'benchmark baseline did not settle'
  )
  eq(50, report.widgets)
  truthy(report.active_views > 0)
  truthy(type(report.transport) == 'table')
  truthy(type(report.jobs) == 'table')
  truthy(type(report.scheduler) == 'table')
  benchmark.stop()
  vim.g.imageui_benchmark_quiet = nil
  vim.print = original_print
  vim.notify = original_notify
  eq(0, vim.tbl_count(require('imageui.manager').all()))
  imageui.disable()
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('pending display crops coalesce to the latest placement request', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('pending-view-coalesce') } },
    integrations = { codelens = { enabled = false } },
  })
  local crop = require('imageui.renderer.crop')
  local original_get = crop.get
  local callback
  local requests = 0
  crop.get = function(_, _, cb)
    requests = requests + 1
    callback = cb
  end
  local id = imageui.create({
    anchor = { kind = 'screen', row = 2, col = 2 },
    content = { kind = 'png', bytes = 'pending-png', width_cells = 2, height_cells = 1 },
  })
  imageui.flush()
  eq(1, requests)
  for index = 1, 5000 do
    imageui.update(id, { offset_col = index % 2 })
    imageui.flush()
  end
  eq(1, requests, 'reconciliation appended duplicate callbacks to one pending crop')
  callback({ key = 'pending-png', bytes = 'pending-png', width_cells = 2, height_cells = 1 })
  eq(1, vim.tbl_count(fake._state()))
  crop.get = original_get
  imageui.disable()
end)

test('viewport scroll events coalesce until the scroll debounce settles', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    placement = {
      debounce = 0,
      scroll_debounce = 1000,
      partial = 'allow',
      occlusion = 'allow',
    },
    render = { cache = { directory = test_path('scroll-debounce') } },
    integrations = { codelens = { enabled = false } },
  })
  imageui.create({
    anchor = { kind = 'screen', row = 1, col = 1 },
    content = { kind = 'png', bytes = 'png', width_cells = 1, height_cells = 1 },
  })
  imageui.flush()
  local before = imageui.inspect().performance.reconciles
  for _ = 1, 20 do
    vim.api.nvim_exec_autocmds('WinScrolled', {})
  end
  eq(before, imageui.inspect().performance.reconciles)
  imageui.flush()
  eq(before + 1, imageui.inspect().performance.reconciles)
  imageui.disable()
end)

test('setup is repeatable and tears down the previous manager', function()
  package.loaded.imageui = nil
  local imageui = require('imageui')
  local first = require('imageui.backend.fake').new()
  imageui.setup({
    backend = first,
    render = { cache = { directory = test_path('repeat-setup') } },
    integrations = { codelens = { enabled = false } },
  })
  imageui.create({
    anchor = { kind = 'screen', row = 1, col = 1 },
    content = { kind = 'png', bytes = 'png', width_cells = 1, height_cells = 1 },
  })
  imageui.flush()
  eq(1, vim.tbl_count(first._state()))

  local second = require('imageui.backend.fake').new()
  imageui.setup({
    backend = second,
    render = { cache = { directory = test_path('repeat-setup') } },
    integrations = { codelens = { enabled = false } },
  })
  eq(0, vim.tbl_count(first._state()))
  eq(true, imageui.is_enabled())
  imageui.disable()
end)

test('cursor anchors follow CursorMoved events', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('cursor') } },
    integrations = { codelens = { enabled = false } },
  })
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'first', 'second' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  imageui.create({
    anchor = { kind = 'cursor' },
    content = { kind = 'png', bytes = 'png', width_cells = 1, height_cells = 1 },
  })
  imageui.flush()
  local before = fake._state()[1].opts.row
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
  imageui.flush()
  eq(before + 1, fake._state()[1].opts.row)
  imageui.disable()
end)

test('buffer anchors skip cursor-only reconciliation', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('buffer-cursor-performance') } },
    integrations = { codelens = { enabled = false } },
  })
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'first', 'second' })
  imageui.create({
    anchor = { kind = 'buffer', buffer = buf, row = 0, col = 0 },
    content = { kind = 'png', bytes = 'png', width_cells = 1, height_cells = 1 },
  })
  imageui.flush()
  local before = imageui.inspect().performance.reconciles
  eq(0, imageui.inspect().performance.cursor_widgets)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
  imageui.flush()
  eq(before, imageui.inspect().performance.reconciles)
  imageui.disable()
end)

test('dynamic cursor anchors follow WinEnter across splits', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('cursor-winenter') } },
    integrations = { codelens = { enabled = false } },
  })
  imageui.create({
    anchor = { kind = 'cursor' },
    content = { kind = 'png', bytes = 'png', width_cells = 1, height_cells = 1 },
  })
  imageui.flush()
  local first_win = vim.api.nvim_get_current_win()
  vim.cmd('rightbelow vsplit')
  local second_win = vim.api.nvim_get_current_win()
  truthy(first_win ~= second_win)
  vim.api.nvim_exec_autocmds('WinEnter', {})
  imageui.flush()
  eq(1, vim.tbl_count(fake._state()))
  local expected = vim.fn.screenpos(second_win, 1, 1)
  local active_image
  for _, value in pairs(fake._state()) do
    active_image = value
  end
  truthy(active_image)
  eq(expected.col, active_image.opts.col)
  vim.api.nvim_win_close(second_win, true)
  imageui.disable()
end)

test('buffer widgets settle into every same-buffer split after layout', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('same-buffer-splits') } },
    integrations = { codelens = { enabled = false } },
  })
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'first', 'second', 'third' })
  local first = vim.api.nvim_get_current_win()
  local second = vim.api.nvim_open_win(buf, false, { split = 'right' })
  local id = imageui.create({
    anchor = { kind = 'buffer', buffer = buf, row = 1, col = 0 },
    content = { kind = 'png', bytes = 'split-png', width_cells = 2, height_cells = 1 },
  })
  imageui.flush()
  vim.api.nvim__redraw({ valid = false, flush = true })
  truthy(
    vim.wait(1000, function()
      return imageui.inspect().widgets[id].views == 2
    end, 10),
    'normal redraw did not settle the new split'
  )
  eq(2, imageui.inspect().widgets[id].views)
  local windows = {}
  for _, placement in ipairs(imageui.inspect().widgets[id].placements) do
    windows[placement.win] = true
  end
  eq(true, windows[first])
  eq(true, windows[second])
  vim.api.nvim_win_close(second, true)
  imageui.disable()
end)

test('closed folds expose only the fold-head widget', function()
  package.loaded.imageui = nil
  local fake = require('imageui.backend.fake').new()
  local imageui = require('imageui').setup({
    backend = fake,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('fold-visibility') } },
    integrations = { codelens = { enabled = false } },
  })
  local previous = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for index = 1, 1002 do
    lines[index] = 'line ' .. index
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  vim.wo.foldmethod = 'manual'
  vim.cmd('2,1001fold')
  for row = 1, 1000 do
    imageui.create({
      anchor = { kind = 'buffer', buffer = buf, row = row, col = 0 },
      content = {
        kind = 'png',
        bytes = 'fold-' .. row,
        width_cells = 1,
        height_cells = 1,
      },
    })
  end
  imageui.flush()
  eq(1, vim.tbl_count(fake._state()), 'hidden folded widgets were rendered')
  eq(1, imageui.inspect().performance.backend.set)
  imageui.disable()
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('cold scrolling cancels obsolete renders and bounds the queue', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    placement = { debounce = 0, scroll_debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = {
      max_jobs = 1,
      max_queue = 32,
      cache = { directory = test_path('cold-scroll-queue') },
    },
    integrations = { codelens = { enabled = false } },
  })
  local jobs = require('imageui.renderer.jobs')
  jobs.setup(imageui.config, function()
    return { kill = function() end }
  end)
  local previous = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for index = 1, 1200 do
    lines[index] = 'local value_' .. index .. ' = ' .. index
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  local win = vim.api.nvim_get_current_win()
  for row = 0, 1199 do
    imageui.create({
      anchor = { kind = 'buffer', buffer = buf, row = row, col = 0 },
      content = {
        kind = 'text',
        highlight = 'Comment',
        spans = { { text = 'cold ' .. row, highlight = 'Comment' } },
      },
    })
  end
  for top = 1, 1181, 20 do
    vim.api.nvim_win_set_cursor(win, { top, 0 })
    vim.api.nvim_win_call(win, function()
      vim.cmd('normal! zt')
    end)
    vim.cmd('redraw')
    imageui.refresh()
    imageui.flush()
    truthy(jobs.stats().queued <= 32, 'render queue exceeded its configured cap')
  end
  local renderer = require('imageui.renderer.rasterizer').stats()
  truthy(renderer.pending <= 64, 'obsolete cold renders remained pending')
  truthy(renderer.cancelled > 0, 'cold scrolling did not cancel obsolete renders')
  imageui.disable()
  jobs.setup(require('imageui.config').normalize())
  vim.api.nvim_set_current_buf(previous)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test('changing partial crops cancels obsolete crop jobs', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    placement = { debounce = 0, partial = 'clip', occlusion = 'allow' },
    render = {
      max_jobs = 1,
      max_queue = 16,
      cache = { directory = test_path('crop-cancellation') },
    },
    integrations = { codelens = { enabled = false } },
  })
  local jobs = require('imageui.renderer.jobs')
  jobs.setup(imageui.config, function()
    return { kill = function() end }
  end)
  local id = imageui.create({
    anchor = { kind = 'screen', row = 1, col = 1 },
    content = {
      kind = 'png',
      path = vim.fs.joinpath(vim.fn.getcwd(), 'examples', 'previews', 'imageui-preview.png'),
      width_cells = 20,
      height_cells = 20,
      pixel_width = 800,
      pixel_height = 800,
    },
  })
  imageui.flush()
  for offset = -1, -15, -1 do
    imageui.update(id, { offset_row = offset })
    imageui.flush()
    truthy(require('imageui.renderer.crop').stats().pending <= 1)
    truthy(jobs.stats().queued <= 1)
  end
  truthy(require('imageui.renderer.crop').stats().cancelled > 0)
  imageui.disable()
  jobs.setup(require('imageui.config').normalize())
end)

test('missing PNG data invokes the widget fallback', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('missing-png') } },
    integrations = { codelens = { enabled = false } },
  })
  local fallbacks = 0
  imageui.create({
    anchor = { kind = 'screen', row = 1, col = 1 },
    content = {
      kind = 'png',
      path = test_path('definitely-missing.png'),
      width_cells = 1,
      height_cells = 1,
    },
    fallback = function()
      fallbacks = fallbacks + 1
    end,
  })
  imageui.flush()
  imageui.flush()
  truthy(vim.wait(1000, function()
    return fallbacks == 1
  end, 10))
  imageui.disable()
end)

test('disabling interactions preserves a mapping installed afterward', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    render = { cache = { directory = test_path('interactions') } },
    interactions = { mouse = true },
    integrations = { codelens = { enabled = false } },
  })
  local external = function()
    return vim.keycode('<LeftMouse>')
  end
  vim.keymap.set('n', '<LeftMouse>', external, { expr = true, replace_keycodes = false })
  imageui.disable()
  local mapping = vim.fn.maparg('<LeftMouse>', 'n', false, true)
  eq(external, mapping.callback)
  vim.keymap.del('n', '<LeftMouse>')
end)

test('fallback is replaced by a recovered image and can be used again', function()
  package.loaded.imageui = nil
  local ready = false
  local images = {}
  local next_image = 0
  local backend = {
    available = function()
      return ready, ready and nil or 'temporarily unavailable'
    end,
    set = function(bytes, opts)
      next_image = next_image + 1
      images[next_image] = { bytes = bytes, opts = opts }
      return next_image
    end,
    update = function(id, opts)
      images[id].opts = opts
    end,
    delete = function(id)
      images[id] = nil
      return true
    end,
  }
  local imageui = require('imageui').setup({
    backend = backend,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('fallback') } },
    integrations = { codelens = { enabled = false } },
  })
  local fallbacks = 0
  local shows = 0
  imageui.create({
    anchor = { kind = 'screen', row = 1, col = 1 },
    content = { kind = 'png', bytes = 'png', width_cells = 1, height_cells = 1 },
    fallback = function()
      fallbacks = fallbacks + 1
    end,
    on_show = function()
      shows = shows + 1
    end,
  })
  imageui.flush()
  truthy(vim.wait(1000, function()
    return fallbacks == 1
  end, 10))

  ready = true
  imageui.refresh()
  imageui.flush()
  eq(1, shows)
  eq(1, vim.tbl_count(images))

  ready = false
  imageui.refresh()
  imageui.flush()
  truthy(vim.wait(1000, function()
    return fallbacks == 2
  end, 10))
  eq(0, vim.tbl_count(images))
  imageui.disable()
end)

test('CodeLens refresh handler is chained and restored', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    render = { cache = { directory = test_path('handler') } },
    integrations = { codelens = { enabled = false } },
  })
  local codelens = require('imageui.integrations.codelens')
  local original = vim.lsp.handlers['workspace/codeLens/refresh']
  local sentinel = function()
    return 'sentinel'
  end
  vim.lsp.handlers['workspace/codeLens/refresh'] = sentinel
  codelens.enable()
  truthy(vim.lsp.handlers['workspace/codeLens/refresh'] ~= sentinel)
  codelens.disable()
  eq(sentinel, vim.lsp.handlers['workspace/codeLens/refresh'])
  vim.lsp.handlers['workspace/codeLens/refresh'] = original
  imageui.disable()
end)

test('CodeLens public API and execution share the ImageUI lens state', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    render = { cache = { directory = test_path('codelens-api') } },
    integrations = {
      codelens = {
        enabled = false,
        debounce = 60000,
        placement_order = { 'above_blank', 'above_clear', 'overlay', 'native' },
        right = { always = true, anchor = 'colorcolumn', side = 'after', distance = 2 },
      },
    },
  })
  local codelens = require('imageui.integrations.codelens')
  local native = {}
  for _, name in ipairs({ 'enable', 'is_enabled', 'get', 'run', 'refresh' }) do
    native[name] = vim.lsp.codelens[name]
  end
  codelens.enable()
  truthy(vim.lsp.codelens.run ~= native.run)

  local previous_buf = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', 'function example() {}' })
  vim.api.nvim_set_current_buf(buf)
  local previous_list = vim.wo.list
  local previous_listchars = vim.wo.listchars
  vim.wo.list = true
  vim.wo.listchars = 'eol:↴'
  vim.cmd.redraw()
  vim.lsp.codelens.enable(true, { bufnr = buf })
  eq(true, vim.lsp.codelens.is_enabled({ bufnr = buf }))

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
  truthy(apply, 'could not locate private CodeLens reconciler')

  local executions = 0
  local get_client = vim.lsp.get_client_by_id
  vim.lsp.get_client_by_id = function(id)
    if id == 424242 then
      return {
        id = id,
        name = 'test-client',
        offset_encoding = 'utf-16',
        attached_buffers = { [buf] = true },
        exec_cmd = function(_, command, context)
          eq('test.references', command.command)
          eq(buf, context.bufnr)
          executions = executions + 1
        end,
      }
    end
    return get_client(id)
  end
  local results = {
    {
      client_id = 424242,
      lens = {
        range = { start = { line = 1, character = 0 } },
        command = { title = '3 references', command = 'test.references' },
      },
    },
  }
  apply(buf, results)
  eq(1, #vim.lsp.codelens.get({ bufnr = buf }))
  local initial_state = codelens.inspect().buffers[buf]
  eq('above_blank', initial_state.placements[1])
  eq('occupied', initial_state.attempts[1].above_blank.fit.reason)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.lsp.codelens.run({ bufnr = buf })
  eq(1, executions)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'x', '        function example() {}' })
  results[1].lens.range.start.character = 8
  vim.cmd.redraw()
  apply(buf, results)
  eq('above_clear', codelens.inspect().buffers[buf].placements[1])
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '        occupied' })
  vim.cmd.redraw()
  apply(buf, results)
  eq('overlay', codelens.inspect().buffers[buf].placements[1])

  vim.lsp.codelens.enable(false, { bufnr = buf, client_id = 424242 })
  eq(false, vim.lsp.codelens.is_enabled({ bufnr = buf, client_id = 424242 }))
  vim.lsp.codelens.enable(true, { bufnr = buf, client_id = 424242 })
  eq(true, vim.lsp.codelens.is_enabled({ bufnr = buf, client_id = 424242 }))
  vim.lsp.codelens.enable(false, { bufnr = buf })
  eq(false, vim.lsp.codelens.is_enabled({ bufnr = buf }))
  eq(0, #vim.lsp.codelens.get({ bufnr = buf }))
  vim.lsp.get_client_by_id = get_client

  local facade_run = vim.lsp.codelens.run
  local external_wrapper = function(opts)
    return facade_run(opts)
  end
  vim.lsp.codelens.run = external_wrapper
  codelens.disable()
  eq(external_wrapper, vim.lsp.codelens.run, 'an external CodeLens wrapper was overwritten')
  vim.lsp.codelens.run = native.run
  for name, callback in pairs(native) do
    eq(callback, vim.lsp.codelens[name], ('CodeLens %s was not restored'):format(name))
  end
  vim.wo.list = previous_list
  vim.wo.listchars = previous_listchars
  vim.api.nvim_set_current_buf(previous_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  imageui.disable()
end)

test('explicit CodeLens placement order controls image failure fallback', function()
  package.loaded.imageui = nil
  local backend = require('imageui.backend.fake').new()
  backend.set = function()
    return nil, 'forced image failure'
  end
  local imageui = require('imageui').setup({
    backend = backend,
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('codelens-ordered-fallback') } },
    integrations = {
      codelens = {
        enabled = false,
        debounce = 60000,
        placement_order = { 'above_blank', 'above_clear', 'native' },
      },
    },
  })
  local codelens = require('imageui.integrations.codelens')
  codelens.enable()
  local previous_buf = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '', 'function example() {}' })
  vim.api.nvim_set_current_buf(buf)
  vim.cmd.redraw()

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
  truthy(apply, 'could not locate private CodeLens reconciler')
  apply(buf, {
    {
      client_id = 999999,
      lens = {
        range = { start = { line = 1, character = 0 } },
        command = { title = '3 references', command = 'test.references' },
      },
    },
  })
  eq('above_blank', codelens.inspect().buffers[buf].placements[1])
  imageui.flush()
  truthy(
    vim.wait(10000, function()
      local state = codelens.inspect().buffers[buf]
      return state and state.fallback_modes[1] ~= nil
    end, 10),
    'ordered fallback was not rendered'
  )
  local state = codelens.inspect().buffers[buf]
  eq('native', state.fallback_modes[1])
  truthy(state.errors[1]:find('forced image failure', 1, true))

  codelens.disable()
  vim.api.nvim_set_current_buf(previous_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  imageui.disable()
end)

test('native CodeLens fallback does not permanently block an above placement', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    placement = { debounce = 0, partial = 'allow', occlusion = 'allow' },
    render = { cache = { directory = test_path('codelens-self-collision') } },
    integrations = {
      codelens = {
        enabled = false,
        debounce = 60000,
        placement_order = { 'above_blank', 'above_clear', 'native' },
      },
    },
  })
  local codelens = require('imageui.integrations.codelens')
  codelens.enable()
  local previous_buf = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'occupied', 'function example() {}' })
  vim.api.nvim_set_current_buf(buf)
  vim.cmd.redraw()

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
  truthy(apply, 'could not locate private CodeLens reconciler')
  local results = {
    {
      client_id = 999999,
      lens = {
        range = { start = { line = 1, character = 0 } },
        command = { title = '3 references', command = 'test.references' },
      },
    },
  }
  apply(buf, results)
  eq('native', codelens.inspect().buffers[buf].placements[1])
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '' })
  vim.cmd.redraw()
  apply(buf, results)
  eq('above_blank', codelens.inspect().buffers[buf].placements[1])

  codelens.disable()
  vim.api.nvim_set_current_buf(previous_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  imageui.disable()
end)

test('CodeLens fallback-only rows are reconciled away', function()
  package.loaded.imageui = nil
  local imageui = require('imageui').setup({
    backend = require('imageui.backend.fake').new(),
    render = { cache = { directory = test_path('codelens-fallback') } },
    integrations = {
      codelens = {
        enabled = false,
        placement_order = { 'native' },
        debounce = 60000,
      },
    },
  })
  local codelens = require('imageui.integrations.codelens')
  codelens.enable()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'function example() {}' })
  codelens.schedule(buf)

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
  truthy(apply, 'could not locate private CodeLens reconciler')
  apply(buf, {
    {
      client_id = 999999,
      lens = {
        range = { start = { line = 0, character = 0 } },
        command = { title = '3 references', command = 'test.references' },
      },
    },
  })
  eq(1, codelens.inspect().buffers[buf].fallbacks)
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'inserted above' })
  apply(buf, {})
  eq(0, codelens.inspect().buffers[buf].fallbacks)
  eq(0, #vim.api.nvim_buf_get_extmarks(buf, codelens.namespace(), 0, -1, {}))
  codelens.disable()
  vim.api.nvim_buf_delete(buf, { force = true })
  imageui.disable()
end)

print(('1..%d'):format(count))
if failures > 0 then
  print(('%d test(s) failed'):format(failures))
  vim.cmd.cquit(1)
else
  print(('all %d tests passed'):format(count))
  vim.cmd('qa!')
end
