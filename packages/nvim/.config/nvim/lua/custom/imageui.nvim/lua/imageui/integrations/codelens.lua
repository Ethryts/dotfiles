local manager = require('imageui.manager')
local placement = require('imageui.placement')
local right_channel = require('imageui.integrations.codelens_right')
local scheduler_module = require('imageui.util.scheduler')

local M = {}

local METHOD = 'textDocument/codeLens'
local RESOLVE_METHOD = 'codeLens/resolve'
local fallback_ns = vim.api.nvim_create_namespace('imageui.nvim:codelens:fallback')

local config
local root_config
local states = {}
local augroup
local enabled = false
local previous_refresh_handler
local refresh_handler
local unsubscribe_redraw
local relayout_scheduler
local original_api
local facade_api
local global_override
local global_client_overrides = {}
local buffer_overrides = {}

---@param bufnr? integer
---@return integer
local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

---@param name string
---@param ... any
---@return boolean, any
local function call_original(name, ...)
  local callback = original_api and original_api[name]
  if type(callback) ~= 'function' then
    return false, nil
  end
  return pcall(callback, ...)
end

---@param bufnr integer
---@return table
local function state_for(bufnr)
  local state = states[bufnr]
  if state then
    return state
  end
  state = {
    bufnr = bufnr,
    generation = 0,
    widgets = {},
    fallbacks = {},
    fallback_modes = {},
    errors = {},
    entries = {},
    results = {},
    sorted_rows = {},
    builtin_was_enabled = true,
    restore_builtin = true,
    restore_clients = {},
    client_gates = {},
    builtin_checked = false,
  }
  state.scheduler = scheduler_module.new(config.debounce, function()
    M.refresh(bufnr)
  end)
  states[bufnr] = state
  return state
end

---@param bufnr integer
---@param client_id? integer
---@return boolean
local function public_enabled(bufnr, client_id)
  bufnr = normalize_bufnr(bufnr)
  local state = states[bufnr]
  local ok, original_value = call_original('is_enabled', { bufnr = bufnr, client_id = client_id })
  local base_buffer = state and state.builtin_checked and state.restore_builtin
    or (ok and original_value or true)
  local buffer_value = buffer_overrides[bufnr]
  if buffer_value == nil then
    buffer_value = global_override
  end
  if buffer_value == nil then
    buffer_value = base_buffer
  end
  if not client_id then
    return buffer_value
  end
  local client_value = global_client_overrides[client_id]
  if client_value == nil then
    client_value = global_override
  end
  if client_value == nil then
    local client_ok, original_client = call_original('is_enabled', { client_id = client_id })
    client_value = state and state.builtin_checked and state.client_gates[client_id]
      or (client_ok and original_client or true)
  end
  return buffer_value and client_value
end

---@param bufnr integer
local function disable_builtin(bufnr)
  if not original_api then
    return
  end
  local state = state_for(bufnr)
  if state.builtin_checked then
    return
  end
  local ok, was_enabled = call_original('is_enabled', { bufnr = bufnr })
  state.builtin_was_enabled = ok and was_enabled or true
  state.restore_builtin = public_enabled(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local client_ok, client_enabled =
      call_original('is_enabled', { bufnr = bufnr, client_id = client.id })
    if client_ok then
      state.restore_clients[client.id] = client_enabled
    end
    local gate_ok, gate = call_original('is_enabled', { client_id = client.id })
    if gate_ok then
      state.client_gates[client.id] = gate
    end
  end
  state.builtin_checked = true
  call_original('enable', false, { bufnr = bufnr })
end

---@param bufnr integer
---@param row integer
local function clear_fallback(bufnr, row)
  local state = states[bufnr]
  local id = state and state.fallbacks[row]
  if vim.api.nvim_buf_is_valid(bufnr) then
    if id then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, fallback_ns, id)
    end
  end
  if state then
    state.fallbacks[row] = nil
    state.fallback_modes[row] = nil
  end
  right_channel.redraw(bufnr)
end

