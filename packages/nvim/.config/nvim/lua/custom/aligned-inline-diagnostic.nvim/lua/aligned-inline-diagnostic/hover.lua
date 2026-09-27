local renderer = require("aligned-inline-diagnostic.renderer")
local highlights = require("aligned-inline-diagnostic.highlights")
local state = require("aligned-inline-diagnostic.state")
local util = require("aligned-inline-diagnostic.util")

local M = {}

M.namespace = vim.api.nvim_create_namespace("aligned-inline-diagnostic-hover")

local formatter_errors = {}

local function code_text(code)
  if type(code) == "table" then
    code = code.value or code.code
  end
  return code ~= nil and tostring(code) or nil
end

local function related_information(diagnostic)
  local user_data = type(diagnostic.user_data) == "table" and diagnostic.user_data or {}
  local lsp = type(user_data.lsp) == "table" and user_data.lsp or user_data
  local related = lsp.relatedInformation or lsp.related_information
  return type(related) == "table" and related or {}
end

local function location_text(location)
  if type(location) ~= "table" then
    return nil
  end

  local uri = location.uri
  local range = location.range or {}
  local start = range.start or {}
  local line = type(start.line) == "number" and (start.line + 1) or nil
  if not uri then
    return line and ("line %d"):format(line) or nil
  end

  local ok, filename = pcall(vim.uri_to_fname, uri)
  filename = ok and filename or uri
  filename = vim.fn.fnamemodify(filename, ":t")
  return line and ("%s:%d"):format(filename, line) or filename
end

local function notify_formatter(name, message)
  local key = name .. ":" .. tostring(message)
  if formatter_errors[key] then
    return
  end
  formatter_errors[key] = true
  vim.schedule(function()
    vim.notify(
      ("aligned-inline-diagnostic hover.%s: %s"):format(name, tostring(message)),
      vim.log.levels.ERROR
    )
  end)
end

local function normalize_text(value)
  if value == nil then
    return nil
  end
  if type(value) == "table" then
    local lines = {}
    for _, item in ipairs(value) do
      table.insert(lines, tostring(item))
    end
    return table.concat(lines, "\n")
  end
  return tostring(value)
end

local function call_formatter(name, formatter, diagnostic, context)
  if type(formatter) ~= "function" then
    return nil, false
  end
  local ok, value = pcall(formatter, diagnostic, context)
  if not ok then
    notify_formatter(name, value)
    -- A broken formatter should not make the diagnostic itself disappear.
    -- Successful nil remains an intentional suppression signal.
    return nil, false
  end
  return normalize_text(value), true
end

local function append_details(details, diagnostic, context)
  local options = state.config.hover

  if options.show_related then
    for _, related in ipairs(related_information(diagnostic)) do
      local text = related.message or "Related diagnostic"
      local location = location_text(related.location)
      if location then
        text = text .. " (" .. location .. ")"
      end
      table.insert(details, text)
    end
  end

  if type(options.details) ~= "function" then
    return
  end
  local ok, extra = pcall(options.details, diagnostic, context)
  if not ok then
    notify_formatter("details", extra)
    return
  end
  if type(extra) == "string" then
    extra = { extra }
  end
  if type(extra) == "table" then
    for _, text in ipairs(extra) do
      table.insert(details, tostring(text))
    end
  end
end

local function diagnostic_model(diagnostic, context)
  local options = state.config.hover
  local message, used_message_formatter =
    call_formatter("format_message", options.format_message, diagnostic, context)
  if not used_message_formatter then
    message = diagnostic.message or ""
  end
  message = message or ""

  local metadata, used_metadata_formatter =
    call_formatter("format_metadata", options.format_metadata, diagnostic, context)
  if not used_metadata_formatter then
    local parts = {}
    if options.show_severity then
      table.insert(parts, util.severity_name(diagnostic.severity))
    end
    if context.show_source and diagnostic.source and diagnostic.source ~= "" then
      table.insert(parts, tostring(diagnostic.source))
    end
    local code = options.show_code and code_text(diagnostic.code) or nil
    if code and code ~= "" then
      table.insert(parts, code)
    end
    metadata = table.concat(parts, options.metadata_separator)
  end
  if options.metadata_position == "hidden" then
    metadata = ""
  end

  local details = {}
  append_details(details, diagnostic, context)
  return {
    message = message,
    metadata = metadata or "",
    details = details,
    severity = diagnostic.severity,
  }
end

local function models_for(diagnostics, base_context)
  local options = state.config.hover
  local models = {}
  local seen_sources = {}
  local sorted = util.sort_diagnostics(diagnostics)
  for index, diagnostic in ipairs(sorted) do
    local source = diagnostic.source and tostring(diagnostic.source) or ""
    local show_source = options.show_source and source ~= ""
    if show_source and options.deduplicate_source and seen_sources[source] then
      show_source = false
    end
    if show_source then
      seen_sources[source] = true
    end
    local context = {}
    for key, value in pairs(base_context or {}) do
      context[key] = value
    end
    context.index = index
    context.count = #sorted
    context.show_source = show_source
    table.insert(models, diagnostic_model(diagnostic, context))
  end
  return models
end

local function split_provider_lines(text)
  return vim.split((text or ""):gsub("\r", ""), "\n", {
    plain = true,
    trimempty = false,
  })
end

local function content_items(model)
  local options = state.config.hover
  local message_lines = split_provider_lines(model.message)
  local primary = table.remove(message_lines, 1) or ""
  local children = {}
  for _, text in ipairs(message_lines) do
    table.insert(children, { text = text, role = "submessage" })
  end
  if options.metadata_position == "inline" and options.message_first and model.metadata ~= "" then
    primary = primary == "" and model.metadata
      or (primary .. options.metadata_separator .. model.metadata)
  elseif
    (options.metadata_position == "below" or options.metadata_position == "inline")
    and model.metadata ~= ""
  then
    table.insert(children, { text = model.metadata, role = "metadata" })
  end
  for _, detail in ipairs(model.details) do
    table.insert(children, { text = detail, role = "detail" })
  end
  return primary, children
end

