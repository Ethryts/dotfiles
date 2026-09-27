local nvim_img = require('imageui.backend.nvim_img')
local tmux = require('imageui.transport.tmux')

local M = {}

local function sequence(control, payload)
  local keys = vim.tbl_keys(control)
  table.sort(keys)
  local fields = {}
  for _, key in ipairs(keys) do
    fields[#fields + 1] = key .. '=' .. tostring(control[key])
  end
  return '\027_G'
    .. table.concat(fields, ',')
    .. (payload and payload ~= '' and ';' .. payload or '')
    .. '\027\\'
end

---@param opts? {send?: fun(data: string), max_assets?: integer, max_bytes?: integer, max_dormant_placements?: integer, max_control_batch_bytes?: integer, seed?: integer, available?: fun(): boolean, supported?: function, tmux?: 'auto'|'on'|'off'|boolean, tmux_env?: string, tmux_status?: ImageUI.TmuxStatus|fun(): ImageUI.TmuxStatus, tmux_geometry?: ImageUI.TmuxGeometry|fun(): ImageUI.TmuxGeometry, safe_reposition?: 'auto'|'on'|'off'|boolean, term_program?: string, wezterm_env?: string}
function M.new(opts)
  opts = opts or {}
  local send_raw = opts.send or vim.api.nvim_ui_send
  local max_assets = opts.max_assets or 256
  local max_bytes = opts.max_bytes or 64 * 1024 * 1024
  local max_dormant_placements = opts.max_dormant_placements or 64
  local max_control_batch_bytes = opts.max_control_batch_bytes or 64 * 1024
  assert(max_control_batch_bytes > 0, 'max_control_batch_bytes must be positive')
  local tmux_mode = opts.tmux or 'off'
  local tmux_detected = tmux.detected(opts.tmux_env)
  local tmux_passthrough = tmux.resolve(tmux_mode, opts.tmux_env)
  local function read_tmux_status()
    if type(opts.tmux_status) == 'function' then
      return opts.tmux_status()
    end
    if opts.tmux_status then
      return vim.deepcopy(opts.tmux_status)
    end
    return tmux.status({ env = opts.tmux_env })
  end
  local tmux_state = tmux_passthrough and read_tmux_status() or nil
  local function read_tmux_geometry()
    if type(opts.tmux_geometry) == 'function' then
      return opts.tmux_geometry()
    end
    if opts.tmux_geometry then
      return vim.deepcopy(opts.tmux_geometry)
    end
    return tmux.geometry({ env = opts.tmux_env })
  end
  local tmux_geometry = tmux_passthrough and read_tmux_geometry() or nil
  local tmux_forced = tmux_mode == true or tmux_mode == 'on'
  local tmux_option_ready = not tmux_passthrough
    or tmux_forced
    or (tmux_state and tmux_state.enabled)
  local tmux_geometry_ready = not tmux_passthrough or (tmux_geometry and tmux_geometry.valid)
  local tmux_ready = tmux_option_ready and tmux_geometry_ready
  local term_program = opts.term_program == nil and vim.env.TERM_PROGRAM or opts.term_program
  local wezterm_env = opts.wezterm_env == nil and vim.env.WEZTERM_EXECUTABLE or opts.wezterm_env
  local wezterm_detected = (type(term_program) == 'string' and term_program:lower() == 'wezterm')
    or (type(wezterm_env) == 'string' and wezterm_env ~= '')
  local safe_reposition_mode = opts.safe_reposition == nil and 'auto' or opts.safe_reposition
  local safe_reposition = safe_reposition_mode == true
    or safe_reposition_mode == 'on'
    or (safe_reposition_mode == 'auto' and wezterm_detected)
  assert(
    safe_reposition_mode == true
      or safe_reposition_mode == false
      or safe_reposition_mode == 'auto'
      or safe_reposition_mode == 'on'
      or safe_reposition_mode == 'off',
    'safe_reposition must be "auto", "on", or "off"'
  )
  local assets = {}
  local placements = {}
  local live_ids = {}
  local quarantined_ids = {}
  local healthy = true
  local transport_focused = true
  local unhealthy_reason
  local clock = 0
  local placement_generation = 0
  local control_batch_depth = 0
  local control_entries = {}
  local control_by_key = {}
  local control_bytes = 0
  local seed = opts.seed
    or tonumber(
      vim.fn.sha256(table.concat({ vim.fn.getpid(), vim.uv.hrtime(), tostring({}) }, ':')):sub(1, 8),
      16
    )
  local next_protocol_id = seed % 0x7ffffffe
  local stats = {
    transmissions = 0,
    transmitted_bytes = 0,
    wire_bytes = 0,
    send_calls = 0,
    tmux_envelopes = 0,
    control_commands = 0,
    control_batches = 0,
    coalesced_control_commands = 0,
    max_batch_commands = 0,
    max_batch_bytes = 0,
    places = 0,
    updates = 0,
    unplaces = 0,
    hard_deletes = 0,
    errors = 0,
    resident_decoded_bytes = 0,
    peak_assets = 0,
    peak_active_placements = 0,
    peak_resident_decoded_bytes = 0,
    capacity_rejections = 0,
    tmux_passthrough = tmux_passthrough,
    tmux_detected = tmux_detected,
    tmux_ready = tmux_ready == true,
    tmux_allow_passthrough = tmux_state and tmux_state.value or nil,
    tmux_forced = tmux_forced,
    wezterm_detected = wezterm_detected,
    safe_reposition = safe_reposition,
    safe_repositions = 0,
  }

  local backend = {}

  local function send(data)
    if tmux_passthrough and not transport_focused then
      error('tmux pane is not focused; terminal graphics writes are paused')
    end
    stats.send_calls = stats.send_calls + 1
    send_raw(data)
    stats.wire_bytes = stats.wire_bytes + #data
  end

  local function graphics(data)
    if tmux_passthrough then
      stats.tmux_envelopes = stats.tmux_envelopes + 1
      return tmux.wrap(data)
    end
    return data
  end

  local function reset_control_batch()
    control_entries = {}
    control_by_key = {}
    control_bytes = 0
  end

  local function flush_control_batch()
    if control_bytes == 0 then
      reset_control_batch()
      return true
    end
    local commands = {}
    local command_count = 0
    for _, entry in ipairs(control_entries) do
      if not entry.removed then
        commands[#commands + 1] = entry.command
        command_count = command_count + entry.command_count
      end
    end
    local payload = table.concat(commands)
    reset_control_batch()
    if payload == '' then
      return true
    end
    stats.control_batches = stats.control_batches + 1
    stats.control_commands = stats.control_commands + command_count
    stats.max_batch_commands = math.max(stats.max_batch_commands, command_count)
    stats.max_batch_bytes = math.max(stats.max_batch_bytes, #payload)
    send(graphics(payload))
    return true
  end

  ---Queue a terminal control operation. Repeated updates for the same placement
  ---collapse to their latest state while a manager reconciliation is open.
  ---@param command string
  ---@param command_count? integer
  ---@param key? string
  ---@param kind? 'place'|'update'|'delete'
  ---@param folded_place? string Pure placement command used to fold place -> update.
  local function queue_control(command, command_count, key, kind, folded_place)
    command_count = command_count or 1
    -- Creating or deleting a placement changes ownership observed by callers,
    -- so keep those writes synchronous and failure-atomic. Only idempotent
    -- moves are write-behind batched; they are the hot path during scrolling.
    if kind ~= 'update' then
      flush_control_batch()
      local entry = {
        command = command,
        command_count = command_count,
        key = key,
        kind = kind,
      }
      control_entries[1] = entry
      control_bytes = #command
      flush_control_batch()
      return
    end
    local existing = key and control_by_key[key] or nil
    local projected_bytes = control_bytes
      - (existing and not existing.removed and #existing.command or 0)
      + #command
    if control_bytes > 0 and projected_bytes > max_control_batch_bytes then
      flush_control_batch()
      existing = nil
    end
    if existing and not existing.removed then
      if existing.kind == 'place' and kind == 'update' then
        stats.coalesced_control_commands = stats.coalesced_control_commands
          + existing.command_count
          + command_count
          - 1
        control_bytes = control_bytes - #existing.command + #folded_place
        existing.command = folded_place
        existing.command_count = 1
        existing.kind = 'place'
      elseif existing.kind == 'place' and kind == 'delete' then
        stats.coalesced_control_commands = stats.coalesced_control_commands
          + existing.command_count
          + command_count
        control_bytes = control_bytes - #existing.command
        existing.removed = true
        control_by_key[key] = nil
      elseif existing.kind == 'update' and (kind == 'update' or kind == 'delete') then
        stats.coalesced_control_commands = stats.coalesced_control_commands + existing.command_count
        control_bytes = control_bytes - #existing.command + #command
        existing.command = command
        existing.command_count = command_count
        existing.kind = kind
      else
        existing = nil
      end
    end
    if not existing then
      local entry = {
        command = command,
        command_count = command_count,
        key = key,
        kind = kind,
      }
      control_entries[#control_entries + 1] = entry
      control_bytes = control_bytes + #command
      if key then
        control_by_key[key] = entry
      end
    end
    if control_batch_depth == 0 or control_bytes >= max_control_batch_bytes then
      flush_control_batch()
    end
  end

  local function allocate_id()
    repeat
      next_protocol_id = (next_protocol_id % 0x7ffffffe) + 1
    until not live_ids[next_protocol_id] and not quarantined_ids[next_protocol_id]
    live_ids[next_protocol_id] = true
    return next_protocol_id
  end

  local function release_id(id)
    live_ids[id] = nil
  end

  local function decoded_size(bytes)
    if #bytes >= 24 and bytes:sub(1, 8) == '\137PNG\r\n\26\n' and bytes:sub(13, 16) == 'IHDR' then
      local function u32(offset)
        local a, b, c, d = bytes:byte(offset, offset + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
      end
      local width = u32(17)
      local height = u32(21)
      if width > 0 and height > 0 then
        return width * height * 4
      end
    end
    return #bytes
  end

  local function transmit(image_id, bytes)
    -- Upload chunks are ordering barriers and deliberately never join a
    -- control batch: tmux limits the size of a single passthrough sequence.
    flush_control_batch()
    local encoded = vim.base64.encode(bytes)
    local position = 1
    while position <= #encoded do
      local final = math.min(position + 4095, #encoded)
      local control = { m = final == #encoded and 0 or 1 }
      if position == 1 then
        control.a = 't'
        control.f = 100
        control.i = image_id
        control.q = 2
        control.t = 'd'
      end
      send(graphics(sequence(control, encoded:sub(position, final))))
      position = final + 1
    end
    stats.transmissions = stats.transmissions + 1
    stats.transmitted_bytes = stats.transmitted_bytes + #bytes
  end

  local function place(asset, placement_id, generation, image_opts, update)
    local row = image_opts.row or 1
    local col = image_opts.col or 1
    if tmux_passthrough then
      row, col = tmux.project(tmux_geometry, row, col)
    end
    local cursor = ('\0277\027[%d;%dH'):format(row, col)
    local control = {
      a = 'p',
      C = 1,
      i = asset.image_id,
      p = placement_id,
      q = 2,
    }
    if image_opts.width then
      control.c = image_opts.width
    end
    if image_opts.height then
      control.r = image_opts.height
    end
    if image_opts.zindex then
      control.z = image_opts.zindex
    end
    -- Save/restore the cursor position, but never alter cursor visibility.
    -- Neovim owns that state and may intentionally hide it for the current mode.
    -- The cursor move and placement must cross tmux atomically. If the cursor
    -- move is left outside the passthrough envelope, tmux consumes it into its
    -- virtual pane state but may forward the Kitty command while the outer
    -- terminal cursor is elsewhere.
    local placement_command = cursor .. sequence(control) .. '\0278'
    local command = placement_command
    local command_count = 1
    if update and safe_reposition then
      -- WezTerm currently leaks render quads when an existing Kitty placement
      -- is repeatedly repositioned during DECSTBM scrolling. Deleting the
      -- placement first retains the uploaded image while avoiding that path.
      command = sequence({
        a = 'd',
        d = 'i',
        i = asset.image_id,
        p = placement_id,
        q = 2,
      }) .. placement_command
      command_count = 2
      stats.safe_repositions = stats.safe_repositions + 1
    end
    queue_control(
      command,
      command_count,
      ('placement:%d:%d'):format(placement_id, generation),
      update and 'update' or 'place',
      placement_command
    )
    stats.places = stats.places + 1
    if update then
      stats.updates = stats.updates + 1
    end
  end

  local function hard_delete(asset)
    flush_control_batch()
    send(graphics(sequence({ a = 'd', d = 'I', i = asset.image_id, q = 2 })))
    for id, placement in pairs(placements) do
      if placement.asset == asset then
        placements[id] = nil
        release_id(id)
      end
    end
    for _, id in ipairs(asset.free) do
      release_id(id)
    end
    release_id(asset.image_id)
    stats.resident_decoded_bytes = math.max(0, stats.resident_decoded_bytes - asset.decoded_bytes)
    assets[asset.key] = nil
    stats.hard_deletes = stats.hard_deletes + 1
  end

  local function prune()
    while vim.tbl_count(assets) > max_assets or stats.resident_decoded_bytes > max_bytes do
      local candidate
      for _, asset in pairs(assets) do
        if asset.active == 0 and (not candidate or asset.used < candidate.used) then
          candidate = asset
        end
      end
      if not candidate then
        return
      end
      local ok = pcall(hard_delete, candidate)
      if not ok then
        stats.errors = stats.errors + 1
        healthy = false
        unhealthy_reason =
          'terminal asset eviction failed; reset the transport before uploading more'
        return
      end
    end
  end

  local function make_room(decoded_bytes)
    while
      vim.tbl_count(assets) + 1 > max_assets
      or stats.resident_decoded_bytes + decoded_bytes > max_bytes
    do
      local candidate
      for _, current in pairs(assets) do
        if current.active == 0 and (not candidate or current.used < candidate.used) then
          candidate = current
        end
      end
      if not candidate then
        stats.capacity_rejections = stats.capacity_rejections + 1
        return false,
          ('terminal asset budget is full (%d assets / %.1f MiB decoded)'):format(
            vim.tbl_count(assets),
            stats.resident_decoded_bytes / 1024 / 1024
          )
      end
      local ok, err = pcall(hard_delete, candidate)
      if not ok then
        stats.errors = stats.errors + 1
        healthy = false
        unhealthy_reason =
          'terminal asset eviction failed; reset the transport before uploading more'
        return false, tostring(err)
      end
    end
    return true
  end

  local function tmux_unavailable_reason()
    if not tmux_option_ready then
      return 'tmux blocks passthrough'
        .. (tmux_state and tmux_state.error and (': ' .. tmux_state.error) or '')
        .. '; run `tmux set -g allow-passthrough on`'
    end
    if not tmux_geometry_ready then
      return 'tmux pane coordinates are unavailable'
        .. (tmux_geometry and tmux_geometry.error and (': ' .. tmux_geometry.error) or '')
    end
    return nil
  end

  function backend.available()
    if not healthy then
      return false, unhealthy_reason or 'Kitty transport is unhealthy'
    end
    local available, reason
    if opts.available then
      available, reason = opts.available()
    else
      available, reason = nvim_img.available()
    end
    if not available then
      return false, reason
    end
    if not tmux_ready then
      return false, tmux_unavailable_reason() or 'tmux passthrough is unavailable'
    end
    return true
  end

  function backend.begin_batch()
    assert(healthy, unhealthy_reason or 'Kitty transport is unhealthy')
    control_batch_depth = control_batch_depth + 1
    return true
  end

  function backend.end_batch()
    assert(control_batch_depth > 0, 'no ImageUI control batch is active')
    control_batch_depth = control_batch_depth - 1
    if control_batch_depth > 0 then
      return true
    end
    local ok, err = pcall(flush_control_batch)
    if not ok then
      stats.errors = stats.errors + 1
      healthy = false
      unhealthy_reason = 'terminal control batch failed; reset the transport: ' .. tostring(err)
      error(unhealthy_reason, 0)
    end
    return true
  end

  function backend.abort_batch(reason)
    reset_control_batch()
    control_batch_depth = 0
    if reason then
      stats.errors = stats.errors + 1
      healthy = false
      unhealthy_reason = 'terminal control batch was aborted: ' .. tostring(reason)
    end
    return true
  end

  ---@param refresh_opts? boolean|{verify?: boolean, replay?: boolean}
  function backend.refresh_transport(refresh_opts)
    if type(refresh_opts) == 'boolean' then
      refresh_opts = { verify = refresh_opts }
    else
      refresh_opts = refresh_opts or {}
    end
    local previous_geometry = tmux_geometry
    if tmux_passthrough and not tmux_forced and refresh_opts.verify then
      tmux_state = read_tmux_status()
      tmux_option_ready = tmux_state.enabled
    end
    if tmux_passthrough then
      tmux_geometry = read_tmux_geometry()
      tmux_geometry_ready = tmux_geometry and tmux_geometry.valid
    end
    tmux_ready = tmux_option_ready and tmux_geometry_ready
    local geometry_changed = tmux_ready
      and previous_geometry
      and previous_geometry.valid
      and (previous_geometry.row ~= tmux_geometry.row or previous_geometry.col ~= tmux_geometry.col)
    if geometry_changed or (tmux_ready and refresh_opts.replay) then
      local own_batch = control_batch_depth == 0
      if own_batch then
        backend.begin_batch()
      end
      for id, placement in pairs(placements) do
        local ok, err =
          pcall(place, placement.asset, id, placement.generation, placement.opts, true)
        if not ok then
          if own_batch then
            backend.abort_batch(err)
          end
          stats.errors = stats.errors + 1
          healthy = false
          unhealthy_reason = 'failed to move Kitty placements after tmux geometry changed: '
            .. tostring(err)
          return false, unhealthy_reason
        end
      end
      if own_batch then
        local ok, err = pcall(backend.end_batch)
        if not ok then
          return false, tostring(err)
        end
      end
    end
    return tmux_ready, not tmux_ready and tmux_unavailable_reason() or nil
  end

  function backend.set_focus(focused)
    transport_focused = focused ~= false
    return tmux_passthrough
  end

  function backend.supported(probe_opts)
    if opts.supported then
      return opts.supported(probe_opts)
    end
    if tmux_passthrough then
      local available, reason = backend.available()
      return available,
        available and 'tmux passthrough is active; the outer terminal capability was not probed'
          or reason
    end
    return nvim_img.supported(probe_opts)
  end

  ---@param bytes string
  ---@param image_opts table
  ---@param metadata? {key?: string}
  function backend.set(bytes, image_opts, metadata)
    assert(healthy, unhealthy_reason or 'Kitty transport is unhealthy')
    if tmux_passthrough and not transport_focused then
      return nil, 'tmux pane is not focused; image upload is deferred'
    end
    metadata = metadata or {}
    local key = metadata.key or vim.fn.sha256(bytes)
    clock = clock + 1
    local asset = assets[key]
    local created = false
    if not asset then
      local asset_decoded_bytes = decoded_size(bytes)
      local admitted, admission_error = make_room(asset_decoded_bytes)
      if not admitted then
        return nil, admission_error
      end
      asset = {
        key = key,
        image_id = allocate_id(),
        free = {},
        active = 0,
        used = clock,
        decoded_bytes = asset_decoded_bytes,
      }
      local ok, err = pcall(transmit, asset.image_id, bytes)
      if not ok then
        local aborted =
          pcall(send, graphics(sequence({ a = 'd', d = 'I', i = asset.image_id, q = 2 })))
        if not aborted then
          quarantined_ids[asset.image_id] = true
          healthy = false
          unhealthy_reason = 'partial Kitty upload could not be aborted; reset the transport'
        end
        release_id(asset.image_id)
        stats.errors = stats.errors + 1
        error(err, 0)
      end
      created = true
      assets[key] = asset
      stats.resident_decoded_bytes = stats.resident_decoded_bytes + asset.decoded_bytes
      stats.peak_assets = math.max(stats.peak_assets, vim.tbl_count(assets))
      stats.peak_resident_decoded_bytes =
        math.max(stats.peak_resident_decoded_bytes, stats.resident_decoded_bytes)
    end
    asset.used = clock
    local placement_id = table.remove(asset.free)
    local reused = placement_id ~= nil
    placement_id = placement_id or allocate_id()
    placement_generation = placement_generation + 1
    local generation = placement_generation
    local ok, err = pcall(place, asset, placement_id, generation, image_opts, false)
    if not ok then
      if reused then
        asset.free[#asset.free + 1] = placement_id
      else
        release_id(placement_id)
      end
      if created then
        local deleted = pcall(hard_delete, asset)
        if not deleted then
          stats.errors = stats.errors + 1
          healthy = false
          unhealthy_reason =
            'failed placement rollback left a terminal asset resident; reset the transport'
        end
      end
      stats.errors = stats.errors + 1
      error(err, 0)
    end
    placements[placement_id] = {
      id = placement_id,
      asset = asset,
      generation = generation,
      opts = vim.deepcopy(image_opts),
    }
    asset.active = asset.active + 1
    stats.peak_active_placements = math.max(stats.peak_active_placements, vim.tbl_count(placements))
    prune()
    return placement_id
  end

  function backend.update(id, image_opts)
    assert(healthy, unhealthy_reason or 'Kitty transport is unhealthy')
    local placement = assert(placements[id], 'invalid ImageUI placement id: ' .. tostring(id))
    local next_opts = vim.tbl_extend('force', vim.deepcopy(placement.opts), image_opts)
    local ok, err = pcall(place, placement.asset, id, placement.generation, next_opts, true)
    if not ok then
      stats.errors = stats.errors + 1
      error(err, 0)
    end
    placement.opts = next_opts
    clock = clock + 1
    placement.asset.used = clock
  end

  function backend.delete(id)
    local placement = placements[id]
    if not placement then
      return false
    end
    local ok, err = pcall(
      queue_control,
      sequence({
        a = 'd',
        d = 'i',
        i = placement.asset.image_id,
        p = id,
        q = 2,
      }),
      1,
      ('placement:%d:%d'):format(id, placement.generation),
      'delete'
    )
    if not ok then
      stats.errors = stats.errors + 1
      error(err, 0)
    end
    placements[id] = nil
    placement.asset.active = placement.asset.active - 1
    if #placement.asset.free < max_dormant_placements then
      placement.asset.free[#placement.asset.free + 1] = id
    else
      release_id(id)
    end
    stats.unplaces = stats.unplaces + 1
    prune()
    return true
  end

  function backend.get(id)
    return placements[id] and vim.deepcopy(placements[id].opts) or nil
  end

  function backend.clear()
    local current = vim.tbl_values(assets)
    for _, asset in ipairs(current) do
      local ok = pcall(hard_delete, asset)
      if not ok then
        stats.errors = stats.errors + 1
      end
    end
    for id in pairs(quarantined_ids) do
      local ok = pcall(send, graphics(sequence({ a = 'd', d = 'I', i = id, q = 2 })))
      if ok then
        quarantined_ids[id] = nil
      else
        stats.errors = stats.errors + 1
      end
    end
    if next(quarantined_ids) == nil then
      healthy = next(assets) == nil
        or (vim.tbl_count(assets) <= max_assets and stats.resident_decoded_bytes <= max_bytes)
      unhealthy_reason = healthy and nil or unhealthy_reason
    end
    local cleared = next(assets) == nil and next(quarantined_ids) == nil
    return cleared, not cleared and 'some terminal assets could not be released'
  end

  function backend.forget()
    reset_control_batch()
    control_batch_depth = 0
    assets = {}
    placements = {}
    live_ids = {}
    quarantined_ids = {}
    healthy = true
    unhealthy_reason = nil
    stats.resident_decoded_bytes = 0
  end

  function backend.stats()
    local result = vim.deepcopy(stats)
    result.assets = vim.tbl_count(assets)
    result.active_placements = vim.tbl_count(placements)
    local dormant = 0
    for _, asset in pairs(assets) do
      dormant = dormant + #asset.free
    end
    result.dormant_placements = dormant
    result.live_protocol_ids = vim.tbl_count(live_ids)
    result.max_assets = max_assets
    result.max_decoded_bytes = max_bytes
    result.max_control_batch_bytes = max_control_batch_bytes
    result.pending_control_commands = 0
    result.pending_control_bytes = control_bytes
    for _, entry in ipairs(control_entries) do
      if not entry.removed then
        result.pending_control_commands = result.pending_control_commands + entry.command_count
      end
    end
    result.tmux_ready = tmux_ready == true
    result.tmux_allow_passthrough = tmux_state and tmux_state.value or nil
    result.tmux_forced = tmux_forced
    result.tmux_geometry = tmux_geometry and vim.deepcopy(tmux_geometry) or nil
    result.tmux_focused = transport_focused
    result.healthy = healthy
    result.unhealthy_reason = unhealthy_reason
    result.quarantined_ids = vim.tbl_count(quarantined_ids)
    return result
  end

  function backend._assets()
    return assets
  end

  function backend._placements()
    return placements
  end

  return backend
end

local active

function M.setup(opts)
  opts = opts or {}
  if opts.tmux == nil then
    opts.tmux = 'auto'
  end
  if active then
    local ok, cleared = pcall(active.clear)
    if not ok or not cleared then
      error('imageui.nvim: unable to replace the active Kitty pool before it is cleared')
    end
  end
  active = M.new(opts)
  return active
end

local cleanup_group = vim.api.nvim_create_augroup('ImageUIBackendKittyPool', { clear = true })
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = cleanup_group,
  callback = function()
    if active then
      pcall(active.clear)
    end
  end,
})

local function delegate(name)
  return function(...)
    active = active or M.setup()
    return active[name](...)
  end
end

for _, name in ipairs({
  'available',
  'supported',
  'set',
  'update',
  'delete',
  'get',
  'clear',
  'forget',
  'stats',
  'begin_batch',
  'end_batch',
  'abort_batch',
  'refresh_transport',
  'set_focus',
}) do
  M[name] = delegate(name)
end

return M
