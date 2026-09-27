local state = require("aligned-inline-diagnostic.state")
local highlights = require("aligned-inline-diagnostic.highlights")
local util = require("aligned-inline-diagnostic.util")

local M = {}

M.namespace = vim.api.nvim_create_namespace("aligned-inline-diagnostic")
M.active_namespace = vim.api.nvim_create_namespace("aligned-inline-diagnostic-active-range")

local deferred = {}
local schedule_serial = 0
local callback_error_epochs = {}

local function current_epoch()
  -- lifecycle_epoch is the current name. Keep epoch as a compatibility hook
  -- for consumers that adopted the earlier experimental field.
  if state.lifecycle_epoch ~= nil then
    return state.lifecycle_epoch
  end
  return state.epoch
end

local function epoch_matches(epoch)
  return current_epoch() == epoch
end

local function buffer_loaded(bufnr)
  return type(bufnr) == "number"
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.api.nvim_buf_is_loaded(bufnr)
end

local function stop_timer(timer)
  if not timer then
    return
  end
  pcall(function()
    if timer.is_closing and timer:is_closing() then
      return
    end
    if timer.stop then
      timer:stop()
    end
    if timer.close then
      timer:close()
    end
  end)
end

local function cancel_deferred(bufnr)
  local pending = deferred[bufnr]
  deferred[bufnr] = nil
  if pending then
    stop_timer(pending.timer)
  end
  state.pending[bufnr] = nil
end

local function can_render(bufnr)
  if not state.enabled or not state.config then
    return false
  end
  if state.disabled_buffers and state.disabled_buffers[bufnr] then
    return false
  end
  if not buffer_loaded(bufnr) then
    return false
  end

  local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
  if not ok then
    return false
  end
  return not util.is_disabled_filetype(filetype, state.config.disabled_filetypes)
end

local function list_contains(values, value)
  if values == nil then
    return true
  end
  if type(values) ~= "table" then
    return values == value
  end
  if values[value] ~= nil then
    return values[value] ~= false
  end
  for _, candidate in ipairs(values) do
    if candidate == value then
      return true
    end
  end
  return false
end

local function excluded_by(values, value)
  if values == nil or type(values) ~= "table" or next(values) == nil then
    return false
  end
  return list_contains(values, value)
end

local severity_names = {
  error = vim.diagnostic.severity.ERROR,
  warn = vim.diagnostic.severity.WARN,
  info = vim.diagnostic.severity.INFO,
  hint = vim.diagnostic.severity.HINT,
}

local function normalize_severity(value)
  if type(value) == "string" then
    return severity_names[value:lower()]
  end
  return value
end

local function severity_allowed(filter, severity)
  if filter == nil then
    return true
  end
  severity = severity or vim.diagnostic.severity.ERROR
  if type(filter) ~= "table" then
    return normalize_severity(filter) == severity
  end
  for _, value in ipairs(filter) do
    if normalize_severity(value) == severity then
      return true
    end
  end
  return false
end

local function notify_callback_error(name, message)
  local epoch = current_epoch()
  local marker = epoch == nil and false or epoch
  if callback_error_epochs[name] == marker then
    return
  end
  callback_error_epochs[name] = marker
  vim.schedule(function()
    if epoch_matches(epoch) then
      vim.notify(
        "aligned-inline-diagnostic " .. name .. ": " .. tostring(message),
        vim.log.levels.ERROR
      )
    end
  end)
end

local function diagnostic_allowed(bufnr, diagnostic, options)
  if not severity_allowed(options.severity, diagnostic.severity) then
    return false
  end
  if not list_contains(options.sources, diagnostic.source) then
    return false
  end
  if excluded_by(options.exclude_sources, diagnostic.source) then
    return false
  end
  if not list_contains(options.namespaces, diagnostic.namespace) then
    return false
  end
  if type(options.filter) == "function" then
    local ok, included = pcall(options.filter, diagnostic, bufnr)
    if not ok then
      notify_callback_error("diagnostics.filter", included)
      -- A broken optional filter should not make all diagnostics disappear.
      return true
    end
    return not not included
  end
  return true