local function natural_width(models)
  local options = state.config.hover
  local icons = state.config.icons
  local lane_width = math.max(
    util.display_width(icons.error or ""),
    util.display_width(icons.warn or ""),
    util.display_width(icons.info or ""),
    util.display_width(icons.hint or ""),
    util.display_width(icons.branch or ""),
    util.display_width(icons.continuation or ""),
    util.display_width(icons.last or ""),
    util.display_width(icons.related or "")
  )
  local widest = 1
  for _, model in ipairs(models) do
    local primary, children = content_items(model)
    if options.message_first or model.metadata == "" then
      widest = math.max(widest, lane_width + 1 + util.display_width(primary))
      for _, child in ipairs(children) do
        widest = math.max(widest, lane_width + 1 + util.display_width(child.text))
      end
    else
      widest = math.max(widest, lane_width + 1 + util.display_width(model.metadata))
      widest = math.max(widest, lane_width + 1 + util.display_width(primary))
      for _, child in ipairs(children) do
        if child.role ~= "metadata" then
          widest = math.max(widest, lane_width + 1 + util.display_width(child.text))
        end
      end
    end
  end
  return widest + options.padding_left + options.padding_right
end

local function make_line(text, severity, prefix_bytes, role, model_index)
  return {
    text = text,
    severity = severity,
    prefix_bytes = prefix_bytes,
    role = role,
    model_index = model_index,
  }
end

local function pad_glyph(glyph, lane_width)
  glyph = glyph or ""
  return glyph .. string.rep(" ", math.max(0, lane_width - util.display_width(glyph))) .. " "
end

local function wrapped(text, width)
  return util.wrap(text, width, state.config.hover.wrap_mode)
end

