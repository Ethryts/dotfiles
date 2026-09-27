local anchor = require('imageui.anchor')
local backend_module = require('imageui.backend')
local crop = require('imageui.renderer.crop')
local fs = require('imageui.util.fs')
local interaction_geometry = require('imageui.interaction_geometry')
local log = require('imageui.util.log')
local placement = require('imageui.placement')
local renderer = require('imageui.renderer')
local scheduler_module = require('imageui.util.scheduler')

local M = {}

local config
local backend
local widgets = {}
local buffer_marks = {}
local non_buffer_widgets = {}
local active_buffer_widgets = {}
local next_id = 0
local scheduler
local enabled = false
local augroup
local redraw_ns = vim.api.nvim_create_namespace('imageui.nvim:redraw-sync')
local redraw_refresh_pending = false
local redraw_observers = {}
local redraw_signature
local cursor_widget_count = 0
local reconcile_count = 0
local reconciling = false
local backend_counts = { set = 0, update = 0, delete = 0, bytes = 0 }
local reconcile_times = {}
local reconcile_time_total = 0
local reconcile_time_max = 0
local redraw_counts = { callbacks = 0, changed = 0, unchanged = 0 }
local hit_rows = {}
local hover_target
local dispatch_target
local hit_counts = { queries = 0, candidates = 0, max_candidates = 0 }

---@param widget table
local function index_widget(widget)
  if widget.anchor.kind == 'buffer' then
    buffer_marks[widget.anchor.buffer] = buffer_marks[widget.anchor.buffer] or {}
    buffer_marks[widget.anchor.buffer][widget.anchor.mark] = widget
  else
    non_buffer_widgets[widget.id] = widget
  end
end

---@param widget table
local function unindex_widget(widget)
  if widget.anchor.kind == 'buffer' then
    local marks = buffer_marks[widget.anchor.buffer]
    if marks then
      marks[widget.anchor.mark] = nil
      if next(marks) == nil then
        buffer_marks[widget.anchor.buffer] = nil
      end
    end
    active_buffer_widgets[widget.id] = nil
  else
    non_buffer_widgets[widget.id] = nil
  end
end