---@param bufnr integer
---@param row integer
---@param spans table[]
---@param mode? 'right'|'native'
local function show_fallback(bufnr, row, spans, mode)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  mode = mode or (config.fallback == 'virtual_text' and 'right' or nil)
  if not mode then
    return
  end
  clear_fallback(bufnr, row)
  local state = states[bufnr]
  if mode == 'right' then
    if state then
      state.fallback_modes[row] = mode
    end
    right_channel.redraw(bufnr)
    return
  end
  local chunks = {}
  for _, span in ipairs(spans) do
    chunks[#chunks + 1] = { span.text, span.highlight or config.highlight }
  end
  local opts = {
    hl_mode = 'combine',
    priority = 90,
  }
  opts.virt_lines = { chunks }
  opts.virt_lines_above = true
  opts.virt_lines_overflow = 'scroll'
  local id = vim.api.nvim_buf_set_extmark(bufnr, fallback_ns, row, 0, opts)
  if state then
    state.fallbacks[row] = id
    state.fallback_modes[row] = mode
  end
end

---@param bufnr integer
---@param row integer
---@return boolean
local function has_native_fallback_at(bufnr, row)
  local state = states[bufnr]
  for original_row, id in pairs(state and state.fallbacks or {}) do
    if state.fallback_modes[original_row] == 'native' then
      local ok, position = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, fallback_ns, id, {})
      if ok and position and position[1] == row then
        return true
      end
    end
  end
  return false
end

---@param entry table
---@param bufnr integer
---@param client_id? integer
local function execute_entry(entry, bufnr, client_id)
  local candidates = {}
  for _, item in ipairs(entry.items) do
    if item.lens.command and (not client_id or item.client_id == client_id) then
      candidates[#candidates + 1] = item
    end
  end
  local function execute(item)
    local client = item and vim.lsp.get_client_by_id(item.client_id)
    if client and item.lens.command then
      client:exec_cmd(item.lens.command, { bufnr = bufnr })
    end
  end
  if #candidates == 1 then
    execute(candidates[1])
  elseif #candidates > 1 then
    vim.ui.select(candidates, {
      prompt = 'Code lenses:',
      kind = 'codelens',
      format_item = function(item)
        local client = vim.lsp.get_client_by_id(item.client_id)
        return ('%s [%s]'):format(item.lens.command.title, client and client.name or item.client_id)
      end,
    }, execute)
  end
end

---@param bufnr integer
---@param item table
---@return integer
local function byte_col(bufnr, item)
  local row = item.lens.range.start.line
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local client = vim.lsp.get_client_by_id(item.client_id)
  local encoding = client and client.offset_encoding or 'utf-16'
  local ok, col = pcall(vim.str_byteindex, line, encoding, item.lens.range.start.character, false)
  return ok and col or 0
end

---@param bufnr integer
---@param row integer
---@return boolean
local function has_blank_line_above(bufnr, row)
  if row <= 0 then
    return false
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  return line ~= nil and line:match('^%s*$') ~= nil
end

---@param spans table[]
---@return integer
local function span_width(spans)
  local width = 0
  for _, span in ipairs(spans) do
    width = width + vim.fn.strdisplaywidth(span.text)
  end
  return math.max(1, math.ceil(width * config.font_scale) + 1)
end

---@param bufnr integer
---@param entry table
---@return boolean clear
---@return boolean geometry_viable
---@return table details
local function cells_above_are_clear(bufnr, entry)
  local details = { windows = {} }
  if entry.row <= 0 then
    details.reason = 'first_buffer_line'
    return false, false, details
  end
  local self_native = has_native_fallback_at(bufnr, entry.row)
  local found_window = false
  local all_clear = true
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win) then
      local pos = vim.fn.screenpos(win, entry.row + 1, entry.col + 1)
      local bounds = placement.window_rect(win)
      -- A native fallback inserts one screen row immediately before the
      -- function. Project through it instead of removing it for measurement;
      -- removing it during redraw makes the layout oscillate.
      local native_rows = self_native and 1 or 0
      local row = pos.row + config.offset_row - 1 - native_rows
      local col = pos.col + config.offset_col
      local window = {
        anchor = { row = pos.row, col = pos.col },
        target = { row = row, col = col, width = entry.width, height = 1 },
        bounds = bounds and vim.deepcopy(bounds) or nil,
        ignored_native_rows = native_rows,
      }
      details.windows[win] = window
      if pos.row > 0 and bounds then
        if
          row < bounds.top
          or row > bounds.bottom
          or col > bounds.right
          or col + entry.width - 1 < bounds.left
        then
          window.reason = 'outside_window'
        else
          local scan_left = math.max(col, bounds.left)
          local scan_right = math.min(col + entry.width - 1, bounds.right)
          if
            root_config.placement.partial == 'hide'
            and (scan_left ~= col or scan_right ~= col + entry.width - 1)
          then
            window.reason = 'partial_hidden'
          else
            found_window = true
            for screen_col = scan_left, scan_right do
              local cell = vim.fn.screenstring(row, screen_col)
              if cell ~= '' and cell:match('%S') then
                window.reason = 'occupied'
                window.occupied = { row = row, col = screen_col, text = cell }
                all_clear = false
                break
              end
            end
            if not window.occupied then
              window.reason = scan_right < col + entry.width - 1 and 'clear_clipped' or 'clear'
            end
          end
        end
      elseif pos.row == 0 then
        window.reason = 'anchor_not_visible'
      else
        window.reason = 'window_bounds_unavailable'
      end
    end
  end
  if not found_window then
    details.reason = 'no_visible_window'
  elseif not all_clear then
    details.reason = 'occupied'
  end
  details.geometry_viable = found_window
  details.clear = found_window and all_clear
  return details.clear, found_window, details