local function append_wrapped(
  lines,
  text,
  severity,
  first_glyph,
  lane_width,
  width,
  role,
  model_index
)
  local continuation = state.config.icons.continuation
  for index, value in ipairs(wrapped(text, width)) do
    local prefix = pad_glyph(index == 1 and first_glyph or continuation, lane_width)
    table.insert(lines, make_line(prefix .. value, severity, #prefix, role, model_index))
  end
end

local function format_models(models, width)
  local options = state.config.hover
  local icons = state.config.icons
  local lane_width = math.max(
    util.display_width(icons.error or ""),
    util.display_width(icons.warn or ""),
    util.display_width(icons.info or ""),
    util.display_width(icons.hint or ""),
    util.display_width(icons.branch or ""),
    util.display_width(icons.continuation or ""),
    util.display_width(icons.last or ""),
    util.display_width(icons.related or "")
  )
  local content_width = math.max(1, width - lane_width - 1)
  local lines = {}

  for model_index, model in ipairs(models) do
    local icon = icons[util.icon_key(model.severity)] or icons.info or ""
    local primary, children = content_items(model)

    if options.message_first or model.metadata == "" then
      append_wrapped(
        lines,
        primary,
        model.severity,
        icon,
        lane_width,
        content_width,
        "message",
        model_index
      )
    else
      append_wrapped(
        lines,
        model.metadata,
        model.severity,
        icon,
        lane_width,
        content_width,
        "metadata",
        model_index
      )
      local legacy_children = { { text = primary, role = "message" } }
      for _, child in ipairs(children) do
        if child.role ~= "metadata" then
          table.insert(legacy_children, child)
        end
      end
      children = legacy_children
    end

    for child_index, child in ipairs(children) do
      local glyph = child.role == "detail" and icons.related
        or (child_index == #children and icons.last or icons.branch)
      append_wrapped(
        lines,
        child.text,
        model.severity,
        glyph,
        lane_width,
        content_width,
        child.role,
        model_index
      )
    end

    if model_index < #models then
      for _ = 1, options.item_spacing do
        table.insert(lines, make_line("", model.severity, 0, "spacing", model_index))
      end
    end
  end
  return lines
end

local function truncate_height(lines, max_height)
  if #lines <= max_height then
    return lines
  end
  if max_height == 1 then
    -- Showing the actual diagnostic is more useful than a one-row message
    -- which only says that useful content was hidden.
    return { lines[1] }
  end

  local slots = max_height - 1
  local groups = {}
  local order = {}
  for _, line in ipairs(lines) do
    if line.role ~= "spacing" then
      local key = line.model_index or 1
      if not groups[key] then
        groups[key] = {}
        table.insert(order, key)
      end
      table.insert(groups[key], line)
    end
  end

  local counts = {}
  local remaining = slots
  for _, key in ipairs(order) do
    if remaining == 0 then
      break
    end
    counts[key] = 1
    remaining = remaining - 1
  end
  while remaining > 0 do
    local progressed = false
    for _, key in ipairs(order) do
      local count = counts[key] or 0
      if count > 0 and count < #groups[key] and remaining > 0 then
        counts[key] = count + 1
        remaining = remaining - 1
        progressed = true
      end
    end
    if not progressed then
      break
    end
  end

  local result = {}
  for _, key in ipairs(order) do
    for index = 1, counts[key] or 0 do
      table.insert(result, groups[key][index])
    end
  end
  local hidden = #lines - #result
  local severity = result[#result] and result[#result].severity or vim.diagnostic.severity.ERROR
  local prefix = state.config.icons.continuation .. " "
  table.insert(
    result,
    make_line(
      prefix .. ("… %d more lines"):format(hidden),
      severity,
      #prefix,
      "metadata",
      result[#result] and result[#result].model_index or nil
    )
  )
  return result
end

local function decorate_lines(lines, width)
  local options = state.config.hover
  local cap_style = options.cap_style
  local left = cap_style == "none" and "" or (state.config.icons.left or "")
  local right = cap_style == "none" and "" or (state.config.icons.right or "")
  local left_width = util.display_width(left)
  local right_width = util.display_width(right)
  local body_width = math.max(1, width - left_width - right_width)
  local decorated = {}

  for index, line in ipairs(lines) do
    local has_left_cap = left ~= "" and (cap_style == "all" or index == 1)
    local has_right_cap = right ~= "" and (cap_style == "all" or index == #lines)
    local left_slot = has_left_cap and left or string.rep(" ", left_width)
    local right_slot = has_right_cap and right or string.rep(" ", right_width)
    local available = math.max(1, body_width - options.padding_left - options.padding_right)
    local clipped = util.truncate(line.text, available, "…")
    local trailing = math.max(0, available - util.display_width(clipped))
    local body = string.rep(" ", options.padding_left)
      .. clipped
      .. string.rep(" ", trailing + options.padding_right)
    local body_start = #left_slot
    local body_end = body_start + #body
    local text_start = body_start + options.padding_left
    local text_end = text_start + #clipped
    local prefix_end = math.min(text_end, text_start + line.prefix_bytes)
    table.insert(decorated, {
      text = left_slot .. body .. right_slot,
      severity = line.severity,
      role = line.role,
      left_edge_end = #left_slot,
      left_edge_width = left_width,
      left_cap_end = has_left_cap and #left_slot or 0,
      body_start = body_start,
      body_end = body_end,
      prefix_start = text_start,
      prefix_end = prefix_end,
      content_start = prefix_end,
      content_end = text_end,
      right_edge_start = body_end,
      right_edge_width = right_width,
      right_cap_start = has_right_cap and body_end or body_end + #right_slot,
    })
  end
  return decorated
end

local function has_border(border)
  return border ~= nil and border ~= "" and border ~= "none"
end

local function window_geometry(source_win)
  local position = vim.api.nvim_win_get_position(source_win)
  local info = nil
  local ok, values = pcall(vim.fn.getwininfo, source_win)
  if ok and type(values) == "table" then
    info = values[1]
  end
  local left = position[2]
  local top = position[1] + ((info and info.winbar) or 0)
  local width = vim.api.nvim_win_get_width(source_win)
  local height = vim.api.nvim_win_get_height(source_win)
  return {
    left = left,
    right = left + width,
    top = top,
    bottom = top + height,
    text_left = left + ((info and info.textoff) or 0),
    leftcol = (info and info.leftcol) or 0,
  }
end

local function add_screen_point(bounds, point)
  if not point or point.row == 0 or point.col == 0 then
    return false
  end
  local row = point.row - 1
  local col = point.col - 1
  local right = point.endcol and point.endcol > 0 and point.endcol or point.col
  bounds.top = bounds.top and math.min(bounds.top, row) or row
  bounds.bottom = bounds.bottom and math.max(bounds.bottom, row) or row
  bounds.left = bounds.left and math.min(bounds.left, col) or col
  bounds.right = bounds.right and math.max(bounds.right, right) or right
  return true
end

local function source_geometry(source_win, layout, target_row)
  local bounds = {}
  local bufnr = layout.bufnr or vim.api.nvim_win_get_buf(source_win)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local viewport_first = 0
  local viewport_last = line_count - 1
  local info_ok, info_values = pcall(vim.fn.getwininfo, source_win)
  local info = info_ok and type(info_values) == "table" and info_values[1] or nil
  if info then
    viewport_first = math.max(0, (info.topline or 1) - 1)
    -- botline can lag until the next redraw after replacing a buffer. The
    -- window-height estimate is an upper bound; off-screen screenpos() calls
    -- fail closed below, while a stale botline must not hide real overlap.
    local estimated_last = viewport_first + vim.api.nvim_win_get_height(source_win) - 1
    viewport_last = math.min(
      line_count - 1,
      math.max(viewport_first, estimated_last, (info.botline or line_count) - 1)
    )
  end
  local max_scan = state.config.alignment.max_range_lines or 50

  for _, diagnostic in ipairs(layout.diagnostics) do
    local start_row = math.max(0, math.min(line_count - 1, diagnostic.lnum or layout.row))
    local start_col = diagnostic.col or 0
    local end_row = math.max(start_row, math.min(line_count - 1, diagnostic.end_lnum or start_row))
    local end_col = diagnostic.end_col
    if end_row == start_row and end_col == nil then
      end_col = start_col + 1
    end
    if end_row > start_row and end_col == 0 then
      end_row = end_row - 1
      end_col = nil
    end

    if start_row < viewport_first then
      bounds.uncertain_top = true
    end
    if end_row > viewport_last then
      bounds.uncertain_bottom = true
    end

    local visible_first = math.max(start_row, viewport_first)
    local visible_last = math.min(end_row, viewport_last)
    local rows = {}
    if visible_first <= visible_last then
      if visible_last - visible_first + 1 > max_scan then
        bounds.uncertain_horizontal = true
        rows = { visible_first, visible_last }
      else
        for row = visible_first, visible_last do
          table.insert(rows, row)
        end
      end
    end

    for _, row in ipairs(rows) do
      local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
      local first_col = row == start_row and start_col or 0
      local final_col = row == end_row and end_col or #text
      first_col = math.max(0, math.min(#text, first_col))
      final_col = final_col and math.max(0, math.min(#text, final_col)) or #text
      local first_query = text == "" and 1 or math.max(1, math.min(#text, first_col + 1))
      local final_query = text == "" and 1 or math.max(1, math.min(#text, final_col))
      local first_point = vim.fn.screenpos(source_win, row + 1, first_query)
      local final_point = vim.fn.screenpos(source_win, row + 1, final_query)
      local first_visible = add_screen_point(bounds, first_point)
      local final_visible = add_screen_point(bounds, final_point)
      if not first_visible or not final_visible then
        bounds.uncertain_horizontal = true
      end
      if row == start_row and not first_visible then
        bounds.uncertain_top = true
      end
      if row == end_row and not final_visible then
        bounds.uncertain_bottom = true
      end
      if first_visible and final_visible and first_point.row ~= final_point.row then
        bounds.uncertain_horizontal = true
      end
    end
  end

  local line_point = vim.fn.screenpos(source_win, layout.row + 1, 1)
  if not bounds.top then
    line_point = vim.fn.screenpos(source_win, target_row + 1, 1)
    add_screen_point(bounds, line_point)
    bounds.uncertain_horizontal = true
    bounds.uncertain_top = true
    bounds.uncertain_bottom = true
  end
  if not bounds.top then
    return nil
  end
  local anchor_col
  if line_point and line_point.row ~= 0 and line_point.col ~= 0 then
    anchor_col = (line_point.col - 1) + (layout.preview_anchor or layout.anchor) + 1
  end
  return bounds, anchor_col
end

local function structural_min_width()
  return util.hover_structural_width(state.config)
end

local function desired_width(models, layout)
  local options = state.config.hover
  local cap_width = options.cap_style == "none" and 0
    or (
      util.display_width(state.config.icons.left or "")
      + util.display_width(state.config.icons.right or "")
    )
  local natural = natural_width(models) + cap_width
  local minimum = math.max(options.min_width, structural_min_width())
  if options.match_preview_width and layout.pill_width then
    return math.max(minimum, math.min(options.max_width, layout.pill_width))
  end
  local target
  if options.width_mode == "fixed" then
    target = options.max_width
  elseif options.width_mode == "fit" then
    target = natural
  else
    target = options.preferred_width
  end
  return math.max(minimum, math.min(options.max_width, target))
end

local function candidate_geometry(kind, source_win, layout, target_row, width, stable_geometry)
  local options = state.config.hover
  local placement = options.placement
  local window = window_geometry(source_win)
  local source, anchor_col = source_geometry(source_win, layout, target_row)
  if not source then
    return nil
  end
  local border_columns = has_border(options.border) and 2 or 0
  local margin = placement.edge_margin
  local left = window.text_left + margin
  local right = window.right - margin
  local available_full = right - left - border_columns
  local minimum = math.max(options.min_width, structural_min_width())
  if available_full < structural_min_width() then
    return nil
  end

  anchor_col = (anchor_col or window.text_left) + options.col_offset
  local preview_bounds = placement.preserve_anchor
      and renderer.preview_screen_bounds(source_win, layout)
    or nil
  local result = {
    kind = kind,
    window_left = left,
    window_right = right,
    window_top = window.top + margin,
    window_bottom = window.bottom - margin,
    source_top = source.top,
    source_bottom = source.bottom,
  }
  if kind == "right" then
    local preserve_anchor = preview_bounds ~= nil
    local preserve_geometry = preserve_anchor
      and stable_geometry ~= nil
      and stable_geometry.kind == "right"
      and stable_geometry.window_left == left
      and stable_geometry.window_right == right
    if placement.avoid_source and source.uncertain_horizontal and not preserve_geometry then
      return nil
    end
    local col
    if preserve_geometry then
      col = stable_geometry.col
    elseif preserve_anchor then
      col = preview_bounds.left + options.col_offset
    else
      col = (placement.avoid_source and math.max(anchor_col, source.right) or anchor_col)
        + placement.gap
    end
    if placement.avoid_source and col <= source.right and not preserve_geometry then
      return nil
    end
    local available = right - col - border_columns
    local candidate_minimum = preserve_anchor and structural_min_width() or minimum
    if available < candidate_minimum then
      return nil
    end
    result.col = col
    result.width = math.min(preserve_geometry and stable_geometry.width or width, available)
    result.row = preserve_anchor and (preview_bounds.row + options.row_offset)
      or (source.top + options.row_offset)
    result.preserve_anchor = preserve_anchor
    result.virtual_column = preserve_geometry
        and math.max(1, col - window.text_left + window.leftcol + 1)
      or (
        preserve_anchor
          and ((layout.preview_anchor or layout.anchor or 0) + 2 + options.col_offset)
        or math.max(1, col - window.text_left + window.leftcol + 1)
      )
  else
    if placement.avoid_source and kind == "below" and source.uncertain_bottom then
      return nil
    end
    if placement.avoid_source and kind == "above" and source.uncertain_top then
      return nil
    end
    result.width = math.min(width, available_full)
    if result.width < minimum then
      return nil
    end
    result.col = math.max(left, math.min(anchor_col, right - result.width - border_columns))
    if kind == "below" then
      result.row = source.bottom + 1 + placement.gap
    else
      result.row = source.top - 1 - placement.gap
    end
    result.virtual_column = math.max(1, result.col - window.text_left + window.leftcol + 1)
  end
  return result
end

local function fit_candidate(candidate, models)
  local options = state.config.hover
  local border_rows = has_border(options.border) and 2 or 0
  local cap_width = options.cap_style == "none" and 0
    or (
      util.display_width(state.config.icons.left or "")
      + util.display_width(state.config.icons.right or "")
    )
  local content_width =
    math.max(1, candidate.width - cap_width - options.padding_left - options.padding_right)
  local lines = format_models(models, content_width)
  local available
  if candidate.kind == "below" then
    available = candidate.window_bottom - candidate.row - border_rows
  elseif candidate.kind == "above" then
    available = candidate.row - candidate.window_top + 1 - border_rows
  elseif candidate.preserve_anchor then
    available = candidate.window_bottom - candidate.row - border_rows
  else
    available = candidate.window_bottom - candidate.window_top - border_rows
  end
  available = math.min(options.max_height, available)
  if available < 1 then
    return nil
  end
  if not state.hover.pinned then
    lines = truncate_height(lines, available)
  end
  local height = math.min(#lines, available)
  if candidate.kind == "above" then
    candidate.row = candidate.row - height - border_rows + 1
  elseif candidate.kind == "right" and not candidate.preserve_anchor then
    candidate.row = math.max(
      candidate.window_top,
      math.min(candidate.row, candidate.window_bottom - height - border_rows)
    )
  end
  candidate.lines = decorate_lines(lines, candidate.width)
  candidate.height = height
  return candidate
end

local function choose_geometry(source_win, layout, target_row, models, stable_geometry)
  local width = desired_width(models, layout)
  for _, kind in ipairs(state.config.hover.placement.order) do
    local candidate =
      candidate_geometry(kind, source_win, layout, target_row, width, stable_geometry)
    if candidate then
      candidate = fit_candidate(candidate, models)
      if candidate then
        return candidate
      end
    end
  end
  return nil
end

local function diagnostic_key(diagnostic)
  if not diagnostic then
    return nil
  end
  if type(renderer.diagnostic_key) == "function" then
    return renderer.diagnostic_key(diagnostic)
  end
  return table.concat({
    tostring(diagnostic.namespace or ""),
    tostring(diagnostic.lnum or 0),
    tostring(diagnostic.col or 0),
    tostring(diagnostic.end_lnum or diagnostic.lnum or 0),
    tostring(diagnostic.end_col or ""),
    tostring(diagnostic.severity or ""),
    tostring(diagnostic.source or ""),
    tostring(code_text(diagnostic.code) or ""),
    tostring(diagnostic.message or ""),
  }, "\31")
end

local function targets_equal(left, right)
  return left ~= nil
    and right ~= nil
    and left.bufnr == right.bufnr
    and left.source_win == right.source_win
    and left.group_key == right.group_key
end

local function target_at(bufnr, row, source_win, input, diagnostic)
  if not vim.api.nvim_win_is_valid(source_win) or vim.api.nvim_win_get_buf(source_win) ~= bufnr then
    return nil
  end
  local layout = diagnostic and renderer.get_layout(bufnr, diagnostic.lnum or row)
    or renderer.find_layout(bufnr, row)
  if not layout then
    return nil
  end
  local grouping = state.config.hover.group_by or "line"
  if grouping == "range" and not diagnostic then
    diagnostic = layout.diagnostics[1]
  end
  local selected_key = diagnostic_key(diagnostic)
  local group_key = grouping == "block" and ("block:" .. tostring(layout.group_id))
    or (grouping == "range" and ("range:" .. tostring(selected_key)) or ("line:" .. layout.row))
  return {
    bufnr = bufnr,
    row = row,
    source_win = source_win,
    layout_row = layout.row,
    diagnostic = diagnostic,
    diagnostic_key = selected_key,
    group_key = group_key,
    input = input or "cursor",
  }
end

local position_in_diagnostic

local function diagnostics_at(bufnr, row, col)
  if type(renderer.diagnostics_at) == "function" then
    return renderer.diagnostics_at(bufnr, row, col)
  end
  local result = {}
  for _, layout in pairs(state.layouts[bufnr] or {}) do
    for _, diagnostic in ipairs(layout.diagnostics or {}) do
      if position_in_diagnostic(diagnostic, row, col) then
        table.insert(result, diagnostic)
      end
    end
  end
  return util.sort_diagnostics(result)
end

local function cursor_target()
  local source_win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(source_win)
  local cursor = vim.api.nvim_win_get_cursor(source_win)
  local row = cursor[1] - 1
  if state.config.hover.cursor_scope == "diagnostic" then
    local matches = diagnostics_at(bufnr, row, cursor[2])
    return matches[1] and target_at(bufnr, row, source_win, "cursor", matches[1]) or nil
  end
  return target_at(bufnr, row, source_win, "cursor")
end

position_in_diagnostic = function(diagnostic, row, col)
  local start_row = diagnostic.lnum or 0
  local start_col = diagnostic.col or 0
  local end_row = diagnostic.end_lnum or start_row
  local end_col = diagnostic.end_col
  if end_row < start_row or row < start_row or row > end_row then
    return false
  end
  if row == start_row and col < start_col then
    return false
  end
  if start_row == end_row then
    end_col = end_col or (start_col + 1)
    return col < math.max(start_col + 1, end_col)
  end
  if row == end_row and end_col ~= nil then
    return col < end_col
  end
  return true
end

local function preview_layout_at(bufnr, source_win, mouse)
  if not mouse.screenrow or not mouse.screencol then
    return nil
  end
  local screen_row = mouse.screenrow - 1
  local screen_col = mouse.screencol - 1
  for _, layout in pairs(state.layouts[bufnr] or {}) do
    local bounds = renderer.preview_screen_bounds(source_win, layout)
    if
      bounds
      and screen_row == bounds.row
      and screen_col >= bounds.left
      and screen_col < bounds.right
    then
      return layout
    end
  end
  return nil
end

local function mouse_over_open_surface(mouse)
  if not mouse or not state.hover.target then
    return false
  end
  if not mouse.winid or mouse.winid == 0 then
    return false
  end
  local bounds = state.hover.bounds
  local screen_row = mouse.screenrow and (mouse.screenrow - 1) or nil
  local screen_col = mouse.screencol and (mouse.screencol - 1) or nil
  if
    bounds
    and screen_row
    and screen_col
    and screen_row >= bounds.top
    and screen_row < bounds.bottom
    and screen_col >= bounds.left
    and screen_col < bounds.right
  then
    return true
  end
  return state.hover.win ~= nil and mouse.winid == state.hover.win
end

local function mouse_target(mouse)
  mouse = mouse or vim.fn.getmousepos()
  if not mouse or not mouse.winid or mouse.winid == 0 then
    return nil
  end
  if mouse_over_open_surface(mouse) then
    return state.hover.target
  end
  if not vim.api.nvim_win_is_valid(mouse.winid) then
    return nil
  end
  local bufnr = vim.api.nvim_win_get_buf(mouse.winid)
  local scope = state.config.hover.mouse_scope
  local row = mouse.line and mouse.line > 0 and (mouse.line - 1) or nil
  if scope == "line" then
    return row and target_at(bufnr, row, mouse.winid, "mouse") or nil
  end

  if (scope == "diagnostic" or scope == "code") and row then
    local col = mouse.column and math.max(0, mouse.column - 1) or -1
    if col >= 0 then
      local matches = diagnostics_at(bufnr, row, col)
      if matches[1] then
        return target_at(bufnr, row, mouse.winid, "mouse", matches[1])
      end
    end
  end

  if scope == "diagnostic" or scope == "preview" then
    local layout = preview_layout_at(bufnr, mouse.winid, mouse)
    if layout then
      return target_at(bufnr, layout.row, mouse.winid, "mouse")
    end
  end
  return nil
end

local function current_target_for(input)
  if input == "mouse" then
    return mouse_target()
  end
  return cursor_target()
end

local function input_enabled(input)
  local mode = state.config.hover.input_mode
  if mode == nil then
    mode = state.config.hover.use_mouse and "mouse" or "cursor"
  end
  return mode == "both" or mode == input
end

local function target_with_fallback(input)
  local target = current_target_for(input)
  if target then
    return target
  end
  local fallback = input == "mouse" and "cursor" or "mouse"
  if input_enabled(fallback) then
    return current_target_for(fallback)
  end
  return nil
end

local function diagnostics_for_target(target, layout)
  local grouping = state.config.hover.group_by or "line"
  if grouping == "range" and target.diagnostic_key then
    for _, diagnostic in ipairs(layout.diagnostics or {}) do
      if diagnostic_key(diagnostic) == target.diagnostic_key then
        return { diagnostic }
      end
    end
    return {}
  end
  if grouping ~= "block" then
    return layout.diagnostics or {}
  end
  if type(renderer.diagnostics_in_group) == "function" then
    return renderer.diagnostics_in_group(target.bufnr, layout.group_id)
  end

  local entries = {}
  for _, candidate in pairs(state.layouts[target.bufnr] or {}) do
    if candidate.group_id == layout.group_id then
      table.insert(entries, candidate)
    end
  end
  table.sort(entries, function(left, right)
    return left.row < right.row
  end)
  local diagnostics = {}
  for _, entry in ipairs(entries) do
    vim.list_extend(diagnostics, entry.diagnostics or {})
  end
  return util.sort_diagnostics(diagnostics)
end

local function placement_layout(layout, diagnostics)
  if diagnostics == layout.diagnostics then
    return layout
  end
  local copy = {}
  for key, value in pairs(layout) do
    copy[key] = value
  end
  copy.diagnostics = diagnostics
  return copy
end

local function cancel_timer()
  local hover = state.hover
  local timer = hover.timer
  hover.timer = nil
  if not timer then
    return
  end
  pcall(function()
    timer:stop()
  end)
  pcall(function()
    if not timer:is_closing() then
      timer:close()
    end
  end)
end

local function close_float()
  local hover = state.hover
  local target = hover.target
  local float_win = hover.win
  local float_buf = hover.buf
  cancel_timer()

  hover.win = nil
  hover.buf = nil
  hover.source_win = nil
  hover.source_buf = nil
  hover.source_line = nil
  hover.target = nil
  hover.pending_target = nil
  hover.pinned = false
  hover.bounds = nil
  hover.geometry = nil
  hover.placement = nil

  -- Closing a bufhidden=wipe surface emits BufWipeout synchronously. Mark it
  -- as owned/closing so that event cannot be mistaken for a source buffer
  -- change and re-arm this hover.
  hover.closing = true
  hover.owned_buffers = hover.owned_buffers or {}
  if float_buf then
    hover.owned_buffers[float_buf] = true
  end
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    pcall(vim.api.nvim_win_close, float_win, true)
  end
  if float_buf and vim.api.nvim_buf_is_valid(float_buf) then
    pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
  end
  if float_buf then
    hover.owned_buffers[float_buf] = nil
  end
  hover.closing = false
  if target then
    renderer.clear_active_range(target.bufnr)
    renderer.update_hover(target.bufnr)
  end
end

local function quoted_ranges(text, start_col, end_col)
  local ranges = {}
  local open_quote = nil
  local open_index = nil
  local escaped = false
  for index = start_col + 1, end_col do
    local character = text:sub(index, index)
    local apostrophe = character == "'"
      and text:sub(index - 1, index - 1):match("[%w_]")
      and text:sub(index + 1, index + 1):match("[%w_]")
    if open_quote then
      if escaped then
        escaped = false
      elseif character == "\\" then
        escaped = true
      elseif character == open_quote and not apostrophe then
        table.insert(ranges, { open_index - 1, index })
        open_quote = nil
        open_index = nil
      end
    elseif (character == '"' or character == "'" or character == "`") and not apostrophe then
      open_quote = character
      open_index = index
    end
  end
  return ranges
end

local function apply_line_highlights(float_buf, lines, geometry, target, layout)
  local border_offset = has_border(state.config.hover.border) and 1 or 0
  for index, line in ipairs(lines) do
    local row = index - 1
    local severity_key = util.severity_key(line.severity)
    vim.api.nvim_buf_add_highlight(
      float_buf,
      M.namespace,
      "AlignedDiagnosticFloatBody" .. severity_key,
      row,
      line.body_start,
      line.body_end
    )
    if line.left_edge_end > 0 then
      local left_edge_group = highlights.edge_group("hover", severity_key, false, {
        source_win = target.source_win,
        bufnr = target.bufnr,
        row = layout.row,
        float_row = row,
        screen_row = geometry.row + border_offset + row + 1,
        screen_column = geometry.col + border_offset + 1,
        side = "left",
        virtual_column = geometry.virtual_column,
      })
      vim.api.nvim_buf_add_highlight(
        float_buf,
        M.namespace,
        left_edge_group,
        row,
        0,
        line.left_edge_end
      )
    end
    if line.right_edge_start < #line.text then
      local right_virtual_column = geometry.virtual_column
          and (geometry.virtual_column + geometry.width - line.right_edge_width)
        or nil
      local right_edge_group = highlights.edge_group("hover", severity_key, false, {
        source_win = target.source_win,
        bufnr = target.bufnr,
        row = layout.row,
        float_row = row,
        screen_row = geometry.row + border_offset + row + 1,
        screen_column = geometry.col + border_offset + geometry.width - line.right_edge_width + 1,
        side = "right",
        virtual_column = right_virtual_column,
      })
      vim.api.nvim_buf_add_highlight(
        float_buf,
        M.namespace,
        right_edge_group,
        row,
        line.right_edge_start,
        -1
      )
    end
    if line.prefix_end > line.prefix_start then
      vim.api.nvim_buf_add_highlight(
        float_buf,
        M.namespace,
        "AlignedDiagnosticHover" .. severity_key,
        row,
        line.prefix_start,
        line.prefix_end
      )
    end

    local role_group = line.role == "metadata" and "AlignedDiagnosticFloatMetadata"
      or (line.role == "detail" and "AlignedDiagnosticFloatDetail")
      or "AlignedDiagnosticFloatMessage"
    if line.content_end > line.content_start then
      vim.api.nvim_buf_add_highlight(
        float_buf,
        M.namespace,
        role_group .. severity_key,
        row,
        line.content_start,
        line.content_end
      )
      if state.config.hover.highlight_tokens and line.role ~= "metadata" then
        for _, range in ipairs(quoted_ranges(line.text, line.content_start, line.content_end)) do
          vim.api.nvim_buf_add_highlight(
            float_buf,
            M.namespace,
            "AlignedDiagnosticFloatCode" .. severity_key,
            row,
            range[1],
            range[2]
          )
        end
      end
    end
  end
end

local function surface_config(geometry)
  local options = state.config.hover
  return {
    relative = "editor",
    row = geometry.row,
    col = geometry.col,
    width = geometry.width,
    height = geometry.height,
    style = "minimal",
    border = options.border,
    focusable = state.hover.pinned == true,
    zindex = options.zindex,
  }
end

local function write_surface(float_buf, geometry, target, layout)
  local text = {}
  for _, line in ipairs(geometry.lines) do
    table.insert(text, line.text)
  end
  vim.api.nvim_set_option_value("modifiable", true, { buf = float_buf })
  vim.api.nvim_buf_clear_namespace(float_buf, M.namespace, 0, -1)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, text)
  apply_line_highlights(float_buf, geometry.lines, geometry, target, layout)
  vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
end

local function configure_surface_window(float_win)
  local options = state.config.hover
  vim.api.nvim_set_option_value("wrap", false, { win = float_win })
  vim.api.nvim_set_option_value("winblend", options.winblend, { win = float_win })
  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:AlignedDiagnosticFloat,FloatBorder:AlignedDiagnosticBorder",
    { win = float_win }
  )
end

local function commit_surface(float_win, float_buf, target, layout, active_layout, geometry)
  local hover = state.hover
  local options = state.config.hover
  hover.win = float_win
  hover.buf = float_buf
  hover.source_win = target.source_win
  hover.source_buf = target.bufnr
  hover.source_line = layout.row
  hover.target = target
  local border_cells = has_border(options.border) and 2 or 0
  hover.bounds = {
    top = geometry.row,
    bottom = geometry.row + geometry.height + border_cells,
    left = geometry.col,
    right = geometry.col + geometry.width + border_cells,
  }
  hover.geometry = {
    kind = geometry.kind,
    row = geometry.row,
    col = geometry.col,
    width = geometry.width,
    height = geometry.height,
    window_left = geometry.window_left,
    window_right = geometry.window_right,
  }
  hover.placement = geometry.kind
  hover.pending_target = nil
  renderer.update_hover(target.bufnr)
  renderer.show_active_range(target.bufnr, active_layout)
end

local function open_target(target, force, refresh_options)
  local hover = state.hover
  if
    not force
    and targets_equal(hover.target, target)
    and hover.win
    and vim.api.nvim_win_is_valid(hover.win)
  then
    return hover.win
  end

  local layout = renderer.get_layout(target.bufnr, target.layout_row)
    or renderer.find_layout(target.bufnr, target.row)
  if not layout then
    close_float()
    return nil
  end
  local diagnostics = diagnostics_for_target(target, layout)
  if #diagnostics == 0 then
    close_float()
    return nil
  end
  -- Geometry and active-range highlighting must cover every diagnostic the
  -- float represents, including block grouping—not only the selected line.
  local active_layout = placement_layout(layout, diagnostics)
  local models = models_for(diagnostics, {
    bufnr = target.bufnr,
    winid = target.source_win,
    row = target.row,
    layout_row = layout.row,
    input = target.input,
    group_by = state.config.hover.group_by,
    target = target.diagnostic,
  })
  local stable_geometry = refresh_options
      and refresh_options.preserve_geometry
      and state.config.hover.placement.preserve_anchor
      and targets_equal(hover.target, target)
      and hover.geometry
    or nil
  local geometry =
    choose_geometry(target.source_win, active_layout, target.row, models, stable_geometry)
  if not geometry then
    close_float()
    return nil
  end

  local can_reuse = targets_equal(hover.target, target)
    and hover.win
    and vim.api.nvim_win_is_valid(hover.win)
    and hover.buf
    and vim.api.nvim_buf_is_valid(hover.buf)
  if can_reuse then
    local ok = pcall(function()
      write_surface(hover.buf, geometry, target, active_layout)
      vim.api.nvim_win_set_config(hover.win, surface_config(geometry))
      configure_surface_window(hover.win)
    end)
    if ok then
      commit_surface(hover.win, hover.buf, target, layout, active_layout, geometry)
      return hover.win
    end
  end

  close_float()
  local float_buf
  local float_win
  local ok, failure = xpcall(function()
    float_buf = vim.api.nvim_create_buf(false, true)
    hover.owned_buffers = hover.owned_buffers or {}
    hover.owned_buffers[float_buf] = true
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = float_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = float_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = float_buf })
    vim.api.nvim_set_option_value("filetype", "aligned-diagnostic", { buf = float_buf })
    vim.keymap.set("n", "q", M.close, { buffer = float_buf, silent = true, nowait = true })
    vim.keymap.set("n", "<Esc>", M.unpin, { buffer = float_buf, silent = true, nowait = true })
    write_surface(float_buf, geometry, target, active_layout)

    local window_config = surface_config(geometry)
    window_config.noautocmd = true
    float_win = vim.api.nvim_open_win(float_buf, false, window_config)
    configure_surface_window(float_win)
  end, debug.traceback)
  if not ok then
    hover.closing = true
    if float_win and vim.api.nvim_win_is_valid(float_win) then
      pcall(vim.api.nvim_win_close, float_win, true)
    end
    if float_buf and vim.api.nvim_buf_is_valid(float_buf) then
      pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
    end
    if float_buf and hover.owned_buffers then
      hover.owned_buffers[float_buf] = nil
    end
    hover.closing = false
    hover.pending_target = nil
    notify_formatter("surface", failure)
    return nil
  end

  commit_surface(float_win, float_buf, target, layout, active_layout, geometry)
  return float_win
end

local function effective_delay()
  local configured = state.config.hover.delay_ms
  return configured == nil and vim.o.updatetime or configured
end

local function leave_target()
  local hover = state.hover
  hover.generation = hover.generation + 1
  hover.pending_target = nil
  close_float()
end

local function track(target)
  local hover = state.hover
  local sticky = state.config.hover.sticky

  if not target then
    if hover.target or hover.pending_target then
      leave_target()
    end
    return
  end
  if sticky and targets_equal(hover.target, target) then
    -- Both inputs can keep the same target alive without restarting its
    -- timer. Remember the input that most recently confirmed the target so
    -- refreshes validate against the right position.
    hover.target.input = target.input
    return
  end
  if sticky and targets_equal(hover.pending_target, target) then
    hover.pending_target.input = target.input
    return
  end

  close_float()
  hover.generation = hover.generation + 1
  local generation = hover.generation
  local lifecycle_epoch = state.lifecycle_epoch
  hover.pending_target = target

  local function try_open()
    state.hover.timer = nil
    if
      state.hover.generation ~= generation
      or state.lifecycle_epoch ~= lifecycle_epoch
      or not state.enabled
    then
      return
    end
    local current = current_target_for(target.input)
    if not targets_equal(current, target) then
      if state.hover.generation == generation then
        state.hover.pending_target = nil
      end
      return
    end
    open_target(current)
  end

  local delay = effective_delay()
  if delay <= 0 then
    try_open()
  else
    hover.timer = vim.defer_fn(try_open, delay)
  end
end

function M.close()
  state.hover.pinned = false
  leave_target()
end

function M.pin()
  if not state.enabled or not state.config.hover.enabled then
    return nil
  end
  if not state.hover.target then
    M.open_current()
  end
  local target = state.hover.target
  if not target then
    return nil
  end
  state.hover.pinned = true
  local float_win = open_target(target, true)
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    pcall(vim.api.nvim_set_current_win, float_win)
  end
  return float_win
end

function M.unpin()
  local hover = state.hover
  if not hover.pinned then
    return hover.win
  end
  local source_win = hover.source_win
  local target = hover.target
  if
    hover.win
    and vim.api.nvim_win_is_valid(hover.win)
    and vim.api.nvim_get_current_win() == hover.win
    and source_win
    and vim.api.nvim_win_is_valid(source_win)
  then
    pcall(vim.api.nvim_set_current_win, source_win)
  end
  hover.pinned = false
  return target and open_target(target, true) or nil
end

function M.on_leave()
  if state.hover.closing or state.hover.pinned then
    return
  end
  M.close({ passive = true })
end

function M.open(bufnr, row, source_win)
  if not state.enabled or not state.config.hover.enabled then
    return nil
  end
  local target = target_at(bufnr, row, source_win, "cursor")
  if not target then
    M.close({ passive = true })
    return nil
  end
  cancel_timer()
  state.hover.generation = state.hover.generation + 1
  state.hover.pending_target = nil
  return open_target(target)
end

function M.open_current()
  if not state.enabled or not state.config.hover.enabled then
    return nil
  end
  local target = cursor_target()
  if not target then
    M.close({ passive = true })
    return nil
  end
  cancel_timer()
  state.hover.generation = state.hover.generation + 1
  state.hover.pending_target = nil
  return open_target(target)
end

function M.track_current()
  if
    state.hover.pinned
    or not state.enabled
    or not state.config.hover.enabled
    or not input_enabled("cursor")
  then
    return
  end
  -- A non-focusable float lets clicks pass through to the source buffer. If
  -- that source cell belongs to another diagnostic, CursorMoved would
  -- otherwise replace the surface under the pointer and make it appear to
  -- jump or resize. The mouse keeps ownership until it actually leaves the
  -- expanded surface; the cursor target takes over on the following move.
  if
    input_enabled("mouse")
    and state.hover.target
    and state.hover.target.input == "mouse"
    and mouse_over_open_surface(vim.fn.getmousepos())
  then
    local cursor = cursor_target()
    if targets_equal(cursor, state.hover.target) then
      track(cursor)
    else
      track(state.hover.target)
    end
    return
  end
  track(target_with_fallback("cursor"))
end

function M.track_mouse()
  if
    state.hover.pinned
    or not state.enabled
    or not state.config.hover.enabled
    or not input_enabled("mouse")
  then
    return
  end
  track(target_with_fallback("mouse"))
end

function M.uses_cursor()
  return input_enabled("cursor")
end

function M.uses_mouse()
  return input_enabled("mouse")
end

function M.track_active()
  if state.hover.pinned or not state.enabled or not state.config.hover.enabled then
    return
  end
  if input_enabled("cursor") then
    track(target_with_fallback("cursor"))
  elseif input_enabled("mouse") then
    track(mouse_target())
  end
end

function M.refresh(options)
  local target = state.hover.target
  if target then
    if state.hover.pinned then
      if
        vim.api.nvim_win_is_valid(target.source_win)
        and vim.api.nvim_win_get_buf(target.source_win) == target.bufnr
        and renderer.get_layout(target.bufnr, target.layout_row)
      then
        open_target(target, true, options)
      else
        M.close({ passive = true })
      end
      return
    end
    local current = target_with_fallback(target.input)
    if targets_equal(current, target) then
      open_target(current, true, options)
      return
    end
    M.close({ passive = true })
    return
  end

  local pending = state.hover.pending_target
  if pending and not targets_equal(target_with_fallback(pending.input), pending) then
    M.close({ passive = true })
  end
end

function M.reconcile()
  if not state.enabled or not state.config.hover.enabled then
    M.close({ passive = true })
    return
  end
  local target = state.hover.target or state.hover.pending_target
  if not target then
    M.track_active()
    return
  end
  if state.hover.pinned and state.hover.target then
    M.refresh()
    return
  end
  local current = target_with_fallback(target.input)
  if targets_equal(current, target) then
    if state.hover.target then
      open_target(current, true)
    else
      track(current)
    end
  else
    M.close({ passive = true })
  end
end

return M