end

local function key_part(value)
  local text = value == nil and "" or tostring(value)
  return #text .. ":" .. text
end

function M.diagnostic_key(diagnostic)
  if type(diagnostic) ~= "table" then
    return nil
  end
  local code = diagnostic.code
  if type(code) == "table" then
    code = code.value or code.code
  end
  return table.concat({
    tostring(diagnostic.namespace or ""),
    tostring(diagnostic.lnum or 0),
    tostring(diagnostic.col or 0),
    tostring(diagnostic.end_lnum or diagnostic.lnum or 0),
    tostring(diagnostic.end_col or ""),
    tostring(diagnostic.severity or ""),
    tostring(diagnostic.source or ""),
    tostring(code or ""),
    tostring(diagnostic.message or ""),
  }, "\31")
end

local function deduplication_key(diagnostic)
  local code = diagnostic.code
  if type(code) == "table" then
    code = code.value or code.target or code.code
  end
  return table.concat({
    key_part(diagnostic.lnum or 0),
    key_part(diagnostic.col or 0),
    key_part(diagnostic.end_lnum or diagnostic.lnum or 0),
    key_part(diagnostic.end_col),
    key_part(diagnostic.severity),
    key_part(diagnostic.source),
    key_part(code),
    key_part(diagnostic.message),
  }, "|")
end

local function collect_entries(bufnr)
  local by_line = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local diagnostic_options = state.config.diagnostics or {}
  local namespace_enabled = {}
  local seen = {}

  for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
    local row = tonumber(diagnostic.lnum) or 0
    local diagnostic_enabled = true
    if diagnostic.namespace ~= nil then
      diagnostic_enabled = namespace_enabled[diagnostic.namespace]
      if diagnostic_enabled == nil then
        local ok, enabled = pcall(vim.diagnostic.is_enabled, {
          bufnr = bufnr,
          ns_id = diagnostic.namespace,
        })
        diagnostic_enabled = not ok or enabled ~= false
        namespace_enabled[diagnostic.namespace] = diagnostic_enabled
      end
    end
    local allowed = row >= 0
      and row < line_count
      and diagnostic_enabled
      and diagnostic_allowed(bufnr, diagnostic, diagnostic_options)
    local duplicate = false
    if allowed and diagnostic_options.deduplicate then
      local key = deduplication_key(diagnostic)
      duplicate = seen[key] == true
      seen[key] = true
    end
    if allowed and not duplicate then
      by_line[row] = by_line[row] or {}
      table.insert(by_line[row], diagnostic)
    end
  end

  local entries = {}
  for row, diagnostics in pairs(by_line) do
    local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
    local ok, line_width = pcall(vim.api.nvim_buf_call, bufnr, function()
      return util.display_width(text)
    end)
    line_width = ok and line_width or util.display_width(text)
    local clearance_width = line_width
    local alignment = state.config.alignment
    if alignment.include_range_width then
      for _, diagnostic in ipairs(diagnostics) do
        local start_row = math.max(0, math.min(line_count - 1, diagnostic.lnum or row))
        local end_row =
          math.max(start_row, math.min(line_count - 1, diagnostic.end_lnum or start_row))
        local span = end_row - start_row + 1
        if end_row > start_row and span <= alignment.max_range_lines then
          local range_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
          local width_ok, range_width = pcall(vim.api.nvim_buf_call, bufnr, function()
            local widest = 0
            for _, range_line in ipairs(range_lines) do
              widest = math.max(widest, util.display_width(range_line))
            end
            return widest
          end)
          if width_ok then
            clearance_width = math.max(clearance_width, range_width)
          end
        end
      end
    end
    table.insert(entries, {
      row = row,
      line_width = line_width,
      clearance_width = clearance_width,
      diagnostics = util.sort_diagnostics(diagnostics),
    })
  end

  table.sort(entries, function(left, right)
    return left.row < right.row
  end)
  return entries