end

---@return string[]
local function placement_order()
  if config.placement_order then
    return config.placement_order
  end
  if config.layout == 'overlay' then
    return { 'overlay', 'right' }
  elseif config.layout == 'blank_line' then
    return { 'above_blank', 'right' }
  end
  return { 'above_blank', 'above_clear', 'overlay', 'right', 'native' }
end

---@param current string
---@return 'right'|'native'|'hide'
local function failure_mode(current)
  local found = false
  for _, mode in ipairs(placement_order()) do
    if found and (mode == 'right' or mode == 'native' or mode == 'hide') then
      return mode
    end
    if mode == current then
      found = true
    end
  end

  -- `fallback` predates placement_order. An explicit order is authoritative;
  -- compatibility behavior only applies to the legacy layout setting.
  if not config.placement_order and config.fallback == 'virtual_text' then
    return 'right'
  end
  return 'hide'
end

---@param bufnr integer
---@param entry table
---@param err? string
local function show_failure_fallback(bufnr, entry, err)
  local mode = failure_mode(entry.mode)
  if mode == 'hide' then
    clear_fallback(bufnr, entry.row)
  else
    show_fallback(bufnr, entry.row, entry.spans, mode)
  end
  local state = states[bufnr]
  if state then
    state.errors[entry.row] = err
    state.last_error = err
  end
end

---@param bufnr integer
---@param entry table
---@return string, table
local function choose_mode(bufnr, entry)
  local blank = has_blank_line_above(bufnr, entry.row)
  local clear, geometry_viable, fit = cells_above_are_clear(bufnr, entry)
  local attempts = {
    -- A blank buffer row is intentionally available even when 'listchars',
    -- indent guides, or other visual-only decorations draw glyphs on it.
    above_blank = { viable = blank and geometry_viable, blank = blank, fit = fit },
    above_clear = { viable = clear, fit = fit },
  }
  for _, mode in ipairs(placement_order()) do
    if mode == 'above_blank' and attempts.above_blank.viable then
      return mode, attempts
    elseif mode == 'above_clear' and attempts.above_clear.viable then
      return mode, attempts
    elseif mode == 'overlay' or mode == 'right' or mode == 'native' or mode == 'hide' then
      attempts[mode] = { viable = true }
      return mode, attempts
    end
  end
  return 'hide', attempts
end