---@param win integer
---@param top integer
---@param bottom integer
---@return table[]
local function visible_line_intervals(win, top, bottom)
  local rows = vim.api.nvim_win_call(win, function()
    local result = {}
    local line = top
    while line <= bottom do
      local fold_start = vim.fn.foldclosed(line)
      if fold_start == -1 then
        result[#result + 1] = line
        line = line + 1
      else
        if fold_start >= top and fold_start <= bottom then
          result[#result + 1] = fold_start
        end
        local fold_end = vim.fn.foldclosedend(line)
        line = math.max(line + 1, fold_end + 1)
      end
    end
    return result
  end)
  local intervals = {}
  for _, line in ipairs(rows) do
    local current = intervals[#intervals]
    if current and current[2] + 1 == line then
      current[2] = line
    elseif not current or current[2] ~= line then
      intervals[#intervals + 1] = { line, line }
    end
  end
  return intervals
end

---@param win integer
---@param top integer 1-based inclusive line
---@param bottom integer 1-based inclusive line
---@return table[]
function M._visible_line_intervals(win, top, bottom)
  return visible_line_intervals(win, top, bottom)
end

---@return table<table, table<integer, boolean>>
local function visible_buffer_windows()
  local result = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local marks = buffer_marks[buf]
      if marks then
        local info = vim.fn.getwininfo(win)[1] or {}
        local top = math.max(1, info.topline or 1)
        local bottom = math.max(top, info.botline or top)
        for _, interval in ipairs(visible_line_intervals(win, top, bottom)) do
          local extmarks = vim.api.nvim_buf_get_extmarks(
            buf,
            anchor.namespace(),
            { interval[1] - 1, 0 },
            { interval[2] - 1, -1 },
            {}
          )
          for _, extmark in ipairs(extmarks) do
            local widget = marks[extmark[1]]
            if
              widget
              and (
                not widget.anchor.window
                or widget.anchor.window == 0
                or widget.anchor.window == win
              )
            then
              result[widget] = result[widget] or {}
              result[widget][win] = true
            end
          end
        end
      end
    end
  end
  return result
end

local function record_reconcile(started)
  local elapsed = (vim.uv.hrtime() - started) / 1e6
  reconcile_time_total = reconcile_time_total + elapsed
  reconcile_time_max = math.max(reconcile_time_max, elapsed)
  reconcile_times[#reconcile_times + 1] = elapsed
  if #reconcile_times > 256 then
    table.remove(reconcile_times, 1)
  end
end

local function reconcile_timing()
  local samples = vim.deepcopy(reconcile_times)
  table.sort(samples)
  local function percentile(value)
    if #samples == 0 then
      return 0
    end
    return samples[math.max(1, math.ceil(#samples * value))]
  end
  return {
    samples = #samples,
    average = reconcile_count > 0 and reconcile_time_total / reconcile_count or 0,
    maximum = reconcile_time_max,
    p50 = percentile(0.50),
    p95 = percentile(0.95),
    p99 = percentile(0.99),
  }
end

---@return string
local function viewport_signature()
  local parts = {
    tostring(vim.o.lines),
    tostring(vim.o.columns),
    tostring(vim.api.nvim_get_current_tabpage()),
    tostring(vim.api.nvim_get_current_win()),
  }
  local wins = vim.api.nvim_tabpage_list_wins(0)
  table.sort(wins)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local info = vim.fn.getwininfo(win)[1] or {}
      local bufnr = vim.api.nvim_win_get_buf(win)
      local win_config = vim.api.nvim_win_get_config(win)
      vim.list_extend(parts, {
        tostring(win),
        tostring(bufnr),
        tostring(vim.api.nvim_buf_get_changedtick(bufnr)),
        tostring(info.winrow),
        tostring(info.wincol),
        tostring(info.width),
        tostring(info.height),
        tostring(info.textoff),
        tostring(info.topline),
        tostring(info.botline),
        tostring(info.leftcol),
        tostring(info.skipcol),
        tostring(info.winbar),
        tostring(win_config.relative),
        tostring(win_config.row),
        tostring(win_config.col),
        tostring(win_config.width),
        tostring(win_config.height),
        tostring(win_config.zindex),
        tostring(win_config.hide),
      })
    end
  end
  return table.concat(parts, '\0')
end

---@param widget table
---@param name string
local function call_widget_callback(widget, name, ...)
  local callback = widget.spec[name]
  if type(callback) ~= 'function' then
    return
  end
  local ok, err = pcall(callback, ...)
  if not ok then
    log.error(('widget %d %s callback failed: %s'):format(widget.id, name, err))
  end
end

---@param widget table
---@param err string?
local function call_fallback(widget, err)
  if widget.fallback_called or type(widget.spec.fallback) ~= 'function' then
    return
  end
  widget.fallback_called = true
  widget.fallback_token = widget.fallback_token + 1
  local token = widget.fallback_token
  vim.schedule(function()
    if
      widgets[widget.id] == widget
      and widget.fallback_called
      and widget.fallback_token == token
    then
      call_widget_callback(widget, 'fallback', widget.id, err)
    end
  end)
end

local function backend_call(method, ...)
  if backend_counts[method] ~= nil then
    backend_counts[method] = backend_counts[method] + 1
    if method == 'set' then
      local bytes = select(1, ...)
      if type(bytes) == 'string' then
        backend_counts.bytes = backend_counts.bytes + #bytes
      end
    end
  end
  local ok, result, detail = pcall(backend[method], ...)
  if not ok then
    log.error(('image backend %s() failed: %s'):format(method, result))
    return nil, result
  end
  return result, detail
end

local function region_callback(widget, node_id, action, region_actions)
  region_actions = region_actions or widget.spec.region_actions
  local entry = node_id and region_actions and region_actions[node_id]
  if type(entry) == 'function' and (action == 'click' or action == 'activate') then
    return entry
  end
  return type(entry) == 'table' and entry[action] or nil
end

local function unregister_view(view)
  local targets = view.hit_targets or {}
  view.hit_targets = nil
  for _, target in ipairs(targets) do
    for row = target.rect.top, target.rect.bottom do
      local entries = hit_rows[row]
      if entries then
        for index = #entries, 1, -1 do
          if entries[index] == target then
            table.remove(entries, index)
          end
        end
        if #entries == 0 then
          hit_rows[row] = nil
        end
      end
    end
    if hover_target == target then
      local leaving = hover_target
      hover_target = nil
      if dispatch_target then
        dispatch_target(leaving, 'leave', nil, 'lifecycle')
      end
    end
  end
end

local function index_target(view, target)
  view.hit_targets = view.hit_targets or {}
  view.hit_targets[#view.hit_targets + 1] = target
  for row = target.rect.top, target.rect.bottom do
    hit_rows[row] = hit_rows[row] or {}
    hit_rows[row][#hit_rows[row] + 1] = target
  end
end

local function register_view(widget, view)
  local registration = (view.hit_registration or 0) + 1
  view.hit_registration = registration
  unregister_view(view)
  if view.hit_registration ~= registration then
    -- A lifecycle callback installed a newer registration for this view.
    return true
  end
  if widget.deleting or widgets[widget.id] ~= widget or widget.views[view.key] ~= view then
    return false
  end
  local interactive = {}
  for _, region in ipairs(view.manifest and view.manifest.regions or {}) do
    if
      not region.disabled
      and region.pointer ~= 'none'
      and (
        region.focusable or (widget.spec.region_actions and widget.spec.region_actions[region.id])
      )
    then
      interactive[region.id] = true
    end
  end
  local collisions =
    interaction_geometry.collisions(view.manifest and view.manifest.regions or {}, interactive)
  for index, collision in ipairs(collisions) do
    if index > 4 then
      break
    end
    local key = collision.first .. '\0' .. collision.second
    if not widget.hit_collision_warnings[key] then
      widget.hit_collision_warnings[key] = true
      log.warn(
        ('widget %d interactive regions %q and %q overlap; the later painted node wins'):format(
          widget.id,
          collision.first,
          collision.second
        ),
        true
      )
    end
  end
  if (#collisions > 4 or collisions.truncated) and not widget.hit_collision_warnings.truncated then
    widget.hit_collision_warnings.truncated = true
    log.warn(
      ('widget %d has additional overlapping interactive regions; further pair warnings are suppressed'):format(
        widget.id
      ),
      true
    )
  end
  for _, region in ipairs(view.manifest and view.manifest.regions or {}) do
    if
      not region.disabled
      and region.pointer ~= 'none'
      and (
        region.focusable or (widget.spec.region_actions and widget.spec.region_actions[region.id])
      )
    then
      local rect = interaction_geometry.project(region, view)
      if rect then
        index_target(view, {
          widget = widget,
          widget_id = widget.id,
          surface_id = widget.spec.surface_id,
          node_id = region.id,
          win = view.win,
          view = view,
          rect = rect,
          zindex = view.opts.zindex or 0,
          paint_order = region.paint_order or 0,
          creation_order = widget.id,
          region = region,
        })
      end
    end
  end
  if widget.spec.actions and next(widget.spec.actions) then
    index_target(view, {
      widget = widget,
      widget_id = widget.id,
      surface_id = widget.spec.surface_id,
      win = view.win,
      view = view,
      rect = vim.deepcopy(view.rect),
      zindex = view.opts.zindex or 0,
      paint_order = -1,
      creation_order = widget.id,
    })
  end
  return true
end

local function validate_manifest(manifest)
  for _, region in ipairs(manifest and manifest.regions or {}) do
    interaction_geometry.hit_rect(region)
  end
end

---@param widget table
---@param view table
local function delete_view(widget, view)
  if view.deleted or view.deleting then
    return true
  end
  view.deleting = true
  if view.image_id then
    local _, err = backend_call('delete', view.image_id)
    if err then
      view.deleting = false
      return false, err
    end
  end
  widget.views[view.key] = nil
  view.deleted = true
  view.deleting = false
  unregister_view(view)
  call_widget_callback(widget, 'on_hide', widget.id, view.win, view.rect)
  return true
end

---@param widget table
local function delete_views(widget)
  local current = {}
  for _, view in pairs(widget.views) do
    current[#current + 1] = view
  end
  local deleted = true
  for _, view in ipairs(current) do
    deleted = delete_view(widget, view) and deleted
  end
  return deleted
end

---Drop view records that an authoritative backend says no longer exist. This
---keeps retryable placements after a partial clear while avoiding stale view
---records for assets the same clear already released.
local function sanitize_backend_views()
  if type(backend.get) ~= 'function' then
    return
  end
  for _, widget in pairs(widgets) do
    for key, view in pairs(widget.views) do
      if view.image_id then
        local current, err = backend_call('get', view.image_id)
        if current == nil and err == nil then
          unregister_view(view)
          widget.views[key] = nil
        end
      end
    end
  end
end

---@param widget table
---@param win integer
local function delete_window_views(widget, win)
  local current = {}
  for _, view in pairs(widget.views) do
    if view.win == win then
      current[#current + 1] = view
    end
  end
  for _, view in ipairs(current) do
    delete_view(widget, view)
  end
end

---@param widget table
---@param win integer
local function cancel_render(widget, win)
  local cancel = widget.rendering[win]
  widget.rendering[win] = nil
  if type(cancel) == 'function' then
    pcall(cancel)
  end
end

---@param widget table
---@param key string
local function cancel_pending_view(widget, key)
  local pending = widget.pending_views[key]
  widget.pending_views[key] = nil
  if pending and type(pending.cancel) == 'function' then
    pcall(pending.cancel)
  end
end

---@param widget table
local function cancel_async(widget)
  for win in pairs(widget.rendering) do
    cancel_render(widget, win)
  end
  for key in pairs(widget.pending_views) do
    cancel_pending_view(widget, key)
  end
end

---@param widget table
local function invalidate_widget_assets(widget)
  widget.reconcile_token = widget.reconcile_token + 1
  widget.desired = {}
  widget.render_generation = widget.render_generation + 1
  cancel_async(widget)
  widget.assets = {}
  widget.fallback_called = false
  widget.fallback_token = widget.fallback_token + 1
  delete_views(widget)
end

---@param widget table
---@param win integer
local function ensure_asset(widget, win)
  if widget.assets[win] or widget.rendering[win] then
    return
  end
  widget.rendering[win] = true
  local generation = widget.render_generation
  local window_generation = widget.render_window_generations[win] or 0
  local render_win = win == 0 and vim.api.nvim_get_current_win() or win
  local ok, cancel_or_error = pcall(
    renderer.render,
    widget.spec.content,
    render_win,
    function(asset, err)
      local current = widgets[widget.id]
      if
        not current
        or current.render_generation ~= generation
        or (current.render_window_generations[win] or 0) ~= window_generation
      then
        return
      end
      if not vim.tbl_contains(anchor.windows(current.anchor), win) then
        current.rendering[win] = nil
        return
      end
      current.rendering[win] = nil
      if not asset then
        current.render_error = err
        call_fallback(current, err)
        return
      end
      current.render_error = nil
      current.assets[win] = asset
      call_widget_callback(current, 'on_render', current.id, asset, win)
      -- PNG and cached renders may complete synchronously while this widget is
      -- already being reconciled. Scheduling another full pass in that case
      -- doubles the work for no state change.
      if not reconciling then
        M.refresh()
      end
    end
  )
  if not ok then
    widget.rendering[win] = nil
    widget.render_error = tostring(cancel_or_error)
    call_fallback(widget, tostring(cancel_or_error))
  elseif widget.rendering[win] == true and type(cancel_or_error) == 'function' then
    widget.rendering[win] = cancel_or_error
  end
end

---@param widget table
---@param view table
local function call_on_show(widget, view)
  widget.fallback_called = false
  widget.fallback_token = widget.fallback_token + 1
  widget.render_error = nil
  call_widget_callback(widget, 'on_show', widget.id, view.asset, view.win, view.rect)
end

---@param widget table
---@param resolved table
---@param asset table
---@param token integer
local function show(widget, resolved, asset, token)
  local pending = widget.pending_views[resolved.key]
  if pending and pending.asset_key == asset.key then
    pending.resolved = resolved
    pending.token = token
    return
  end
  pending = {
    asset_key = asset.key,
    resolved = resolved,
    token = token,
  }
  widget.pending_views[resolved.key] = pending
  local cancel = crop.get(asset, resolved.crop, function(display_asset, err)
    local current = widgets[widget.id]
    if not current or current.pending_views[resolved.key] ~= pending then
      return
    end
    current.pending_views[resolved.key] = nil
    resolved = pending.resolved
    token = pending.token
    if current.reconcile_token ~= token or not current.desired[resolved.key] then
      return
    end
    if not display_asset then
      current.render_error = err
      call_fallback(current, err)
      return
    end

    local ok, bytes = pcall(crop.bytes, display_asset)
    if not ok then
      current.render_error = tostring(bytes)
      call_fallback(current, tostring(bytes))
      return
    end

    local manifest_ok, manifest_error = pcall(validate_manifest, asset.manifest)
    if not manifest_ok then
      current.render_error = tostring(manifest_error)
      call_fallback(current, tostring(manifest_error))
      return
    end

    local view = current.views[resolved.key]
    if view and view.asset_key == display_asset.key then
      local geometry_changed = not vim.deep_equal(view.rect, resolved.rect)
        or not vim.deep_equal(view.crop, resolved.crop)
      local updated = false
      if not vim.deep_equal(view.opts, resolved.opts) then
        local _, update_error = backend_call('update', view.image_id, resolved.opts)
        if update_error then
          call_fallback(current, update_error)
          return
        end
        view.opts = vim.deepcopy(resolved.opts)
        updated = true
      end
      view.rect = resolved.rect
      view.crop = vim.deepcopy(resolved.crop)
      view.manifest = asset.manifest
      if geometry_changed or updated then
        if not register_view(current, view) then
          return
        end
      end
      if updated then
        call_on_show(current, view)
      end
      return
    end

    if view then
      local deleted, delete_error = delete_view(current, view)
      if not deleted then
        call_fallback(current, delete_error)
        return
      end
    end
    local image_id, set_error = backend_call('set', bytes, resolved.opts, {
      key = display_asset.key,
      path = display_asset.path,
    })
    if not image_id then
      call_fallback(current, set_error or 'image backend rejected the rendered image')
      return
    end
    local new_view = {
      key = resolved.key,
      image_id = image_id,
      asset_key = display_asset.key,
      asset = display_asset,
      opts = vim.deepcopy(resolved.opts),
      rect = resolved.rect,
      crop = vim.deepcopy(resolved.crop),
      manifest = asset.manifest,
      win = resolved.win,
    }
    current.views[resolved.key] = new_view
    if not register_view(current, new_view) then
      return
    end
    call_on_show(current, new_view)
  end)
  if widget.pending_views[resolved.key] == pending and type(cancel) == 'function' then
    pending.cancel = cancel
  end
end

function M.reconcile()
  if not enabled then
    return
  end
  local started = vim.uv.hrtime()
  reconciling = true
  reconcile_count = reconcile_count + 1

  local available, reason = backend_call('available')
  if not available then
    for _, widget in pairs(widgets) do
      widget.reconcile_token = widget.reconcile_token + 1
      widget.desired = {}
      widget.render_error = reason
      call_fallback(widget, reason)
      delete_views(widget)
    end
    reconciling = false
    record_reconcile(started)
    return
  end

  local batched = type(backend.begin_batch) == 'function'
    and type(backend.end_batch) == 'function'
    and backend_call('begin_batch') == true

  local visible_buffers = visible_buffer_windows()
  local candidates = {}
  for _, widget in pairs(non_buffer_widgets) do
    candidates[widget.id] = widget
  end
  for widget in pairs(visible_buffers) do
    candidates[widget.id] = widget
  end
  for id, widget in pairs(active_buffer_widgets) do
    candidates[id] = widget
  end
  local next_active_buffer_widgets = {}

  for _, widget in pairs(candidates) do
    widget.reconcile_token = widget.reconcile_token + 1
    local token = widget.reconcile_token
    local desired = {}
    widget.desired = desired
    widget.placement_results = {}

    local current_windows
    if widget.anchor.kind == 'buffer' then
      current_windows = vim.tbl_keys(visible_buffers[widget] or {})
      table.sort(current_windows)
      if #current_windows > 0 then
        next_active_buffer_widgets[widget.id] = widget
      end
    else
      current_windows = anchor.windows(widget.anchor)
    end
    local window_set = {}
    local visible_windows = {}
    for _, win in ipairs(current_windows) do
      window_set[win] = true
      if anchor.screen_position(widget.anchor, win) then
        visible_windows[win] = true
      end
    end
    local next_style_keys = {}
    local changed_style_windows = {}
    for _, win in ipairs(current_windows) do
      if visible_windows[win] then
        local key = renderer.style_key(widget.spec.content, win)
        next_style_keys[win] = key
        if widget.style_keys[win] ~= nil and widget.style_keys[win] ~= key then
          changed_style_windows[#changed_style_windows + 1] = win
        end
      else
        next_style_keys[win] = widget.style_keys[win]
      end
    end
    if #changed_style_windows > 0 then
      widget.reconcile_token = widget.reconcile_token + 1
      token = widget.reconcile_token
      desired = {}
      widget.desired = desired
      for _, win in ipairs(changed_style_windows) do
        widget.render_window_generations[win] = (widget.render_window_generations[win] or 0) + 1
        widget.assets[win] = nil
        cancel_render(widget, win)
        delete_window_views(widget, win)
      end
    end
    widget.style_keys = next_style_keys
    for win in pairs(widget.assets) do
      if not window_set[win] then
        widget.assets[win] = nil
        cancel_render(widget, win)
      end
    end
    for win in pairs(widget.rendering) do
      if not window_set[win] then
        cancel_render(widget, win)
      end
    end

    for _, win in ipairs(current_windows) do
      if visible_windows[win] then
        ensure_asset(widget, win)
        local asset = widget.assets[win]
        if asset then
          local resolved_views, placement_details = placement.resolve(widget, asset, win)
          widget.placement_results[win] = placement_details[win]
          for _, resolved in ipairs(resolved_views) do
            desired[resolved.key] = true
            show(widget, resolved, asset, token)
          end
        else
          widget.placement_results[win] = {
            win = win,
            reason = widget.render_error and 'render_error' or 'rendering',
            error = widget.render_error,
          }
        end
      end
    end

    local obsolete = {}
    for key, view in pairs(widget.views) do
      if not desired[key] then
        obsolete[#obsolete + 1] = view
      end
    end
    for _, view in ipairs(obsolete) do
      if not delete_view(widget, view) then
        next_active_buffer_widgets[widget.id] = widget
      end
    end
    for key in pairs(widget.pending_views) do
      if not desired[key] then
        cancel_pending_view(widget, key)
      end
    end
    for win in pairs(widget.assets) do
      if not visible_windows[win] then
        widget.assets[win] = nil
      end
    end
    for win in pairs(widget.rendering) do
      if not visible_windows[win] then
        cancel_render(widget, win)
      end
    end
  end
  active_buffer_widgets = next_active_buffer_widgets
  if batched then
    local committed = backend_call('end_batch') == true
    if not committed then
      vim.schedule(function()
        if enabled then
          M.reset_transport()
        end
      end)
    end
  end
  reconciling = false
  record_reconcile(started)
end

---@param delay? integer
function M.refresh(delay)
  if scheduler then
    scheduler:schedule(delay)
  end
end

function M.flush()
  if scheduler then
    scheduler:flush()
  end
end

---@param opts table
function M.setup(opts)
  config = opts
  backend = backend_module.get()
  placement.setup(opts)
  renderer.setup(opts)
  crop.setup(opts)
  require('imageui.renderer.jobs').setup(opts)
end

function M.enable()
  if enabled then
    return
  end
  enabled = true
  reconcile_count = 0
  reconcile_times = {}
  reconcile_time_total = 0
  reconcile_time_max = 0
  redraw_counts = { callbacks = 0, changed = 0, unchanged = 0 }
  backend_counts = { set = 0, update = 0, delete = 0, bytes = 0 }
  hit_counts = { queries = 0, candidates = 0, max_candidates = 0 }
  scheduler = scheduler_module.new(config.placement.debounce, M.reconcile)
  augroup = vim.api.nvim_create_augroup('ImageUIManager', { clear = true })

  local available, reason = backend_call('available')
  if not available then
    log.warn(reason or 'image backend is unavailable', config.backend == 'auto')
  end

  vim.api.nvim_set_decoration_provider(redraw_ns, {
    on_win = function()
      redraw_counts.callbacks = redraw_counts.callbacks + 1
      if redraw_refresh_pending then
        return false
      end
      redraw_refresh_pending = true
      vim.schedule(function()
        redraw_refresh_pending = false
        if enabled then
          local signature = viewport_signature()
          if signature == redraw_signature then
            redraw_counts.unchanged = redraw_counts.unchanged + 1
            return
          end
          redraw_counts.changed = redraw_counts.changed + 1
          redraw_signature = signature
          for name, callback in pairs(redraw_observers) do
            local ok, err = pcall(callback)
            if not ok then
              log.error(('redraw observer %s failed: %s'):format(name, err))
            end
          end
          M.refresh(config.placement.scroll_debounce)
        end
      end)
      return false
    end,
  })

  vim.api.nvim_create_autocmd({
    'WinResized',
    'VimResized',
    'WinNew',
    'WinEnter',
    'WinClosed',
    'TabEnter',
    'BufWinEnter',
    'BufWinLeave',
    'TextChanged',
    'TextChangedI',
    'TextChangedP',
    'CompleteChanged',
    'CompleteDone',
    'ModeChanged',
    'DiagnosticChanged',
    'LspProgress',
    'UILeave',
  }, {
    group = augroup,
    callback = function(args)
      if args.event == 'VimResized' and type(backend.refresh_transport) == 'function' then
        backend_call('refresh_transport')
      end
      redraw_signature = nil
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd({ 'FocusGained', 'FocusLost' }, {
    group = augroup,
    callback = function(args)
      local gained = args.event == 'FocusGained'
      local transport_managed = false
      if type(backend.set_focus) == 'function' then
        transport_managed = backend_call('set_focus', gained) == true
      end
      redraw_signature = nil
      if gained and transport_managed then
        local replayed = backend_call('refresh_transport', { replay = true })
        if replayed then
          M.refresh()
        else
          M.reset_transport()
        end
      elseif gained then
        M.refresh()
      end
    end,
  })
  vim.api.nvim_create_autocmd('UIEnter', {
    group = augroup,
    callback = function()
      redraw_signature = nil
      M.reset_transport(true)
    end,
  })
  vim.api.nvim_create_autocmd('WinScrolled', {
    group = augroup,
    callback = function()
      redraw_signature = nil
      M.refresh(config.placement.scroll_debounce)
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = augroup,
    callback = function()
      if cursor_widget_count > 0 then
        M.refresh()
      end
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = augroup,
    callback = function()
      M.invalidate_styles()
    end,
  })
  vim.api.nvim_create_autocmd('OptionSet', {
    group = augroup,
    pattern = {
      'number',
      'relativenumber',
      'signcolumn',
      'foldcolumn',
      'winbar',
      'statuscolumn',
      'statusline',
      'laststatus',
      'showtabline',
      'cmdheight',
      'wrap',
      'linebreak',
      'breakindent',
      'breakindentopt',
      'smoothscroll',
      'scrolloff',
      'sidescroll',
      'sidescrolloff',
      'list',
      'listchars',
      'conceallevel',
      'concealcursor',
      'foldenable',
      'foldmethod',
      'foldlevel',
      'diff',
    },
    callback = function()
      redraw_signature = nil
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd('OptionSet', {
    group = augroup,
    pattern = {
      'winhighlight',
      'fillchars',
      'winborder',
      'winblend',
      'pumblend',
      'background',
      'termguicolors',
    },
    callback = M.invalidate_styles,
  })
  redraw_signature = viewport_signature()
  M.refresh()
end

function M.disable()
  pcall(vim.api.nvim_set_decoration_provider, redraw_ns, {})
  redraw_refresh_pending = false
  redraw_signature = nil
  reconciling = false
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  if scheduler then
    scheduler:close()
    scheduler = nil
  end
  local released = true
  for _, widget in pairs(widgets) do
    cancel_async(widget)
    released = delete_views(widget) and released
  end
  if type(backend.clear) == 'function' then
    local cleared = backend_call('clear')
    if cleared then
      released = true
      for _, widget in pairs(widgets) do
        for _, view in pairs(widget.views) do
          unregister_view(view)
        end
        widget.views = {}
      end
    else
      released = false
      sanitize_backend_views()
    end
  end
  if not released then
    -- Preserve widget/anchor ownership so enable() or a later disable() can
    -- retry the terminal cleanup instead of orphaning ghost placements.
    enabled = false
    return false
  end
  for _, widget in pairs(widgets) do
    anchor.delete(widget.anchor)
  end
  widgets = {}
  buffer_marks = {}
  non_buffer_widgets = {}
  active_buffer_widgets = {}
  hit_rows = {}
  hover_target = nil
  cursor_widget_count = 0
  enabled = false
  return true
end

---@param spec table
---@return integer
function M.create(spec)
  vim.validate('spec', spec, 'table')
  assert(type(spec.content) == 'table', 'imageui widget requires content')
  assert(type(spec.anchor) == 'table', 'imageui widget requires an anchor')
  next_id = next_id + 1
  local widget = {
    id = next_id,
    spec = vim.deepcopy(spec),
    anchor = anchor.create(spec.anchor),
    assets = {},
    rendering = {},
    views = {},
    pending_views = {},
    desired = {},
    render_generation = 1,
    render_window_generations = {},
    style_keys = {},
    reconcile_token = 0,
    fallback_called = false,
    fallback_token = 0,
    hit_collision_warnings = {},
    placement_results = {},
  }
  widgets[widget.id] = widget
  index_widget(widget)
  if widget.anchor.kind == 'cursor' then
    cursor_widget_count = cursor_widget_count + 1
  end
  M.refresh()
  return widget.id
end

---@param id integer
---@param patch table
---@return boolean
function M.update(id, patch)
  local widget = widgets[id]
  if not widget or widget.deleting then
    return false
  end
  vim.validate('patch', patch, 'table')
  local next_spec = vim.tbl_deep_extend('force', widget.spec, vim.deepcopy(patch))
  -- Lists and callback-bearing specs are values, not mergeable configuration trees.
  for _, key in ipairs({ 'anchor', 'content', 'actions', 'region_actions', 'host' }) do
    if patch[key] ~= nil then
      next_spec[key] = vim.deepcopy(patch[key])
    end
  end
  local anchor_changed = patch.anchor ~= nil
    and not vim.deep_equal(widget.spec.anchor, next_spec.anchor)
  local content_changed = patch.content ~= nil
    and not vim.deep_equal(widget.spec.content, next_spec.content)
  local interactions_changed = (patch.actions ~= nil or patch.region_actions ~= nil)
    and (
      not vim.deep_equal(widget.spec.actions, next_spec.actions)
      or not vim.deep_equal(widget.spec.region_actions, next_spec.region_actions)
    )
  local next_anchor = anchor_changed and anchor.create(next_spec.anchor) or nil

  widget.reconcile_token = widget.reconcile_token + 1
  widget.desired = {}
  widget.fallback_called = false
  widget.fallback_token = widget.fallback_token + 1
  widget.spec = next_spec
  if anchor_changed then
    local previous_anchor = widget.anchor
    unindex_widget(widget)
    widget.anchor = next_anchor
    if previous_anchor.kind == 'cursor' then
      cursor_widget_count = cursor_widget_count - 1
    end
    if next_anchor.kind == 'cursor' then
      cursor_widget_count = cursor_widget_count + 1
    end
    anchor.delete(previous_anchor)
    index_widget(widget)
  end
  if content_changed then
    widget.render_generation = widget.render_generation + 1
    cancel_async(widget)
    widget.assets = {}
    widget.render_error = nil
    widget.style_keys = {}
    delete_views(widget)
    if widgets[id] ~= widget or widget.deleting then
      return false
    end
  elseif interactions_changed then
    for _, view in pairs(widget.views) do
      if not register_view(widget, view) then
        return false
      end
    end
  end
  M.refresh()
  return true
end

---@param id integer
---@return boolean
function M.delete(id)
  local widget = widgets[id]
  if not widget then
    return false
  end
  if widget.deleting then
    return true
  end
  widget.deleting = true
  cancel_async(widget)
  if not delete_views(widget) then
    widget.deleting = false
    return false
  end
  unindex_widget(widget)
  anchor.delete(widget.anchor)
  if widget.anchor.kind == 'cursor' then
    cursor_widget_count = cursor_widget_count - 1
  end
  widgets[id] = nil
  call_widget_callback(widget, 'on_delete', widget.id)
  return true
end

---@param filter? table|fun(widget: table): boolean
---@return integer
function M.clear(filter)
  local ids = {}
  for id, widget in pairs(widgets) do
    local matches = filter == nil
    if type(filter) == 'function' then
      matches = filter(widget)
    elseif type(filter) == 'table' then
      matches = (not filter.tag or widget.spec.tag == filter.tag)
        and (not filter.buffer or widget.anchor.buffer == filter.buffer)
    end
    if matches then
      ids[#ids + 1] = id
    end
  end
  local deleted = 0
  for _, id in ipairs(ids) do
    if M.delete(id) then
      deleted = deleted + 1
    end
  end
  return deleted
end

function M.invalidate_styles()
  renderer.rasterizer.clear()
  crop.clear()
  for _, widget in pairs(widgets) do
    widget.style_keys = {}
    invalidate_widget_assets(widget)
  end
  M.refresh()
end

---@param force_forget? boolean
---@return boolean
function M.reset_transport(force_forget)
  if type(backend.refresh_transport) == 'function' then
    backend_call('refresh_transport', { verify = true })
  end
  if force_forget and type(backend.forget) == 'function' then
    backend_call('forget')
    for _, widget in pairs(widgets) do
      cancel_async(widget)
      for _, view in pairs(widget.views) do
        unregister_view(view)
      end
      widget.views = {}
    end
    M.refresh()
    return true
  end
  for _, widget in pairs(widgets) do
    cancel_async(widget)
    delete_views(widget)
  end
  if type(backend.clear) == 'function' then
    local cleared = backend_call('clear')
    if not cleared then
      sanitize_backend_views()
      M.refresh()
      return false
    end
  end
  for _, widget in pairs(widgets) do
    for _, view in pairs(widget.views) do
      unregister_view(view)
    end
    widget.views = {}
  end
  M.refresh()
  return true
end

---@param name string
---@param callback fun()
---@return fun()
function M.subscribe_redraw(name, callback)
  vim.validate({
    name = { name, 'string' },
    callback = { callback, 'function' },
  })
  redraw_observers[name] = callback
  return function()
    if redraw_observers[name] == callback then
      redraw_observers[name] = nil
    end
  end
end

---@param id integer
---@return table?
function M.get(id)
  return widgets[id]
end

---@return table<integer, table>
function M.all()
  return widgets
end

function M._redraw_observers()
  return redraw_observers
end

---@param row integer
---@param col integer
---@return table?
function M.hit_test(row, col)
  local target = M._hit_target(row, col)
  if target then
    return target.widget
  end
  local hit
  local hit_z = -math.huge
  for _, widget in pairs(widgets) do
    for _, view in pairs(widget.views) do
      local rect = view.rect
      local zindex = view.opts.zindex or 0
      if
        row >= rect.top
        and row <= rect.bottom
        and col >= rect.left
        and col <= rect.right
        and zindex >= hit_z
      then
        hit = widget
        hit_z = zindex
      end
    end
  end
  return hit
end

local function target_better(candidate, current)
  if not current then
    return true
  end
  if candidate.zindex ~= current.zindex then
    return candidate.zindex > current.zindex
  end
  if candidate.creation_order ~= current.creation_order then
    return candidate.creation_order > current.creation_order
  end
  return candidate.paint_order >= current.paint_order
end

---@param row integer
---@param col integer
---@return table?
function M._hit_target(row, col)
  local hit
  local candidates = hit_rows[row] or {}
  hit_counts.queries = hit_counts.queries + 1
  hit_counts.candidates = hit_counts.candidates + #candidates
  hit_counts.max_candidates = math.max(hit_counts.max_candidates, #candidates)
  for _, target in ipairs(candidates) do
    if col >= target.rect.left and col <= target.rect.right and target_better(target, hit) then
      hit = target
    end
  end
  return hit
end

---@param row integer
---@param col integer
---@return table?
function M.hit_target(row, col)
  local hit = M._hit_target(row, col)
  if not hit then
    return nil
  end
  return {
    widget_id = hit.widget_id,
    surface_id = hit.surface_id,
    node_id = hit.node_id,
    win = hit.win,
    rect = vim.deepcopy(hit.rect),
    local_cell = {
      row = hit.view.crop.top + row - hit.view.rect.top,
      col = hit.view.crop.left + col - hit.view.rect.left,
    },
  }
end

dispatch_target = function(target, action, mouse, source)
  if not target then
    return false
  end
  local widget = target.widget
  if not widget or widgets[widget.id] ~= widget or (widget.deleting and action ~= 'leave') then
    return false
  end
  local region_actions = target.region_actions or widget.spec.region_actions
  local callback = region_callback(widget, target.node_id, action, region_actions)
  local regional = type(callback) == 'function'
  local entry = target.node_id and region_actions and region_actions[target.node_id] or nil
  local consume = type(entry) ~= 'table' or entry.consume ~= false
  callback = callback or (widget.spec.actions and widget.spec.actions[action])
  if type(callback) ~= 'function' then
    return false
  end
  local context = {
    action = action,
    source = source or 'mouse',
    widget_id = widget.id,
    surface_id = widget.spec.surface_id,
    node_id = target.node_id,
    win = target.win,
    host = widget.spec.host,
    mouse = mouse,
    local_cell = target.local_cell,
    rect = vim.deepcopy(target.rect),
  }
  local row = mouse and (mouse.screenrow or mouse.row)
  local col = mouse and (mouse.screencol or mouse.column or mouse.col)
  if target.view and row and col then
    context.local_cell = {
      row = target.view.crop.top + row - target.view.rect.top,
      col = target.view.crop.left + col - target.view.rect.left,
    }
  end
  local ok, err
  if regional then
    ok, err = pcall(callback, context)
  else
    ok, err = pcall(callback, widget.id, mouse, context)
  end
  if not ok then
    log.error(('widget %d %s action failed: %s'):format(widget.id, action, err), true)
  end
  return not regional or action ~= 'click' or source ~= 'mouse' or consume
end

---@param action string
---@param mouse? table
---@return boolean
function M.dispatch(action, mouse)
  mouse = mouse or vim.fn.getmousepos()
  local row = mouse.screenrow or mouse.row
  local col = mouse.screencol or mouse.column or mouse.col
  if not row or not col then
    return false
  end
  return dispatch_target(M._hit_target(row, col), action, mouse, 'mouse')
end

---@param mouse? table
---@return boolean
function M.dispatch_hover(mouse)
  mouse = mouse or vim.fn.getmousepos()
  local row = mouse.screenrow or mouse.row
  local col = mouse.screencol or mouse.column or mouse.col
  local target = row and col and M._hit_target(row, col) or nil
  local previous = hover_target
  if previous ~= target then
    hover_target = target
    dispatch_target(previous, 'leave', mouse, 'mouse')
    if hover_target == target then
      dispatch_target(target, 'enter', mouse, 'mouse')
    end
  end
  target = hover_target
  return dispatch_target(target, 'hover', mouse, 'mouse') or target ~= nil
end

---@param widget_id integer
---@param node_id string
---@param action? string
---@param region_actions? table<string, function|table>
---@return boolean
function M.dispatch_node(widget_id, node_id, action, region_actions)
  local widget = widgets[widget_id]
  if not widget or widget.deleting then
    return false
  end
  local current_win = vim.api.nvim_get_current_win()
  local views = vim.tbl_values(widget.views)
  table.sort(views, function(first, second)
    if (first.win == current_win) ~= (second.win == current_win) then
      return first.win == current_win
    end
    if first.win ~= second.win then
      return first.win < second.win
    end
    return first.key < second.key
  end)
  for _, view in ipairs(views) do
    for _, target in ipairs(view.hit_targets or {}) do
      if target.node_id == node_id then
        target = vim.tbl_extend('force', {}, target, { region_actions = region_actions })
        return dispatch_target(target, action or 'activate', nil, 'keyboard')
      end
    end
    for _, region in ipairs(view.manifest and view.manifest.regions or {}) do
      if region.id == node_id then
        local rect = interaction_geometry.project(region, view)
        if rect then
          return dispatch_target({
            widget = widget,
            widget_id = widget.id,
            surface_id = widget.spec.surface_id,
            node_id = node_id,
            win = view.win,
            view = view,
            rect = rect,
            region = region,
            region_actions = region_actions,
          }, action or 'activate', nil, 'keyboard')
        end
      end
    end
  end
  local selected_view = views[1]
  local target = {
    widget = widget,
    widget_id = widget.id,
    surface_id = widget.spec.surface_id,
    node_id = node_id,
    win = selected_view and selected_view.win
      or (widget.spec.host and (widget.spec.host.window or widget.spec.host.win)),
    view = selected_view,
    rect = selected_view and vim.deepcopy(selected_view.rect) or {},
    region_actions = region_actions,
  }
  return dispatch_target(target, action or 'activate', nil, 'keyboard')
end

---@param directory string
---@return string[]
function M.export(directory)
  directory = fs.ensure_dir(directory)
  local exported = {}
  local seen = {}
  local function export_asset(asset, base)
    if not asset or seen[asset.key] then
      return
    end
    seen[asset.key] = true
    local png = vim.fs.joinpath(directory, base .. '.png')
    if asset.path then
      local ok = vim.uv.fs_copyfile(asset.path, png)
      if ok then
        exported[#exported + 1] = png
      end
    elseif asset.bytes then
      fs.write_binary(png, asset.bytes)
      exported[#exported + 1] = png
    end
    if asset.svg_path then
      local target = vim.fs.joinpath(directory, base .. '.svg')
      if vim.uv.fs_copyfile(asset.svg_path, target) then
        exported[#exported + 1] = target
      end
    end
  end
  for id, widget in pairs(widgets) do
    for win, asset in pairs(widget.assets) do
      export_asset(asset, ('widget-%d-source-win-%s-%s'):format(id, win, asset.key:sub(1, 10)))
    end
    for _, view in pairs(widget.views) do
      local view_key = view.key:gsub(':', '-')
      export_asset(
        view.asset,
        ('widget-%d-view-%s-%s'):format(id, view_key, view.asset.key:sub(1, 10))
      )
    end
  end
  return exported
end

---@return table
function M.inspect()
  local backend_available, backend_reason = backend_call('available')
  local transport = type(backend.stats) == 'function' and backend_call('stats') or nil
  local result = {
    enabled = enabled,
    backend = { available = backend_available == true, reason = backend_reason },
    widgets = {},
    renderer = renderer.rasterizer.stats(),
    crop = crop.stats(),
    jobs = require('imageui.renderer.jobs').stats(),
    performance = {
      reconciles = reconcile_count,
      cursor_widgets = cursor_widget_count,
      backend = vim.deepcopy(backend_counts),
      transport = transport,
      reconcile_ms = reconcile_timing(),
      scheduler = scheduler and scheduler:stats() or nil,
      redraw = vim.deepcopy(redraw_counts),
      interactions = vim.deepcopy(hit_counts),
    },
    log = log.history(),
  }
  for id, widget in pairs(widgets) do
    local placements = {}
    local hitboxes = {}
    for _, view in pairs(widget.views) do
      placements[#placements + 1] = {
        win = view.win,
        rect = vim.deepcopy(view.rect),
        opts = vim.deepcopy(view.opts),
        asset = view.asset_key,
      }
      for _, target in ipairs(view.hit_targets or {}) do
        hitboxes[#hitboxes + 1] = {
          node_id = target.node_id,
          win = target.win,
          rect = vim.deepcopy(target.rect),
          focusable = target.region and target.region.focusable or false,
        }
      end
    end
    result.widgets[id] = {
      tag = widget.spec.tag,
      anchor = vim.deepcopy(widget.anchor),
      views = vim.tbl_count(widget.views),
      assets = vim.tbl_count(widget.assets),
      rendering = vim.tbl_count(widget.rendering),
      placements = placements,
      style_keys = vim.deepcopy(widget.style_keys),
      error = widget.render_error,
      hitboxes = hitboxes,
      surface_id = widget.spec.surface_id,
      placement_results = vim.deepcopy(widget.placement_results),
    }
  end
  return result
end

return M