end

local function anchor_for_width(width)
  local options = state.config.alignment
  local anchor = math.max(options.min_col, width + options.padding)
  if options.max_col then
    anchor = math.min(anchor, options.max_col)
  end
  return anchor
end

local function format_count(entry)
  local preview = state.config.preview
  local extra = #entry.diagnostics - 1
  if extra <= 0 or not preview.show_count then
    return ""
  end
  if type(preview.count_format) == "function" then
    local ok, value = pcall(preview.count_format, extra, #entry.diagnostics)
    if ok and value ~= nil then
      return util.collapse(tostring(value))
    end
    if not ok then
      notify_callback_error("preview.count_format", value)
    end
  end
  return "+" .. extra
end

local function format_preview_message(entry, group_id)
  local diagnostic = entry.diagnostics[1]
  local fallback = util.collapse(diagnostic.message)
  local formatter = state.config.preview.format
  if type(formatter) ~= "function" then
    return fallback
  end
  local ok, value = pcall(formatter, diagnostic, {
    bufnr = entry.bufnr,
    row = entry.row,
    diagnostics = entry.diagnostics,
    count = #entry.diagnostics,
    group_id = group_id,
  })
  if not ok then
    notify_callback_error("preview.format", value)
    return fallback
  end
  if value == nil then
    return fallback
  end
  return util.collapse(tostring(value))
end

local function preview_natural_width(entry)
  local preview = state.config.preview
  local message = entry.preview_message or util.collapse(entry.diagnostics[1].message)
  local count_width = util.display_width(entry.count_text)
  local separator_width = count_width > 0 and 2 or 0
  return math.max(
    1,
    math.min(preview.max_width, util.display_width(message) + separator_width + count_width)
  )
end

local function assign_group_anchor(entries, first, last, group_id)
  local widest = 0
  local widest_preview = 1
  local widest_count = 0
  local widest_icon = 0
  for index = first, last do
    widest = math.max(widest, entries[index].clearance_width or entries[index].line_width)
    entries[index].group_id = group_id
    entries[index].count_text = format_count(entries[index])
    entries[index].preview_message = format_preview_message(entries[index], group_id)
    entries[index].natural_preview_width = preview_natural_width(entries[index])
    widest_preview = math.max(widest_preview, entries[index].natural_preview_width)
    widest_count = math.max(widest_count, util.display_width(entries[index].count_text))
    local diagnostic = entries[index].diagnostics[1]
    local icon = state.config.icons[util.icon_key(diagnostic.severity)]
      or state.config.icons.info
      or ""
    widest_icon = math.max(widest_icon, util.display_width(icon))
  end

  local anchor = anchor_for_width(widest)
  for index = first, last do
    local entry = entries[index]
    entry.anchor = anchor
    entry.preview_anchor =
      math.max(anchor, (entry.clearance_width or entry.line_width) + state.config.alignment.padding)
    entry.group_id = group_id
    entry.group_first = entries[first].row
    entry.group_last = entries[last].row
    entry.count_slot_width = widest_count
    entry.icon_slot_width = widest_icon
    if state.config.preview.width_mode == "fixed" then
      entry.preview_width = state.config.preview.max_width
    elseif state.config.preview.width_mode == "block" then
      entry.preview_width = widest_preview
    else
      entry.preview_width = entry.natural_preview_width
      entry.count_slot_width = util.display_width(entry.count_text)
      local diagnostic = entry.diagnostics[1]
      local icon = state.config.icons[util.icon_key(diagnostic.severity)]
        or state.config.icons.info
        or ""
      entry.icon_slot_width = util.display_width(icon)
    end
    if state.config.hover.match_preview_width then
      local preview = state.config.preview
      local icons = state.config.icons
      local overhead = preview.padding_left
        + preview.padding_right
        + util.display_width(icons.left)
        + util.display_width(icons.right)
        + entry.icon_slot_width
        + 1
      local minimum =
        math.max(state.config.hover.min_width, util.hover_structural_width(state.config))
      local current_total = entry.preview_width + overhead
      local target_total = math.max(minimum, math.min(state.config.hover.max_width, current_total))
      entry.preview_width = math.max(1, math.min(preview.max_width, target_total - overhead))
    end
  end
end

local function align_entries(entries)
  if #entries == 0 then
    return
  end

  local options = state.config.alignment
  if options.mode == "none" then
    for index, entry in ipairs(entries) do
      assign_group_anchor(entries, index, index, index)
      entry.anchor = (entry.clearance_width or entry.line_width) + options.padding
      entry.preview_anchor = entry.anchor
    end
    return
  end

  if options.mode == "buffer" then
    assign_group_anchor(entries, 1, #entries, 1)
    return
  end

  local group_start = 1
  local group_id = 1
  for index = 2, #entries do
    local clean_lines = entries[index].row - entries[index - 1].row - 1
    if clean_lines > options.max_gap then
      assign_group_anchor(entries, group_start, index - 1, group_id)
      group_start = index
      group_id = group_id + 1
    end
  end
  assign_group_anchor(entries, group_start, #entries, group_id)
end

local function window_for_buffer(bufnr)
  local ok, current = pcall(vim.api.nvim_get_current_win)
  if ok and current and vim.api.nvim_win_is_valid(current) then
    local valid, current_buf = pcall(vim.api.nvim_win_get_buf, current)
    if valid and current_buf == bufnr then
      return current
    end
  end
  local listed, windows = pcall(vim.api.nvim_list_wins)
  if listed then
    for _, winid in ipairs(windows) do
      if vim.api.nvim_win_is_valid(winid) then
        local valid, window_buf = pcall(vim.api.nvim_win_get_buf, winid)
        if valid and window_buf == bufnr then
          return winid
        end
      end
    end
  end
  return nil
end

local function preview_chunks(entry)
  local options = state.config
  local diagnostic = entry.diagnostics[1]
  local severity_key = util.severity_key(diagnostic.severity)
  local inactive = entry.inactive
  local body_hl = (inactive and "AlignedDiagnosticInactiveBody" or "AlignedDiagnosticPreviewBody")
    .. severity_key
  local icon_hl = (inactive and "AlignedDiagnosticInactiveIcon" or "AlignedDiagnosticPreviewIcon")
    .. severity_key
  local count_hl = (
    inactive and "AlignedDiagnosticInactiveCount" or "AlignedDiagnosticPreviewCount"
  ) .. severity_key
  local icon = options.icons[util.icon_key(diagnostic.severity)] or options.icons.info or ""
  local icon_padding =
    math.max(0, (entry.icon_slot_width or util.display_width(icon)) - util.display_width(icon))
  local preview = options.preview
  local count_text = entry.count_text or ""
  local max_count_width = math.max(1, entry.preview_width - 3)
  count_text = util.truncate(count_text, max_count_width, preview.ellipsis)
  local count_width = util.display_width(count_text)
  local count_slot_width = preview.count_align == "right"
      and math.min(entry.count_slot_width or count_width, max_count_width)
    or count_width
  local count_separator_width = count_slot_width > 0 and 2 or 0
  local message_width = math.max(1, entry.preview_width - count_separator_width - count_slot_width)
  local message = util.truncate(
    entry.preview_message or util.collapse(diagnostic.message),
    message_width,
    preview.ellipsis
  )
  local message_padding = 0
  local trailing_padding = 0
  if preview.count_align == "right" then
    message_padding = math.max(0, message_width - util.display_width(message))
  else
    trailing_padding = math.max(
      0,
      entry.preview_width - util.display_width(message) - count_separator_width - count_slot_width
    )
  end

  local padding = math.max(options.alignment.padding, entry.preview_anchor - entry.line_width)
  local chunks = {}
  local source_win = entry.source_win or window_for_buffer(entry.bufnr)
  local edge_descriptor = entry.edge_descriptor or highlights.prepare_edge_descriptor(source_win)
  -- EOL virtual text begins after Neovim's dedicated EOL screen cell.
  local virtual_column = entry.line_width + 2
  local function append(text, highlight)
    if text == "" then
      return
    end
    table.insert(chunks, { text, highlight })
    virtual_column = virtual_column + util.display_width(text)
  end
  local function edge_group(side, column)
    return highlights.edge_group("preview", severity_key, inactive, {
      source_win = source_win,
      bufnr = entry.bufnr,
      row = entry.row,
      side = side,
      virtual_column = column,
      edge_descriptor = edge_descriptor,
    })
  end
  local function append_underlay(count, side)
    local start_column = virtual_column
    local run_group = nil
    local run_width = 0
    for offset = 0, count - 1 do
      local group = edge_group(side, start_column + offset)
      if run_group and group ~= run_group then
        append(string.rep(" ", run_width), run_group)
        run_width = 0
      end
      run_group = group
      run_width = run_width + 1
    end
    if run_width > 0 then
      append(string.rep(" ", run_width), run_group)
    end
  end
  if padding > 0 then
    append_underlay(padding, "padding")
  end
  if options.icons.left ~= "" then
    append(options.icons.left, edge_group("left", virtual_column))
  end
  if preview.padding_left > 0 then
    append(string.rep(" ", preview.padding_left), body_hl)
  end
  append(icon, icon_hl)
  if icon_padding > 0 then
    append(string.rep(" ", icon_padding), body_hl)
  end
  append(" ", body_hl)
  append(message, body_hl)
  if message_padding > 0 then
    append(string.rep(" ", message_padding), body_hl)
  end
  if count_slot_width > 0 then
    append("  ", body_hl)
    local count_padding = math.max(0, count_slot_width - count_width)
    if count_padding > 0 then
      append(string.rep(" ", count_padding), count_hl)
    end
    append(count_text, count_hl)
  end
  if trailing_padding > 0 then
    append(string.rep(" ", trailing_padding), body_hl)
  end
  if preview.padding_right > 0 then
    append(string.rep(" ", preview.padding_right), body_hl)
  end
  if options.icons.right ~= "" then
    append(options.icons.right, edge_group("right", virtual_column))
  end
  local total_width = 0
  for _, chunk in ipairs(chunks) do
    total_width = total_width + util.display_width(chunk[1])
  end
  entry.preview_padding = padding
  entry.pill_width = math.max(0, total_width - padding)
  return chunks
end

local function is_inactive(entry)
  local target = state.hover.target
  local preview = state.config.preview
  if not target or not state.config.hover.dim_inactive or not preview.inactive.enabled then
    return false
  end
  if target.bufnr ~= entry.bufnr then
    return false
  end
  if entry.row == target.layout_row then
    return false
  end
  if preview.inactive.scope == "buffer" then
    return true
  end
  local active = M.get_layout(target.bufnr, target.layout_row)
  return active ~= nil and active.group_id == entry.group_id
end

local function place_entry(bufnr, entry)
  -- Hidden previews still define the canonical expanded width. A diagnostic
  -- refresh can rebuild layouts while the hover is open; measure the preview
  -- before skipping its extmark so mouse and cursor openings use the same
  -- pill_width instead of falling back to hover.preferred_width.
  local chunks = preview_chunks(entry)
  if entry.hidden then
    return nil
  end
  entry.extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M.namespace, entry.row, 0, {
    virt_text = chunks,
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = state.config.priority,
    strict = false,
    invalidate = true,
  })
  return entry.extmark_id
end

local function active_layout_for_target(layout, target)
  if
    not layout
    or not target
    or not state.config
    or not state.config.hover
    or state.config.hover.group_by ~= "range"
  then
    return layout
  end
  local target_key = target.diagnostic_key or M.diagnostic_key(target.diagnostic)
  if not target_key then
    return layout
  end
  for _, diagnostic in ipairs(layout.diagnostics or {}) do
    if diagnostic == target.diagnostic or M.diagnostic_key(diagnostic) == target_key then
      return { diagnostics = { diagnostic } }
    end
  end
  return nil
end

function M.render(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  cancel_deferred(bufnr)
  if not buffer_loaded(bufnr) then
    state.layouts[bufnr] = nil
    state.rendered_buffers[bufnr] = nil
    return
  end

  pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)
  M.clear_active_range(bufnr)
  state.layouts[bufnr] = {}
  state.rendered_buffers[bufnr] = true

  if not can_render(bufnr) then
    return
  end

  local entries = collect_entries(bufnr)
  for _, entry in ipairs(entries) do
    entry.bufnr = bufnr
  end
  align_entries(entries)
  local source_win = window_for_buffer(bufnr)
  local edge_descriptor = highlights.prepare_edge_descriptor(source_win)

  for _, entry in ipairs(entries) do
    entry.source_win = source_win
    entry.edge_descriptor = edge_descriptor
    local hover_target = state.hover.target
    entry.hidden = state.config.hover
      and state.config.hover.hide_preview
      and hover_target ~= nil
      and hover_target.bufnr == bufnr
      and hover_target.layout_row == entry.row
    state.layouts[bufnr][entry.row] = entry
  end
  for _, entry in ipairs(entries) do
    entry.inactive = is_inactive(entry)
    place_entry(bufnr, entry)
  end
  local target = state.hover.target
  if target and target.bufnr == bufnr then
    local layout = state.layouts[bufnr][target.layout_row]
    M.show_active_range(bufnr, active_layout_for_target(layout, target))
  end
end

function M.update_hover(bufnr)
  local layouts = state.layouts[bufnr]
  if not layouts or not buffer_loaded(bufnr) or not state.config then
    return
  end
  for _, entry in pairs(layouts) do
    if entry.extmark_id then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, M.namespace, entry.extmark_id)
      entry.extmark_id = nil
    end
    local target = state.hover.target
    entry.hidden = state.config.hover.hide_preview
      and target ~= nil
      and target.bufnr == bufnr
      and target.layout_row == entry.row
    entry.inactive = is_inactive(entry)
    place_entry(bufnr, entry)
  end
end

local function range_end(bufnr, diagnostic)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return nil
  end
  local start_row = math.max(0, math.min(line_count - 1, diagnostic.lnum or 0))
  local start_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1] or ""
  local start_col = math.max(0, math.min(#start_line, diagnostic.col or 0))
  local end_row = math.max(start_row, math.min(line_count - 1, diagnostic.end_lnum or start_row))
  local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""
  local end_col = diagnostic.end_col and math.max(0, math.min(#end_line, diagnostic.end_col)) or nil
  if end_row < start_row then
    end_row = start_row
    end_col = start_col + 1
  elseif end_col == nil then
    end_col = end_row == start_row and (start_col + 1) or 0
  end
  if end_row == start_row and end_col <= start_col then
    local character = vim.fn.strcharpart(start_line:sub(start_col + 1), 0, 1)
    end_col = start_col + #character
    if end_col <= start_col then
      return nil
    end
  end
  return start_row, start_col, end_row, end_col
end

function M.show_active_range(bufnr, layout)
  M.clear_active_range(bufnr)
  if not state.config then
    return
  end
  local mode = state.config.hover.highlight_target
  if not mode or not layout or not buffer_loaded(bufnr) then
    return
  end
  local diagnostics = mode == "primary" and { layout.diagnostics[1] } or layout.diagnostics
  for _, diagnostic in ipairs(diagnostics) do
    local start_row, start_col, end_row, end_col = range_end(bufnr, diagnostic)
    if start_row then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, M.active_namespace, start_row, start_col, {
        end_row = end_row,
        end_col = end_col,
        hl_group = "AlignedDiagnosticActiveRange" .. util.severity_key(diagnostic.severity),
        hl_mode = "combine",
        priority = state.config.priority
          + 6
          - (diagnostic.severity or vim.diagnostic.severity.ERROR),
        strict = false,
        invalidate = true,
      })
    end
  end
end

function M.clear_active_range(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.active_namespace, 0, -1)
  end
end

function M.schedule(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if type(bufnr) ~= "number" then
    return
  end
  local existing = deferred[bufnr]
  if existing then
    stop_timer(existing.timer)
    deferred[bufnr] = nil
  end
  schedule_serial = schedule_serial + 1
  local generation = schedule_serial
  state.pending[bufnr] = generation
  local delay = state.config and state.config.throttle_ms or 0
  local epoch = current_epoch()
  local record = { generation = generation, timer = nil }

  local function run()
    if deferred[bufnr] == record then
      deferred[bufnr] = nil
    end
    if state.pending[bufnr] ~= generation then
      return
    end
    state.pending[bufnr] = nil
    if not epoch_matches(epoch) then
      return
    end
    M.render(bufnr)
  end

  if delay == 0 then
    run()
  else
    deferred[bufnr] = record
    local timer = vim.defer_fn(run, delay)
    if deferred[bufnr] == record then
      record.timer = timer
    end
  end
end

function M.get_layout(bufnr, row)
  return state.layouts[bufnr] and state.layouts[bufnr][row] or nil
end

function M.preview_screen_bounds(source_win, entry)
  if
    not entry
    or type(source_win) ~= "number"
    or not vim.api.nvim_win_is_valid(source_win)
    or not buffer_loaded(entry.bufnr)
  then
    return nil
  end
  local ok, window_buf = pcall(vim.api.nvim_win_get_buf, source_win)
  if not ok or window_buf ~= entry.bufnr then
    return nil
  end
  local text = vim.api.nvim_buf_get_lines(entry.bufnr, entry.row, entry.row + 1, false)[1] or ""
  -- Query the NUL/EOL cell itself. This is the cell after the final buffer
  -- character and is also well-defined for empty lines. Measuring the last
  -- character instead loses one column because `virt_text_pos = "eol"`
  -- starts after this dedicated display cell.
  local point = vim.fn.screenpos(source_win, entry.row + 1, #text + 1)
  if not point or point.row == 0 or point.col == 0 then
    return nil
  end
  local padding = entry.preview_padding
    or math.max(state.config.alignment.padding, entry.preview_anchor - entry.line_width)
  -- `endcol` is one-based and inclusive, while float columns are zero-based,
  -- so adding the explicit padding yields the first cell of the pill.
  local eol_end = point.endcol and point.endcol > 0 and point.endcol or point.col
  local left = eol_end + padding
  return {
    row = point.row - 1,
    left = left,
    right = left + (entry.pill_width or 0),
  }
end

-- Neovim diagnostic ranges use zero-based byte columns and an exclusive end.
-- A missing single-line end is treated as one byte/cell so point diagnostics
-- remain targetable. Passing no column asks whether any part spans the row.
function M.diagnostic_contains(diagnostic, row, col)
  if type(diagnostic) ~= "table" or type(row) ~= "number" then
    return false
  end
  local start_row = diagnostic.lnum or 0
  local start_col = diagnostic.col or 0
  local end_row = diagnostic.end_lnum or start_row
  local end_col = diagnostic.end_col
  if end_row < start_row or row < start_row or row > end_row then
    return false
  end

  if col == nil then
    if start_row ~= end_row and row == end_row and end_col ~= nil then
      return end_col > 0
    end
    return true
  end
  if type(col) ~= "number" or col < 0 then
    return false
  end
  if start_row == end_row then
    end_col = math.max(start_col + 1, end_col or (start_col + 1))
    return row == start_row and col >= start_col and col < end_col
  end
  if row == start_row then
    return col >= start_col
  end
  if row == end_row then
    return end_col == nil or col < end_col
  end
  return true
end

local function ordered_layouts(bufnr)
  local result = {}
  for _, layout in pairs(state.layouts[bufnr] or {}) do
    table.insert(result, layout)
  end
  table.sort(result, function(left, right)
    return left.row < right.row
  end)
  return result
end

-- Return every matching diagnostic together with its preview layout. Unlike
-- find_layout(), this deliberately does not let a nearer start row mask an
-- overlapping multiline range.
function M.diagnostic_matches_at(bufnr, row, col)
  local result = {}
  local seen = {}
  for _, layout in ipairs(ordered_layouts(bufnr)) do
    for _, diagnostic in ipairs(layout.diagnostics or {}) do
      if not seen[diagnostic] and M.diagnostic_contains(diagnostic, row, col) then
        seen[diagnostic] = true
        table.insert(result, { diagnostic = diagnostic, layout = layout })
      end
    end
  end
  return result
end

function M.diagnostics_at(bufnr, row, col)
  local diagnostics = {}
  for _, match in ipairs(M.diagnostic_matches_at(bufnr, row, col)) do
    table.insert(diagnostics, match.diagnostic)
  end
  return util.sort_diagnostics(diagnostics)
end

function M.diagnostics_in_group(bufnr, group_id)
  local diagnostics = {}
  local seen = {}
  for _, layout in ipairs(ordered_layouts(bufnr)) do
    if layout.group_id == group_id then
      for _, diagnostic in ipairs(layout.diagnostics or {}) do
        if not seen[diagnostic] then
          seen[diagnostic] = true
          table.insert(diagnostics, diagnostic)
        end
      end
    end
  end
  return util.sort_diagnostics(diagnostics)
end

function M.find_layout(bufnr, row)
  local layouts = state.layouts[bufnr]
  if not layouts then
    return nil
  end
  if layouts[row] then
    return layouts[row]
  end

  local best = nil
  for _, layout in pairs(layouts) do
    if layout.row <= row and (not best or layout.row > best.row) then
      for _, diagnostic in ipairs(layout.diagnostics) do
        if M.diagnostic_contains(diagnostic, row) then
          best = layout
          break
        end
      end
    end
  end
  return best
end

function M.hide_line(bufnr, row)
  local entry = M.get_layout(bufnr, row)
  if not entry then
    return
  end
  entry.hidden = true
  if entry.extmark_id and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.namespace, entry.extmark_id)
  end
  entry.extmark_id = nil
end

function M.show_line(bufnr, row)
  local entry = M.get_layout(bufnr, row)
  if not entry or not buffer_loaded(bufnr) then
    return
  end
  entry.hidden = false
  if not entry.extmark_id and can_render(bufnr) then
    place_entry(bufnr, entry)
  end
end

function M.clear(bufnr)
  if type(bufnr) ~= "number" then
    return
  end
  cancel_deferred(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.active_namespace, 0, -1)
  end
  state.layouts[bufnr] = nil
  state.rendered_buffers[bufnr] = nil
  state.pending[bufnr] = nil
end

function M.clear_all()
  local buffers = {}
  for bufnr in pairs(state.rendered_buffers) do
    buffers[bufnr] = true
  end
  for bufnr in pairs(deferred) do
    buffers[bufnr] = true
  end
  for bufnr in pairs(state.pending) do
    buffers[bufnr] = true
  end
  for bufnr in pairs(buffers) do
    M.clear(bufnr)
  end
end

return M