---@param bufnr integer
---@param results table[]
local function apply(bufnr, results)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local state = state_for(bufnr)
  state.results = results

  local grouped = {}
  for _, item in ipairs(results) do
    if item.lens.command and item.lens.command.title then
      local row = item.lens.range.start.line
      grouped[row] = grouped[row] or { row = row, items = {} }
      grouped[row].items[#grouped[row].items + 1] = item
    end
  end

  for _, entry in pairs(grouped) do
    table.sort(entry.items, function(a, b)
      return a.lens.range.start.character < b.lens.range.start.character
    end)
    entry.col = byte_col(bufnr, entry.items[1])

    local spans = {}
    for index, item in ipairs(entry.items) do
      if index > 1 then
        spans[#spans + 1] = { text = config.separator, highlight = config.separator_highlight }
      end
      spans[#spans + 1] = { text = item.lens.command.title, highlight = config.highlight }
    end
    entry.spans = spans
    entry.width = span_width(spans)
    entry.mode, entry.attempts = choose_mode(bufnr, entry)
    entry.display_row = (entry.mode == 'above_blank' or entry.mode == 'above_clear')
        and entry.row - 1
      or entry.row

    if entry.mode == 'right' or entry.mode == 'native' then
      state.errors[entry.row] = nil
      local existing = state.widgets[entry.row]
      if existing then
        if manager.delete(existing) then
          state.widgets[entry.row] = nil
        end
      end
      show_fallback(bufnr, entry.row, spans, entry.mode)
    elseif entry.mode == 'hide' then
      state.errors[entry.row] = nil
      local existing = state.widgets[entry.row]
      if existing then
        if manager.delete(existing) then
          state.widgets[entry.row] = nil
        end
      end
      clear_fallback(bufnr, entry.row)
    else
      local above = entry.mode == 'above_blank' or entry.mode == 'above_clear'
      local widget_spec = {
        tag = 'codelens',
        anchor = { kind = 'buffer', buffer = bufnr, row = entry.row, col = entry.col },
        offset_row = config.offset_row + (above and -1 or 0),
        offset_col = config.offset_col,
        content = {
          kind = 'text',
          spans = spans,
          highlight = config.highlight,
          font_scale = config.font_scale,
          position = above and 'bottom' or config.position,
          height_cells = 1,
          padding = { left = 0, right = 1, top = 0, bottom = 0 },
        },
        actions = {
          click = function()
            execute_entry(entry, bufnr)
          end,
        },
        fallback = function(_, err)
          show_failure_fallback(bufnr, entry, err)
        end,
        on_show = function()
          clear_fallback(bufnr, entry.row)
          state.errors[entry.row] = nil
          state.last_error = nil
        end,
      }

      clear_fallback(bufnr, entry.row)
      local existing = state.widgets[entry.row]
      if existing then
        manager.update(existing, widget_spec)
      else
        state.widgets[entry.row] = manager.create(widget_spec)
      end
    end
  end

  state.entries = grouped
  state.sorted_rows = vim.tbl_keys(grouped)
  table.sort(state.sorted_rows)
  local obsolete = {}
  for row, id in pairs(state.widgets) do
    local entry = grouped[row]
    if not entry or entry.mode == 'right' or entry.mode == 'native' or entry.mode == 'hide' then
      obsolete[#obsolete + 1] = { row = row, id = id }
    end
  end
  for _, item in ipairs(obsolete) do
    if manager.delete(item.id) then
      state.widgets[item.row] = nil
    end
  end
  local stale_fallbacks = {}
  for row in pairs(state.fallback_modes) do
    local entry = grouped[row]
    if not entry or (entry.mode ~= 'right' and entry.mode ~= 'native') then
      stale_fallbacks[#stale_fallbacks + 1] = row
    end
  end
  for _, row in ipairs(stale_fallbacks) do
    clear_fallback(bufnr, row)
  end
  for row in pairs(state.errors) do
    if not grouped[row] then
      state.errors[row] = nil
    end
  end
  right_channel.redraw(bufnr)
end

local function relayout()
  for bufnr, state in pairs(states) do
    if vim.api.nvim_buf_is_valid(bufnr) and public_enabled(bufnr) then
      local visible_rows = {}
      for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        if vim.api.nvim_win_is_valid(win) then
          local info = vim.fn.getwininfo(win)[1] or {}
          local rows = state.sorted_rows or {}
          local top_line = math.max(1, (info.topline or 1) - 1)
          local bottom_line = math.max(top_line, info.botline or top_line) + 1
          for _, interval in ipairs(manager._visible_line_intervals(win, top_line, bottom_line)) do
            local top = interval[1] - 1
            local bottom = interval[2] - 1
            local low = 1
            local high = #rows
            while low <= high do
              local mid = math.floor((low + high) / 2)
              if rows[mid] < top then
                low = mid + 1
              else
                high = mid - 1
              end
            end
            for index = low, #rows do
              local row = rows[index]
              if row > bottom then
                break
              end
              visible_rows[row] = true
            end
          end
        end
      end
      for row in pairs(visible_rows) do
        local entry = state.entries[row]
        if entry then
          local runtime_fallback = state.fallback_modes[entry.row]
          local next_mode, attempts = choose_mode(bufnr, entry)
          local anchor_visible = false
          local fit = attempts.above_blank and attempts.above_blank.fit
          for _, window in pairs(fit and fit.windows or {}) do
            if window.anchor and window.anchor.row > 0 then
              anchor_visible = true
              break
            end
          end
          -- Offscreen entries cannot be collision-tested. Keep their current
          -- mode and rendered asset so scrolling does not tear down/rebuild a
          -- CodeLens merely because its anchor left the viewport.
          if
            anchor_visible
            and not (runtime_fallback and state.errors[entry.row])
            and next_mode ~= entry.mode
          then
            apply(bufnr, state.results)
            break
          end
        end
      end
    end
  end
end

---@param bufnr integer
local function clear_display(bufnr)
  local state = states[bufnr]
  if not state then
    return
  end
  state.generation = state.generation + 1
  local remaining = {}
  for row, id in pairs(state.widgets) do
    if not manager.delete(id) then
      remaining[row] = id
    end
  end
  state.widgets = remaining
  state.fallbacks = {}
  state.fallback_modes = {}
  state.errors = {}
  state.entries = {}
  state.results = {}
  state.sorted_rows = {}
  state.right_windows = {}
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, fallback_ns, 0, -1)
  end
  right_channel.redraw(bufnr)
end

---@param bufnr integer
local function clear_buffer(bufnr)
  local state = states[bufnr]
  if not state then
    return
  end
  clear_display(bufnr)
  state.scheduler:close()
  if vim.api.nvim_buf_is_valid(bufnr) and state.builtin_checked then
    call_original('enable', state.restore_builtin, { bufnr = bufnr })
    for client_id, value in pairs(state.restore_clients) do
      if value ~= state.restore_builtin then
        call_original('enable', value, { bufnr = bufnr, client_id = client_id })
      end
    end
  end
  states[bufnr] = nil
end

---@param bufnr? integer
function M.schedule(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if not enabled or not vim.api.nvim_buf_is_valid(bufnr) or not public_enabled(bufnr) then
    return
  end
  state_for(bufnr).scheduler:schedule()
end

---@param bufnr? integer
function M.refresh(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if
    not enabled
    or not vim.api.nvim_buf_is_valid(bufnr)
    or not vim.api.nvim_buf_is_loaded(bufnr)
  then
    return
  end
  if not public_enabled(bufnr) then
    clear_display(bufnr)
    return
  end
  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if public_enabled(bufnr, client.id) and client:supports_method(METHOD, bufnr) then
      clients[#clients + 1] = client
    end
  end
  if #clients == 0 then
    local state = states[bufnr]
    if state then
      apply(bufnr, {})
    end
    return
  end

  disable_builtin(bufnr)
  local state = state_for(bufnr)
  state.generation = state.generation + 1
  local generation = state.generation
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local pending = #clients
  local all_results = {}

  local function finish_one()
    pending = pending - 1
    if pending ~= 0 then
      return
    end
    local current = states[bufnr]
    if
      current
      and current.generation == generation
      and vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_get_changedtick(bufnr) == changedtick
    then
      apply(bufnr, all_results)
    end
  end

  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  for _, client in ipairs(clients) do
    local request_client = client
    local request_ok = request_client:request(METHOD, params, function(err, result)
      local current = states[bufnr]
      if err or not current or current.generation ~= generation then
        finish_one()
        return
      end

      local unresolved = 0
      local client_results = {}
      local function finish_client()
        if unresolved ~= 0 then
          return
        end
        vim.list_extend(all_results, client_results)
        finish_one()
      end

      for _, lens in ipairs(result or {}) do
        if lens.command then
          client_results[#client_results + 1] = { client_id = request_client.id, lens = lens }
        elseif request_client:supports_method(RESOLVE_METHOD, bufnr) then
          unresolved = unresolved + 1
          local resolve_ok = request_client:request(
            RESOLVE_METHOD,
            lens,
            function(resolve_err, resolved)
              if not resolve_err and resolved and resolved.command then
                client_results[#client_results + 1] =
                  { client_id = request_client.id, lens = resolved }
              end
              unresolved = unresolved - 1
              finish_client()
            end,
            bufnr
          )
          if not resolve_ok then
            unresolved = unresolved - 1
          end
        end
      end
      finish_client()
    end, bufnr)
    if not request_ok then
      finish_one()
    end
  end
end

---@param opts? table
function M.run(opts)
  opts = opts or {}
  local bufnr = normalize_bufnr(opts.bufnr)
  local state = states[bufnr]
  local row = opts.row
  if row == nil then
    row = vim.api.nvim_win_get_cursor(0)[1] - 1
  end
  local entry = state and state.entries[row]
  if not entry and state then
    for _, candidate in pairs(state.entries) do
      if candidate.display_row == row then
        entry = candidate
        break
      end
    end
  end
  if entry then
    execute_entry(entry, bufnr, opts.client_id)
    return
  end
  vim.notify('No code lenses found on the current line', vim.log.levels.INFO)
end

---@param filter? table|integer
---@return table[]
function M.get(filter)
  local deprecated_number = type(filter) == 'number'
  local opts = deprecated_number and { bufnr = filter } or (filter or {})
  local bufnr = normalize_bufnr(opts.bufnr)
  local state = states[bufnr]
  local result = {}
  for _, item in ipairs(state and state.results or {}) do
    if not opts.client_id or item.client_id == opts.client_id then
      result[#result + 1] = deprecated_number and item.lens or item
    end
  end
  return result
end

---@param value? boolean
---@param filter? table
local function public_enable(value, filter)
  if not enabled then
    local _, result = call_original('enable', value, filter)
    return result
  end
  value = value == nil or value
  filter = filter or {}
  local bufnr = filter.bufnr and normalize_bufnr(filter.bufnr) or nil
  if filter.client_id then
    global_client_overrides[filter.client_id] = value
  elseif bufnr then
    buffer_overrides[bufnr] = value
  else
    global_override = value
    for target, override in pairs(buffer_overrides) do
      if override == value then
        buffer_overrides[target] = nil
      end
    end
    for client_id, override in pairs(global_client_overrides) do
      if override == value then
        global_client_overrides[client_id] = nil
      end
    end
  end

  local targets
  if filter.client_id then
    local client = vim.lsp.get_client_by_id(filter.client_id)
    targets = client and vim.tbl_keys(client.attached_buffers or {}) or (bufnr and { bufnr } or {})
  else
    targets = bufnr and { bufnr } or vim.api.nvim_list_bufs()
  end
  for _, target in ipairs(targets) do
    local state = states[target]
    if state then
      if filter.client_id then
        state.restore_clients[filter.client_id] = value
      else
        state.restore_builtin = public_enabled(target)
      end
    end
    call_original('enable', false, { bufnr = target })
    if public_enabled(target) then
      M.schedule(target)
    else
      clear_display(target)
    end
  end
end

---@param filter? table
---@return boolean
local function public_is_enabled(filter)
  if not enabled then
    local ok, result = call_original('is_enabled', filter)
    return ok and result or false
  end
  filter = filter or {}
  return public_enabled(normalize_bufnr(filter.bufnr), filter.client_id)
end

local function install_facade()
  if not vim.lsp.codelens then
    return
  end
  if not original_api then
    original_api = {}
    facade_api = {}
    for _, name in ipairs({ 'enable', 'is_enabled', 'get', 'run', 'refresh' }) do
      original_api[name] = vim.lsp.codelens[name]
    end
    facade_api.enable = public_enable
    facade_api.is_enabled = public_is_enabled
    facade_api.get = function(filter)
      if not enabled then
        local _, result = call_original('get', filter)
        return result
      end
      return M.get(filter)
    end
    facade_api.run = function(opts)
      if not enabled then
        local _, result = call_original('run', opts)
        return result
      end
      return M.run(opts)
    end
    facade_api.refresh = function(opts)
      if not enabled then
        local _, result = call_original('refresh', opts)
        return result
      end
      local bufnr = opts and opts.bufnr
      public_enable(true, { bufnr = bufnr })
      return M.refresh(bufnr)
    end
  end
  for name, callback in pairs(facade_api) do
    if original_api[name] and vim.lsp.codelens[name] == original_api[name] then
      vim.lsp.codelens[name] = callback
    end
  end
end

local function uninstall_facade()
  if not original_api or not vim.lsp.codelens then
    return
  end
  for name, callback in pairs(facade_api) do
    if vim.lsp.codelens[name] == callback then
      vim.lsp.codelens[name] = original_api[name]
    end
  end
end

---@param opts table
function M.setup(opts)
  root_config = opts
  config = opts.integrations.codelens
end

function M.enable()
  if enabled then
    return
  end
  enabled = true
  install_facade()
  right_channel.enable({
    states = function()
      return states
    end,
    config = function()
      return config.right
    end,
  })
  relayout_scheduler = scheduler_module.new(config.relayout_debounce, relayout)
  unsubscribe_redraw = manager.subscribe_redraw('codelens', function()
    relayout_scheduler:schedule()
  end)
  local prior_refresh_handler = vim.lsp.handlers['workspace/codeLens/refresh']
  previous_refresh_handler = prior_refresh_handler
  refresh_handler = function(err, result, ctx, handler_config)
    local client = ctx and vim.lsp.get_client_by_id(ctx.client_id)
    if client then
      for bufnr in pairs(client.attached_buffers or {}) do
        M.schedule(bufnr)
      end
    end
    if prior_refresh_handler then
      return prior_refresh_handler(err, result, ctx, handler_config)
    end
    return vim.NIL
  end
  vim.lsp.handlers['workspace/codeLens/refresh'] = refresh_handler
  augroup = vim.api.nvim_create_augroup('ImageUICodeLens', { clear = true })
  vim.api.nvim_create_autocmd(config.refresh, {
    group = augroup,
    callback = function(event)
      M.schedule(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd('LspDetach', {
    group = augroup,
    callback = function(event)
      M.schedule(event.buf)
    end,
  })
  if config.refresh_on_change then
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP', 'InsertLeave' }, {
      group = augroup,
      callback = function(event)
        M.schedule(event.buf)
      end,
    })
  end
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    callback = function(event)
      clear_buffer(event.buf)
    end,
  })
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.schedule(bufnr)
    end
  end
end

function M.disable()
  enabled = false
  right_channel.disable()
  if relayout_scheduler then
    relayout_scheduler:close()
    relayout_scheduler = nil
  end
  if unsubscribe_redraw then
    unsubscribe_redraw()
    unsubscribe_redraw = nil
  end
  if refresh_handler and vim.lsp.handlers['workspace/codeLens/refresh'] == refresh_handler then
    vim.lsp.handlers['workspace/codeLens/refresh'] = previous_refresh_handler
  end
  refresh_handler = nil
  previous_refresh_handler = nil
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  local buffers = vim.tbl_keys(states)
  for _, bufnr in ipairs(buffers) do
    clear_buffer(bufnr)
  end
  uninstall_facade()
  global_override = nil
  global_client_overrides = {}
  buffer_overrides = {}
end

---@return boolean
function M.is_enabled()
  return enabled
end

---@param filter? table
---@return boolean
function M.is_visible(filter)
  return public_is_enabled(filter)
end

---@return table
function M.inspect()
  local result = {
    enabled = enabled,
    right = config and vim.deepcopy(config.right) or nil,
    buffers = {},
  }
  for bufnr, state in pairs(states) do
    local placements = {}
    local attempts = {}
    local fallbacks = {}
    for row, entry in pairs(state.entries) do
      placements[row] = entry.mode
      attempts[row] = vim.deepcopy(entry.attempts)
    end
    for row, mode in pairs(state.fallback_modes) do
      fallbacks[row] = mode
    end
    result.buffers[bufnr] = {
      generation = state.generation,
      widgets = vim.tbl_count(state.widgets),
      fallbacks = vim.tbl_count(state.fallbacks),
      results = #state.results,
      placements = placements,
      attempts = attempts,
      fallback_modes = fallbacks,
      errors = vim.deepcopy(state.errors),
      public_enabled = public_enabled(bufnr),
      builtin_was_enabled = state.builtin_was_enabled,
      last_error = state.last_error,
      right_windows = vim.deepcopy(state.right_windows or {}),
    }
  end
  return result
end

function M._flush_relayout()
  if relayout_scheduler then
    relayout_scheduler:flush()
  end
end

---@return integer
function M.namespace()
  return fallback_ns
end

return M
