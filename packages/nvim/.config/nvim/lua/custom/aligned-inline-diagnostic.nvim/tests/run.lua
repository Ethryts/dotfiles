local function project_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h")
end

local function assert_equal(expected, actual, message)
  if expected ~= actual then
    error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_truthy(value, message)
  if not value then
    error(message)
  end
end

local function assert_raises(callback, message)
  local ok = pcall(callback)
  if ok then
    error(message)
  end
end

local function drain_events(milliseconds)
  vim.wait(milliseconds or 30, function()
    return false
  end, 1)
end

local function chunk_has_highlight(chunk, expected)
  local highlight = chunk[2]
  if highlight == expected then
    return true
  end
  if type(highlight) == "table" then
    for _, name in ipairs(highlight) do
      if name == expected then
        return true
      end
    end
  end
  return false
end

local function virtual_text(mark)
  local text = ""
  for _, chunk in ipairs(mark[4].virt_text or {}) do
    text = text .. chunk[1]
  end
  return text
end

local function find_chunk(chunks, text)
  for _, chunk in ipairs(chunks or {}) do
    if chunk[1] == text then
      return chunk
    end
  end
  return nil
end

local function find_mark(marks, row)
  for _, mark in ipairs(marks) do
    if mark[2] == row then
      return mark
    end
  end
  return nil
end

local function run()
  vim.opt.runtimepath:prepend(project_root())
  vim.o.columns = 120
  vim.o.lines = 40

  local plugin = require("aligned-inline-diagnostic")
  local config = require("aligned-inline-diagnostic.config")
  local highlights = require("aligned-inline-diagnostic.highlights")
  local hover = require("aligned-inline-diagnostic.hover")
  local renderer = require("aligned-inline-diagnostic.renderer")
  local state = require("aligned-inline-diagnostic.state")
  local util = require("aligned-inline-diagnostic.util")

  assert_raises(function()
    plugin.enable()
  end, "enable before setup should fail with a clear setup requirement")

  assert_equal(
    "mouse",
    config.resolve({ hover = { use_mouse = true } }).hover.input_mode,
    "legacy use_mouse=true should retain mouse-only behavior"
  )
  assert_equal(
    "both",
    config.resolve({ hover = { input_mode = "both", use_mouse = true } }).hover.input_mode,
    "input_mode should take precedence over use_mouse"
  )
  assert_truthy(
    not pcall(config.resolve, { hover = { input_mode = "touch" } }),
    "invalid input modes should be rejected"
  )
  assert_truthy(
    config.resolve().hover.placement.preserve_anchor,
    "expanded diagnostics should preserve their preview anchor by default"
  )
  assert_truthy(
    config.resolve().hover.match_preview_width,
    "expanded diagnostics should match their rendered preview width by default"
  )
  assert_equal(3, config.resolve().alignment.padding, "default source spacing should be readable")
  assert_truthy(
    config.resolve().alignment.include_range_width,
    "short multiline ranges should contribute to alignment by default"
  )
  assert_equal(
    4,
    config.resolve({ preview = { max_width = 4 } }).preview.max_width,
    "width matching should remain best-effort for existing compact preview configurations"
  )
  assert_truthy(
    not pcall(config.resolve, { hover = { placement = { preserve_anchor = "yes" } } }),
    "preserve_anchor should require a boolean"
  )
  assert_truthy(
    config.resolve().appearance.edge_underlay.combine,
    "preview edges should combine with native window highlights by default"
  )
  assert_truthy(
    not pcall(config.resolve, { appearance = { edge_underlay = { resolve = "invalid" } } }),
    "edge underlay resolvers should require a function"
  )

  local invalid_configs = {
    { { enabled = "yes" }, "enabled should require a boolean" },
    {
      { disable_default_virtual_text = "yes" },
      "disable_default_virtual_text should require a boolean",
    },
    { { throttle_ms = 0.5 }, "throttle_ms should require an integer" },
    { { priority = "high" }, "priority should require an integer" },
    {
      { alignment = { include_range_width = "yes" } },
      "alignment.include_range_width should require a boolean",
    },
    {
      { alignment = { max_range_lines = 0 } },
      "alignment.max_range_lines should require a positive integer",
    },
    { { disabled_filetypes = "help" }, "disabled_filetypes should require a list" },
    {
      { disabled_filetypes = { "help", 42 } },
      "disabled_filetypes entries should require strings",
    },
    { { hover = { row_offset = 0.5 } }, "hover.row_offset should require an integer" },
    { { hover = { col_offset = "0" } }, "hover.col_offset should require an integer" },
    {
      { hover = { match_preview_width = "yes" } },
      "hover.match_preview_width should require a boolean",
    },
    { { hover = { border = 42 } }, "hover.border should reject unsupported values" },
    { { highlights = "Normal" }, "highlights should require a table" },
    {
      { highlights = { AlignedDiagnosticFloatBody = 42 } },
      "highlight overrides should require a spec or link",
    },
    {
      { highlights = { TestHighlight = { fg = {} } } },
      "highlight foregrounds should require a color",
    },
    {
      { highlights = { TestHighlight = { bg = false } } },
      "highlight backgrounds should require a color",
    },
    {
      { highlights = { TestHighlight = { sp = function() end } } },
      "highlight special colors should require a color",
    },
    {
      { highlights = { TestHighlight = { blend = "20" } } },
      "highlight blend should require an integer percentage",
    },
    {
      { highlights = { TestHighlight = { bold = "yes" } } },
      "highlight style attributes should require booleans",
    },
    {
      { highlights = { TestHighlight = { link = { "NormalFloat" } } } },
      "highlight links should require group names",
    },
    {
      { highlights = { TestHighlight = { bg = "Normal" } } },
      "raw highlight colors should not accept highlight-group names",
    },
    {
      { hover = { min_width = 1, preferred_width = 5, max_width = 5 } },
      "hover.max_width should fit configured edges and glyph lanes",
    },
    {
      {
        hover = { min_width = 8, preferred_width = 8, max_width = 8 },
        icons = { related = "RELATED" },
      },
      "custom related glyph widths should contribute to the structural minimum",
    },
    { { preview = { ellipsis = ".\n" } }, "preview.ellipsis should be one line" },
    { { icons = { error = "E\n" } }, "icons should be one line" },
  }
  for _, case in ipairs(invalid_configs) do
    assert_raises(function()
      config.resolve(case[1])
    end, case[2])
  end

  local valid_config = config.resolve({
    disabled_filetypes = { "help", "qf" },
    hover = {
      row_offset = -1,
      col_offset = 2,
      border = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
    },
    highlights = {
      AlignedDiagnosticFloatBody = "NormalFloat",
      AlignedDiagnosticPreviewBody = {
        fg = "#f0e0d0",
        bg = 0x202020,
        sp = "#ff8080",
        blend = 20,
        bold = true,
        italic = false,
        undercurl = true,
        nocombine = false,
      },
      AlignedDiagnosticPreviewIcon = { fg = "Red" },
      AlignedDiagnosticMetadata = { link = "Comment", default = true },
    },
  })
  assert_equal(-1, valid_config.hover.row_offset, "signed row offsets should be supported")
  assert_equal(2, valid_config.hover.col_offset, "signed column offsets should be supported")

  local balanced = util.wrap("alpha beta gamma delta", 16, "balanced")
  assert_truthy(
    #balanced == 2 and balanced[1] == "alpha beta" and balanced[2] == "gamma delta",
    "balanced wrapping should avoid an orphan"
  )

  local cut_cases = {
    { text = "abcdef", width = 3, prefix = "abc", suffix = "def" },
    { text = "éclair", width = 2, prefix = "éc", suffix = "lair" },
    { text = "界x", width = 2, prefix = "界", suffix = "x" },
  }
  for _, case in ipairs(cut_cases) do
    local prefix, suffix = util.cut_cells(case.text, case.width)
    assert_equal(case.prefix, prefix, "cut_cells should preserve complete display characters")
    assert_equal(case.suffix, suffix, "cut_cells should return the unconsumed suffix")
    assert_equal(case.text, prefix .. suffix, "cut_cells should never lose text")
    assert_truthy(
      util.display_width(prefix) <= case.width,
      "cut_cells prefixes should respect the requested cell width"
    )
  end
  assert_equal("abc…", util.truncate("abcdef", 4, "…"), "truncate should budget for ellipsis")

  for _, line in ipairs(util.wrap("alpha betagamma 界 delta", 7, "greedy")) do
    assert_truthy(
      util.display_width(line) <= 7,
      "wrapped lines should remain within their cell budget"
    )
  end

  local outer_diagnostic = {
    lnum = 0,
    col = 2,
    end_lnum = 2,
    end_col = 3,
    severity = vim.diagnostic.severity.ERROR,
    message = "outer",
  }
  local inner_diagnostic = {
    lnum = 1,
    col = 5,
    end_lnum = 1,
    end_col = 8,
    severity = vim.diagnostic.severity.WARN,
    message = "inner",
  }
  assert_truthy(
    not renderer.diagnostic_contains(outer_diagnostic, 0, 1),
    "diagnostic hit tests should respect the start column"
  )
  assert_truthy(
    renderer.diagnostic_contains(outer_diagnostic, 0, 2),
    "diagnostic hit tests should include the start column"
  )
  assert_truthy(
    renderer.diagnostic_contains(outer_diagnostic, 2, 2),
    "diagnostic hit tests should include cells before the end column"
  )
  assert_truthy(
    not renderer.diagnostic_contains(outer_diagnostic, 2, 3),
    "diagnostic hit tests should treat the end column as exclusive"
  )
  assert_truthy(
    not renderer.diagnostic_contains({ lnum = 0, col = 2, end_lnum = 1, end_col = 0 }, 1),
    "a multiline range ending at column zero should not cover its end row"
  )

  local synthetic_bufnr = -1000
  state.layouts[synthetic_bufnr] = {
    [0] = { row = 0, diagnostics = { outer_diagnostic } },
    [1] = { row = 1, diagnostics = { inner_diagnostic } },
  }
  local outer_only = renderer.diagnostic_matches_at(synthetic_bufnr, 1, 1)
  assert_equal(1, #outer_only, "a nearer start row must not mask an outer multiline range")
  assert_equal(
    "outer",
    outer_only[1].diagnostic.message,
    "the spanning diagnostic should be returned"
  )
  local both_matches = renderer.diagnostic_matches_at(synthetic_bufnr, 1, 6)
  assert_equal(2, #both_matches, "overlapping ranges should both remain targetable")
  state.layouts[synthetic_bufnr] = nil

  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "local short = missing_name",
    "  ",
    "if short then",
    "  print(another_missing_name)",
    "end",
  })

  local namespace = vim.api.nvim_create_namespace("aligned-inline-diagnostic-test-source")
  vim.diagnostic.set(namespace, bufnr, {
    {
      lnum = 0,
      col = 14,
      end_lnum = 1,
      end_col = 2,
      severity = vim.diagnostic.severity.ERROR,
      source = "testls",
      code = "E001",
      message = "This is a deliberately long primary diagnostic that must wrap inside the hover window",
      user_data = {
        lsp = {
          relatedInformation = {
            {
              message = "Declared over here",
              location = {
                uri = vim.uri_from_fname("/tmp/related.lua"),
                range = { start = { line = 4, character = 0 } },
              },
            },
          },
        },
      },
    },
    {
      lnum = 0,
      col = 6,
      severity = vim.diagnostic.severity.WARN,
      source = "testls",
      code = "W002",
      message = "A second diagnostic on the same line",
    },
    {
      lnum = 3,
      col = 8,
      severity = vim.diagnostic.severity.ERROR,
      source = "testls",
      code = "E003",
      message = "Another missing name",
    },
  })

  local colorcolumn_background = 0x313641
  local overflow_background = 0x191c24
  vim.api.nvim_set_hl(0, "ColorColumn", { bg = colorcolumn_background })
  vim.api.nvim_set_hl(0, "PastColorColumn", { bg = overflow_background })
  vim.wo.colorcolumn = "38"

  plugin.setup({
    throttle_ms = 0,
    disable_default_virtual_text = true,
    alignment = {
      mode = "block",
      min_col = 36,
      max_gap = 4,
    },
    preview = {
      max_width = 28,
    },
    hover = {
      min_width = 24,
      max_width = 38,
      max_height = 16,
    },
  })
  assert_equal(
    38,
    state.config.hover.preferred_width,
    "legacy max_width overrides should clamp the default preferred width"
  )

  -- Clearing and rescheduling must not let an older delayed callback match a
  -- reused per-buffer generation number.
  local original_throttle = state.config.throttle_ms
  local original_render = renderer.render
  local delayed_render_calls = 0
  renderer.render = function(target_bufnr)
    if target_bufnr == bufnr then
      delayed_render_calls = delayed_render_calls + 1
    end
  end
  state.config.throttle_ms = 25
  renderer.schedule(bufnr)
  renderer.clear(bufnr)
  renderer.schedule(bufnr)
  drain_events(60)
  renderer.render = original_render
  state.config.throttle_ms = original_throttle
  assert_equal(1, delayed_render_calls, "only the newest delayed render generation should run")

  plugin.refresh(bufnr)

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, { details = true })
  assert_equal(2, #marks, "one preview should be rendered for each diagnostic line")
  table.sort(marks, function(left, right)
    return left[2] < right[2]
  end)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local function preview_anchor(mark)
    local chunks = mark[4].virt_text
    local padding = chunks[1][1]
    return vim.fn.strdisplaywidth(lines[mark[2] + 1]) + vim.fn.strdisplaywidth(padding)
  end

  assert_equal(preview_anchor(marks[1]), preview_anchor(marks[2]), "block previews should align")
  local first_preview = virtual_text(marks[1])
  assert_truthy(first_preview:find("+1", 1, true), "same-line diagnostic count should be shown")
  assert_truthy(first_preview:find("…", 1, true), "long preview should be truncated")

  local function preview_end(mark)
    return vim.fn.strdisplaywidth(lines[mark[2] + 1]) + vim.fn.strdisplaywidth(virtual_text(mark))
  end

  assert_equal(
    preview_end(marks[1]),
    preview_end(marks[2]),
    "block previews should share a stable right edge"
  )

  local count_chunk = nil
  for _, chunk in ipairs(marks[1][4].virt_text) do
    if chunk[1] == "+1" then
      count_chunk = chunk
      break
    end
  end
  assert_truthy(count_chunk, "the compact preview should reserve a distinct count chunk")
  assert_truthy(
    chunk_has_highlight(count_chunk, "AlignedDiagnosticPreviewCountError"),
    "the right-aligned count should use the preview count role"
  )

  local left_cap_chunk = find_chunk(marks[1][4].virt_text, state.config.icons.left)
  local right_cap_chunk = find_chunk(marks[1][4].virt_text, state.config.icons.right)
  assert_truthy(left_cap_chunk and right_cap_chunk, "preview should expose both edge chunks")
  assert_equal(
    "AlignedDiagnosticCapError",
    left_cap_chunk[2],
    "native ColorColumn should flow through the combined preview edge"
  )
  local left_cap_spec = vim.api.nvim_get_hl(0, { name = left_cap_chunk[2], link = false })
  assert_truthy(
    left_cap_spec.bg == nil,
    "combined preview caps should not force a canvas background"
  )
  local right_cap_spec = vim.api.nvim_get_hl(0, { name = right_cap_chunk[2], link = false })
  assert_equal(
    overflow_background,
    right_cap_spec.bg,
    "preview edges past colorcolumn should use the configured overflow background"
  )

  local original_count_format = state.config.preview.count_format
  state.config.preview.count_format = function()
    return "custom\ncount"
  end
  plugin.refresh(bufnr)
  local formatted_marks =
    vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, { details = true })
  local formatted_preview = virtual_text(assert(find_mark(formatted_marks, 0)))
  assert_truthy(
    formatted_preview:find("custom count", 1, true),
    "count_format output should remain visible after sanitization"
  )
  assert_truthy(
    not formatted_preview:find("\n", 1, true),
    "count_format must not inject newlines into virtual text"
  )
  state.config.preview.count_format = original_count_format
  plugin.refresh(bufnr)

  local hover_colorcolumn_edge = highlights.edge_group("hover", "Error", false, {
    source_win = vim.api.nvim_get_current_win(),
    virtual_column = 38,
    side = "left",
  })
  local hover_overflow_edge = highlights.edge_group("hover", "Error", false, {
    source_win = vim.api.nvim_get_current_win(),
    virtual_column = 39,
    side = "right",
  })
  assert_equal(
    colorcolumn_background,
    vim.api.nvim_get_hl(0, { name = hover_colorcolumn_edge, link = false }).bg,
    "float edge lanes should resolve ColorColumn explicitly"
  )
  assert_equal(
    overflow_background,
    vim.api.nvim_get_hl(0, { name = hover_overflow_edge, link = false }).bg,
    "float edge lanes should resolve overflow backgrounds explicitly"
  )

  local saved_colorcolumn = vim.wo.colorcolumn
  local saved_textwidth = vim.bo.textwidth
  vim.bo.textwidth = 0
  vim.wo.colorcolumn = "+1"
  highlights.setup(state.config)
  local ignored_relative_edge = highlights.edge_group("hover", "Error", false, {
    source_win = vim.api.nvim_get_current_win(),
    virtual_column = 38,
    side = "right",
  })
  assert_truthy(
    vim.api.nvim_get_hl(0, { name = ignored_relative_edge, link = false }).bg ~= overflow_background,
    "relative colorcolumn entries should be ignored when textwidth is zero"
  )
  vim.bo.textwidth = saved_textwidth
  vim.wo.colorcolumn = saved_colorcolumn
  highlights.setup(state.config)

  local range_layout = renderer.find_layout(bufnr, 1)
  assert_truthy(
    range_layout and range_layout.row == 0,
    "multiline range should keep one hover target"
  )

  -- Opening from the continuation line should expand the diagnostic that
  -- started on the previous line.
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.fn.winrestview({ topline = 1 })
  local multiline_preview_bounds =
    renderer.preview_screen_bounds(vim.api.nvim_get_current_win(), range_layout)
  assert_truthy(multiline_preview_bounds, "multiline preview should expose an in-place anchor")
  local float_win = plugin.open()
  assert_truthy(float_win and vim.api.nvim_win_is_valid(float_win), "hover float should open")
  assert_truthy(
    renderer.get_layout(bufnr, 0).hidden,
    "expanded hover should hide its inline preview"
  )

  -- A valid surface should refresh in place. Closing or refreshing a
  -- plugin-owned scratch buffer must not feed back through BufWipeout and
  -- re-arm the hover.
  local original_float_buf = state.hover.buf
  vim.fn.winrestview({ topline = 1 })
  hover.refresh()
  local refreshed_win = state.hover.win
  local refreshed_buf = state.hover.buf
  assert_truthy(
    refreshed_win and vim.api.nvim_win_is_valid(refreshed_win),
    "hover refresh should leave a valid float"
  )
  assert_equal(float_win, refreshed_win, "hover refresh should preserve the window position")
  assert_equal(original_float_buf, refreshed_buf, "hover refresh should reuse its scratch buffer")
  drain_events(40)
  assert_equal(refreshed_win, state.hover.win, "hover refresh should remain stable")
  assert_equal(refreshed_buf, state.hover.buf, "hover refresh should not start a buffer-wipe loop")
  float_win = state.hover.win

  local open_marks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, {})
  assert_equal(1, #open_marks, "only the covered preview should be hidden")
  local float_lines = vim.api.nvim_buf_get_lines(state.hover.buf, 0, -1, false)
  local float_highlights =
    vim.api.nvim_buf_get_extmarks(state.hover.buf, hover.namespace, 0, -1, { details = true })
  local saw_colorcolumn_edge = false
  local saw_overflow_edge = false
  for _, mark in ipairs(float_highlights) do
    local group = mark[4].hl_group
    if group then
      local query = type(group) == "number" and { id = group, link = false }
        or { name = group, link = false }
      local background = vim.api.nvim_get_hl(0, query).bg
      saw_colorcolumn_edge = saw_colorcolumn_edge or background == colorcolumn_background
      saw_overflow_edge = saw_overflow_edge or background == overflow_background
    end
  end
  assert_truthy(saw_colorcolumn_edge, "expanded flat edges should use ColorColumn underlay")
  assert_truthy(saw_overflow_edge, "expanded flat edges should use overflow underlay")
  local expanded = table.concat(float_lines, "\n")
  local primary_message_position = expanded:find("This is a deliberately", 1, true)
  local primary_metadata_position = expanded:find("testls · E001", 1, true)
  assert_truthy(
    primary_message_position
      and primary_metadata_position
      and primary_message_position < primary_metadata_position,
    "the diagnostic message should appear before its metadata"
  )
  local secondary_message_position = expanded:find("A second diagnostic", 1, true)
  local secondary_metadata_position = expanded:find("W002", 1, true)
  assert_truthy(
    secondary_message_position
      and secondary_metadata_position
      and secondary_message_position < secondary_metadata_position,
    "each same-line diagnostic should retain message-first ordering"
  )
  local _, source_count = expanded:gsub("testls", "")
  assert_equal(1, source_count, "a repeated diagnostic source should be shown only once")
  assert_truthy(
    expanded:find("Declared over here", 1, true),
    "related information should be expanded"
  )

  local active_marks =
    vim.api.nvim_buf_get_extmarks(bufnr, renderer.active_namespace, 0, -1, { details = true })
  assert_equal(2, #active_marks, "all diagnostic ranges on the active line should be highlighted")
  local active_groups = {}
  for _, mark in ipairs(active_marks) do
    active_groups[mark[4].hl_group] = true
  end
  assert_truthy(
    active_groups.AlignedDiagnosticActiveRangeError,
    "the primary error range should use its severity highlight"
  )
  assert_truthy(
    active_groups.AlignedDiagnosticActiveRangeWarn,
    "the secondary warning range should use its severity highlight"
  )

  local dimmed_marks =
    vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, { details = true })
  local dimmed = find_mark(dimmed_marks, 3)
  assert_truthy(dimmed, "the inactive preview in the same block should remain visible")
  local dimmed_body = false
  for _, chunk in ipairs(dimmed[4].virt_text or {}) do
    if chunk_has_highlight(chunk, "AlignedDiagnosticInactiveBodyError") then
      dimmed_body = true
      break
    end
  end
  assert_truthy(dimmed_body, "nearby previews should use inactive role highlights while open")

  assert_equal(
    "right",
    state.hover.placement,
    "a visible multiline source range should expand beside its preview"
  )
  local float_config = vim.api.nvim_win_get_config(float_win)
  assert_equal(
    multiline_preview_bounds.row,
    float_config.row,
    "multiline expansion should retain the preview row"
  )
  assert_equal(
    multiline_preview_bounds.left,
    float_config.col,
    "multiline expansion should retain the preview column"
  )
  assert_truthy(float_config.width <= 38, "the float window must respect max_width")
  for _, line in ipairs(float_lines) do
    assert_equal(
      float_config.width,
      vim.fn.strdisplaywidth(line),
      "every hover row should fill the stable float width"
    )
  end
  assert_truthy(float_lines[1]:sub(1, #"") == "", "first hover line needs a left cap")
  assert_truthy(float_lines[1]:sub(-1) == " ", "first hover line should reserve a flat right edge")
  assert_truthy(
    float_lines[#float_lines]:sub(1, 1) == " ",
    "last hover line should reserve a flat left edge"
  )
  assert_truthy(
    float_lines[#float_lines]:sub(-#"") == "",
    "last hover line needs a right cap"
  )
  for index = 2, #float_lines - 1 do
    assert_truthy(
      float_lines[index]:sub(1, 1) == " " and float_lines[index]:sub(-1) == " ",
      "middle hover lines should have flat edges"
    )
  end

  plugin.close()
  local closed_generation = state.hover.generation
  drain_events(40)
  assert_truthy(not state.hover.win, "hover should close")
  assert_truthy(not state.hover.target, "closing should clear the open target")
  assert_truthy(not state.hover.pending_target, "closing should not re-arm from its own BufWipeout")
  assert_equal(
    closed_generation,
    state.hover.generation,
    "closing an owned float should not schedule another hover generation"
  )
  assert_truthy(
    not renderer.get_layout(bufnr, 0).hidden,
    "closing hover should restore its preview"
  )
  local restored_marks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, {})
  assert_equal(2, #restored_marks, "closing hover should restore all previews")

  local cleared_active_marks =
    vim.api.nvim_buf_get_extmarks(bufnr, renderer.active_namespace, 0, -1, {})
  assert_equal(0, #cleared_active_marks, "closing hover should clear active range highlights")

  local restored_details =
    vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, { details = true })
  local restored = find_mark(restored_details, 3)
  assert_truthy(restored, "the nearby preview should survive hover restoration")
  local restored_body = false
  local still_inactive = false
  for _, chunk in ipairs(restored[4].virt_text or {}) do
    restored_body = restored_body or chunk_has_highlight(chunk, "AlignedDiagnosticPreviewBodyError")
    still_inactive = still_inactive
      or chunk_has_highlight(chunk, "AlignedDiagnosticInactiveBodyError")
  end
  assert_truthy(restored_body, "closing hover should restore normal preview role highlights")
  assert_truthy(not still_inactive, "closing hover should remove inactive preview styling")

  local original_group_by = state.config.hover.group_by
  state.config.hover.group_by = "block"
  vim.api.nvim_win_set_cursor(0, { 4, 8 })
  vim.fn.winrestview({ topline = 1 })
  local block_float = plugin.open()
  assert_truthy(block_float, "block grouping should open an expanded surface")
  local block_text = table.concat(vim.api.nvim_buf_get_lines(state.hover.buf, 0, -1, false), "\n")
  assert_truthy(
    block_text:find("This is a deliberately", 1, true)
      and block_text:find("Another missing name", 1, true),
    "block grouping should include diagnostics from every preview in the block"
  )
  local block_active_marks =
    vim.api.nvim_buf_get_extmarks(bufnr, renderer.active_namespace, 0, -1, {})
  assert_equal(
    3,
    #block_active_marks,
    "block grouping should highlight every diagnostic represented by the float"
  )
  plugin.close()
  state.config.hover.group_by = original_group_by

  vim.api.nvim_win_set_cursor(0, { 4, 8 })
  local single_source_win = vim.api.nvim_get_current_win()
  local single_layout = renderer.get_layout(bufnr, 3)
  local single_preview_bounds = renderer.preview_screen_bounds(single_source_win, single_layout)
  assert_truthy(single_preview_bounds, "single-line preview should have an expansion anchor")
  local single_marks =
    vim.api.nvim_buf_get_extmarks(bufnr, renderer.namespace, 0, -1, { details = true })
  local single_mark = find_mark(single_marks, 3)
  assert_truthy(single_mark, "single-line preview should have a rendered extmark")
  local rendered_padding = 0
  local found_left_cap = false
  for _, chunk in ipairs(single_mark[4].virt_text or {}) do
    if chunk[1] == state.config.icons.left then
      found_left_cap = true
      break
    end
    rendered_padding = rendered_padding + util.display_width(chunk[1])
  end
  assert_truthy(found_left_cap, "single-line preview should expose its rendered left cap")
  local rendered_pill_width = util.display_width(virtual_text(single_mark)) - rendered_padding
  local single_line_text = vim.api.nvim_buf_get_lines(bufnr, 3, 4, false)[1]
  local last_character =
    vim.fn.strcharpart(single_line_text, vim.fn.strchars(single_line_text) - 1, 1)
  local last_byte_col = #single_line_text - #last_character + 1
  local endpoint = vim.fn.screenpos(single_source_win, 4, last_byte_col)
  local endpoint_right = endpoint.endcol > 0 and endpoint.endcol
    or (endpoint.col - 1 + util.display_width(last_character))
  local expected_preview_left = endpoint_right + 1 + rendered_padding
  assert_equal(
    expected_preview_left,
    single_preview_bounds.left,
    "preview bounds should begin after Neovim's dedicated EOL cell and alignment padding"
  )
  assert_equal(
    rendered_pill_width,
    single_preview_bounds.right - single_preview_bounds.left,
    "preview bounds should report the rendered pill width"
  )
  local single_line_float = plugin.open()
  assert_truthy(single_line_float, "a single-line diagnostic float should open")
  assert_equal("right", state.hover.placement, "a roomy single-line target should expand in place")
  assert_equal(
    rendered_pill_width,
    vim.api.nvim_win_get_config(single_line_float).width,
    "expanded hover should match the rendered preview width"
  )

  -- DiagnosticChanged can rebuild layouts while the active preview is
  -- hidden. That hidden entry must retain its measured pill width; otherwise
  -- a cursor refresh falls back to hover.preferred_width and becomes narrower
  -- than the equivalent mouse hover.
  renderer.render(bufnr)
  local rebuilt_hidden_layout = renderer.get_layout(bufnr, single_layout.row)
  assert_truthy(
    rebuilt_hidden_layout and rebuilt_hidden_layout.hidden,
    "an active preview should remain hidden after a full layout rebuild"
  )
  assert_equal(
    rendered_pill_width,
    rebuilt_hidden_layout.pill_width,
    "hidden previews should retain the canonical measured pill width"
  )
  hover.refresh()
  assert_equal(
    single_line_float,
    state.hover.win,
    "a rebuilt cursor hover should reuse its surface"
  )
  assert_equal(
    rendered_pill_width,
    vim.api.nvim_win_get_config(single_line_float).width,
    "a rebuilt cursor hover should remain the same width as its preview"
  )
  local stable_float_config = vim.api.nvim_win_get_config(single_line_float)
  local original_preview_screen_bounds = renderer.preview_screen_bounds
  local window_position = vim.api.nvim_win_get_position(single_source_win)
  local window_right = window_position[2]
    + vim.api.nvim_win_get_width(single_source_win)
    - state.config.hover.placement.edge_margin
  renderer.preview_screen_bounds = function(source_win, entry)
    local bounds = original_preview_screen_bounds(source_win, entry)
    if source_win ~= single_source_win or not bounds or entry.row ~= single_layout.row then
      return bounds
    end
    local shifted = vim.deepcopy(bounds)
    shifted.left = window_right - stable_float_config.width + 3
    shifted.right = shifted.left + rendered_pill_width
    return shifted
  end
  hover.refresh({ preserve_geometry = true })
  renderer.preview_screen_bounds = original_preview_screen_bounds
  local scrolled_float_config = vim.api.nvim_win_get_config(single_line_float)
  assert_equal(
    stable_float_config.col,
    scrolled_float_config.col,
    "scroll refresh should preserve an open hover's screen column"
  )
  assert_equal(
    stable_float_config.width,
    scrolled_float_config.width,
    "scroll refresh should preserve an open hover's width"
  )
  local pinned_float = plugin.pin()
  assert_equal(single_line_float, pinned_float, "pinning should reuse the expanded surface")
  assert_truthy(state.hover.pinned, "pinning should mark the hover as pinned")
  assert_equal(pinned_float, vim.api.nvim_get_current_win(), "pinning should focus the hover")
  local pinned_generation = state.hover.generation
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = bufnr })
  assert_equal(
    pinned_generation,
    state.hover.generation,
    "the regression setup should queue hover work before an explicit pinned close"
  )
  hover.on_leave()
  assert_truthy(
    vim.api.nvim_win_is_valid(pinned_float),
    "ordinary leave events should not close a pinned hover"
  )
  local q_mapping = nil
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(state.hover.buf, "n")) do
    if mapping.lhs == "q" then
      q_mapping = mapping
      break
    end
  end
  assert_truthy(q_mapping and type(q_mapping.callback) == "function", "pinned hover should map q")
  q_mapping.callback()
  drain_events(40)
  assert_truthy(not state.hover.win, "q should close a focused pinned hover")
  assert_truthy(
    not state.hover.pending_target,
    "the source WinEnter caused by closing a pinned hover must not re-arm it"
  )

  single_line_float = plugin.open()
  pinned_float = plugin.pin()
  assert_equal(
    single_line_float,
    pinned_float,
    "pinning should remain reusable after an explicit close"
  )
  local unpinned_float = plugin.unpin()
  assert_truthy(not state.hover.pinned, "unpinning should clear the pinned state")
  assert_equal(single_source_win, vim.api.nvim_get_current_win(), "unpinning should restore focus")
  assert_equal(pinned_float, unpinned_float, "unpinning should preserve the expanded surface")
  local single_float_config = vim.api.nvim_win_get_config(single_line_float)
  assert_equal(
    single_preview_bounds.row,
    single_float_config.row,
    "expanded hover should retain the preview row"
  )
  assert_equal(
    single_preview_bounds.left,
    single_float_config.col,
    "expanded hover should retain the preview column"
  )
  -- Let the source-window enter event caused by unpinning settle while the
  -- target is still open, so the following explicit close is the final state.
  drain_events(20)
  plugin.close()

  -- The fallback anchor calculation is separate from preview_screen_bounds().
  -- It must include the same EOL cell when in-place preservation is disabled.
  local original_preserve_anchor = state.config.hover.placement.preserve_anchor
  state.config.hover.placement.preserve_anchor = false
  local unpreserved_float = plugin.open()
  assert_truthy(unpreserved_float, "unpreserved right placement should still open")
  assert_equal(
    expected_preview_left,
    vim.api.nvim_win_get_config(unpreserved_float).col,
    "fallback right placement should use the same EOL-aware preview anchor"
  )
  plugin.close()
  state.config.hover.placement.preserve_anchor = original_preserve_anchor

  local original_match_preview_width = state.config.hover.match_preview_width
  local original_width_mode = state.config.hover.width_mode
  state.config.hover.match_preview_width = false
  state.config.hover.width_mode = "fixed"
  local independent_width_float = plugin.open()
  assert_truthy(independent_width_float, "independently sized hover should open")
  assert_equal(
    state.config.hover.max_width,
    vim.api.nvim_win_get_config(independent_width_float).width,
    "disabling width matching should restore hover.width_mode"
  )
  plugin.close()
  state.config.hover.match_preview_width = original_match_preview_width
  state.config.hover.width_mode = original_width_mode

  -- A target that cannot currently fit must leave the state retryable. Once
  -- geometry becomes valid, reconcile should open it without requiring the
  -- user to leave and re-enter the diagnostic.
  drain_events(20)
  local original_delay = state.config.hover.delay_ms
  local original_input_mode = state.config.hover.input_mode
  local original_row_offset = state.config.hover.row_offset
  local original_placement_order = vim.deepcopy(state.config.hover.placement.order)
  state.config.hover.delay_ms = 0
  state.config.hover.input_mode = "cursor"
  state.config.hover.row_offset = vim.o.lines + 100
  state.config.hover.placement.order = { "right" }
  hover.track_current()
  assert_truthy(not state.hover.win, "an impossible placement should not open a float")
  assert_truthy(
    not state.hover.pending_target,
    "an impossible placement should not leave a permanently sticky pending target"
  )
  state.config.hover.row_offset = 0
  hover.reconcile()
  assert_truthy(state.hover.win, "reconcile should retry a target after geometry becomes valid")
  plugin.close()
  drain_events(20)

  -- Deferred callbacks from an older target must not open after the cursor has
  -- already left it.
  state.config.hover.placement.order = original_placement_order
  state.config.hover.delay_ms = 25
  vim.api.nvim_win_set_cursor(0, { 4, 8 })
  hover.track_current()
  assert_truthy(state.hover.pending_target, "a nonzero delay should create a pending target")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  hover.track_current()
  drain_events(60)
  assert_truthy(not state.hover.win, "a stale delayed generation must not open a float")
  assert_truthy(not state.hover.pending_target, "leaving should cancel the delayed target")
  state.config.hover.delay_ms = original_delay
  state.config.hover.input_mode = original_input_mode
  state.config.hover.row_offset = original_row_offset
  vim.api.nvim_win_set_cursor(0, { 4, 8 })

  -- Mouse scope defaults to diagnosed code plus its preview, rather than the
  -- entire source line. Mock getmousepos() so the behavior remains testable
  -- without attaching a UI to the headless Neovim instance.
  assert_equal("diagnostic", state.config.hover.mouse_scope, "mouse scope should be conservative")
  assert_equal("both", state.config.hover.input_mode, "cursor and mouse should both be enabled")
  local original_getmousepos = vim.fn.getmousepos
  local mouse_position = {}
  vim.fn.getmousepos = function()
    return mouse_position
  end
  original_input_mode = state.config.hover.input_mode
  original_delay = state.config.hover.delay_ms
  state.config.hover.input_mode = "mouse"
  state.config.hover.delay_ms = 0

  local source_win = vim.api.nvim_get_current_win()
  vim.fn.winrestview({ topline = 1 })
  local source_point = vim.fn.screenpos(source_win, 1, 1)
  mouse_position = {
    winid = source_win,
    line = 1,
    column = 1,
    screenrow = source_point.row,
    screencol = source_point.col,
  }
  hover.track_mouse()
  assert_truthy(not state.hover.win, "unrelated code on a diagnostic line should not trigger hover")

  mouse_position.column = 15
  mouse_position.screencol = source_point.col + 14
  hover.track_mouse()
  assert_truthy(state.hover.win, "the diagnosed code range should trigger default mouse hover")
  plugin.close()

  vim.fn.winrestview({ topline = 1 })
  local preview_bounds = renderer.preview_screen_bounds(source_win, renderer.get_layout(bufnr, 0))
  assert_truthy(preview_bounds, "the visible preview should expose screen bounds for hit testing")
  mouse_position.column = 1
  mouse_position.screenrow = preview_bounds.row + 1
  mouse_position.screencol = preview_bounds.left + 1
  hover.track_mouse()
  assert_truthy(state.hover.win, "the inline preview should trigger default mouse hover")
  plugin.close()

  state.config.hover.mouse_scope = "line"
  vim.fn.winrestview({ topline = 1 })
  mouse_position.screenrow = source_point.row
  mouse_position.screencol = source_point.col
  hover.track_mouse()
  assert_truthy(state.hover.win, "line mouse scope should retain whole-line compatibility")
  plugin.close()

  -- In both mode, one input falling outside the diagnostic must not close a
  -- target still held by the other input.
  state.config.hover.input_mode = "both"
  state.config.hover.mouse_scope = "diagnostic"
  vim.api.nvim_win_set_cursor(source_win, { 4, 8 })
  mouse_position = {
    winid = source_win,
    line = 1,
    column = 1,
    screenrow = source_point.row,
    screencol = source_point.col,
  }
  hover.track_current()
  assert_truthy(state.hover.win, "keyboard cursor should open hover in both mode")
  hover.track_mouse()
  assert_truthy(state.hover.win, "unrelated mouse movement should preserve a cursor target")
  plugin.close()

  vim.fn.winrestview({ topline = 1 })
  mouse_position.column = 15
  mouse_position.screencol = source_point.col + 14
  hover.track_mouse()
  assert_truthy(state.hover.win, "mouse should open hover in both mode")
  vim.api.nvim_win_set_cursor(source_win, { 3, 0 })
  hover.track_current()
  assert_truthy(state.hover.win, "cursor movement should preserve a mouse target under the pointer")
  plugin.close()

  -- Clicking an inline preview moves Neovim's source cursor to the line end.
  -- The mouse and cursor still identify the same logical line target, so that
  -- input handoff (and a scroll-style geometry refresh caused by the click)
  -- must reuse the surface without changing its anchor or matched width.
  vim.fn.winrestview({ topline = 1 })
  local click_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  vim.api.nvim_win_set_cursor(source_win, { 1, 6 })
  plugin.close()
  local click_layout = renderer.get_layout(bufnr, 0)
  local click_preview_bounds = renderer.preview_screen_bounds(source_win, click_layout)
  assert_truthy(click_preview_bounds, "click handoff should start from a visible preview")
  mouse_position = {
    winid = source_win,
    line = 1,
    column = #click_line + 1,
    screenrow = click_preview_bounds.row + 1,
    screencol = click_preview_bounds.left + 1,
  }
  hover.track_mouse()
  local click_float = state.hover.win
  assert_truthy(click_float, "mouse preview hover should open before the click handoff")
  assert_equal("mouse", state.hover.target.input, "the preview should initially be mouse-owned")
  local click_target_group = state.hover.target.group_key
  local click_target_layout = state.hover.target.layout_row
  local click_generation = state.hover.generation
  local click_float_config = vim.api.nvim_win_get_config(click_float)

  vim.api.nvim_win_set_cursor(source_win, { 1, #click_line })
  hover.track_current()
  assert_equal(
    click_target_group,
    state.hover.target.group_key,
    "clicking the preview should retain the logical diagnostic target"
  )
  assert_equal(
    click_target_layout,
    state.hover.target.layout_row,
    "clicking the preview should retain its rendered layout target"
  )
  assert_equal("cursor", state.hover.target.input, "the cursor should take over the same target")
  assert_equal(
    click_generation,
    state.hover.generation,
    "mouse-to-cursor handoff should not restart the hover timer"
  )

  hover.refresh({ preserve_geometry = true })
  local clicked_float_config = vim.api.nvim_win_get_config(state.hover.win)
  assert_equal(click_float, state.hover.win, "click handoff should reuse the open surface")
  assert_equal(
    click_float_config.row,
    clicked_float_config.row,
    "click handoff should preserve the expanded surface row"
  )
  assert_equal(
    click_float_config.col,
    clicked_float_config.col,
    "click handoff should preserve the expanded surface column"
  )
  assert_equal(
    click_float_config.width,
    clicked_float_config.width,
    "click handoff should preserve the preview-matched surface width"
  )
  plugin.close()

  -- A non-focusable float passes clicks through to the source rows beneath
  -- it. If one of those rows has another diagnostic, that incidental cursor
  -- target must not replace a mouse-held surface while the pointer remains
  -- inside it. Once the pointer leaves, normal cursor ownership resumes.
  vim.api.nvim_win_set_cursor(source_win, { 3, 0 })
  vim.fn.winrestview({ topline = 1 })
  click_preview_bounds = renderer.preview_screen_bounds(source_win, click_layout)
  local underlying_row = 3
  local underlying_line =
    vim.api.nvim_buf_get_lines(bufnr, underlying_row, underlying_row + 1, false)[1]
  local underlying_point = {
    row = source_point.row + underlying_row,
    col = source_point.col,
  }
  mouse_position = {
    winid = source_win,
    line = 1,
    column = #click_line + 1,
    screenrow = click_preview_bounds.row + 1,
    screencol = click_preview_bounds.left + 1,
  }
  hover.track_mouse()
  local covered_float = state.hover.win
  assert_truthy(covered_float, "mouse hover should open before the covered-row click")
  assert_equal("mouse", state.hover.target.input, "the covered-row surface should be mouse-owned")
  local covered_group = state.hover.target.group_key
  local covered_layout = state.hover.target.layout_row
  local covered_generation = state.hover.generation
  local covered_config = vim.api.nvim_win_get_config(covered_float)
  local covered_bounds = vim.deepcopy(state.hover.bounds)
  assert_truthy(
    underlying_point.row - 1 >= covered_bounds.top
      and underlying_point.row - 1 < covered_bounds.bottom,
    ("the regression diagnostic row should be covered by the expanded surface: bounds=%s row=%s"):format(
      vim.inspect(covered_bounds),
      vim.inspect(underlying_point.row - 1)
    )
  )
  mouse_position = {
    winid = source_win,
    line = underlying_row + 1,
    column = #underlying_line + 1,
    screenrow = underlying_point.row,
    screencol = covered_bounds.left + 1,
  }
  vim.api.nvim_win_set_cursor(source_win, { underlying_row + 1, #underlying_line })
  hover.track_current()
  local held_config = vim.api.nvim_win_get_config(state.hover.win)
  assert_equal(covered_float, state.hover.win, "a covered-row click should reuse the mouse surface")
  assert_equal(
    covered_group,
    state.hover.target.group_key,
    "a covered row must not steal the target"
  )
  assert_equal(
    covered_layout,
    state.hover.target.layout_row,
    "a covered row must not replace the mouse layout"
  )
  assert_equal("mouse", state.hover.target.input, "the pointer should retain surface ownership")
  assert_equal(
    covered_generation,
    state.hover.generation,
    "a covered-row click should not restart the hover timer"
  )
  assert_equal(
    covered_config.col,
    held_config.col,
    "a covered-row click should preserve the column"
  )
  assert_equal(
    covered_config.width,
    held_config.width,
    "a covered-row click should preserve the width"
  )

  mouse_position.column = 1
  mouse_position.screencol = underlying_point.col
  hover.track_current()
  assert_truthy(
    state.hover.target.group_key ~= covered_group,
    "the cursor should take over a different diagnostic after the pointer leaves"
  )
  assert_equal(
    underlying_row,
    state.hover.target.layout_row,
    "cursor takeover should select the underlying diagnostic layout"
  )
  assert_equal("cursor", state.hover.target.input, "pointer leave should restore cursor ownership")
  plugin.close()

  state.config.hover.mouse_scope = "diagnostic"
  state.config.hover.input_mode = original_input_mode
  state.config.hover.delay_ms = original_delay
  vim.fn.getmousepos = original_getmousepos

  -- Short multiline diagnostics align after their widest covered line. This
  -- keeps import-block style diagnostics beside the source while retaining a
  -- conservative below fallback when range-width alignment is disabled.
  local range_bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(range_bufnr)
  local long_range_line = "    long_symbol_name_for_import_testing,"
  vim.api.nvim_buf_set_lines(range_bufnr, 0, -1, false, {
    "from package import (",
    long_range_line,
    ")",
  })
  local range_namespace = vim.api.nvim_create_namespace("aligned-inline-diagnostic-range-test")
  vim.diagnostic.set(range_namespace, range_bufnr, {
    {
      lnum = 0,
      col = 0,
      end_lnum = 2,
      end_col = 1,
      severity = vim.diagnostic.severity.WARN,
      source = "ruff",
      code = "I001",
      message = "Import block is un-sorted or un-formatted",
    },
  })
  plugin.refresh(range_bufnr)
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  vim.fn.winrestview({ topline = 1 })
  local multiline_layout = renderer.get_layout(range_bufnr, 0)
  assert_equal(
    util.display_width(long_range_line),
    multiline_layout.clearance_width,
    "multiline alignment should include the widest covered source line"
  )
  local range_source_win = vim.api.nvim_get_current_win()
  local range_preview_bounds = renderer.preview_screen_bounds(range_source_win, multiline_layout)
  local range_float = plugin.open()
  assert_truthy(range_float, "range-width aligned multiline hover should open")
  assert_equal("right", state.hover.placement, "range-width alignment should retain side placement")
  local range_float_config = vim.api.nvim_win_get_config(range_float)
  assert_equal(
    range_preview_bounds.row,
    range_float_config.row,
    "range hover should retain its row"
  )
  assert_equal(
    range_preview_bounds.left,
    range_float_config.col,
    "range hover should retain its column"
  )
  plugin.close()

  state.config.alignment.include_range_width = false
  plugin.refresh(range_bufnr)
  vim.cmd("redraw")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  multiline_layout = renderer.get_layout(range_bufnr, 0)
  assert_truthy(
    multiline_layout.clearance_width < util.display_width(long_range_line),
    "range-width alignment should remain configurable"
  )
  range_float = plugin.open()
  assert_truthy(range_float, "overlapping multiline hover should use a fallback")
  assert_equal(
    "below",
    state.hover.placement,
    "a multiline range crossing the preview column should avoid covering source"
  )
  plugin.close()
  state.config.alignment.include_range_width = true
  vim.api.nvim_set_current_buf(bufnr)
  plugin.refresh(bufnr)
  vim.api.nvim_buf_delete(range_bufnr, { force = true })

  -- Teardown must not overwrite global options that another component changed
  -- after this plugin installed its own values.
  local external_virtual_text = { spacing = 7, prefix = "external" }
  vim.diagnostic.config({ virtual_text = external_virtual_text })
  local supports_mousemoveevent = vim.fn.exists("+mousemoveevent") == 1
  if supports_mousemoveevent then
    vim.o.mousemoveevent = false
  end
  local enabled_epoch = state.lifecycle_epoch
  plugin.disable()
  assert_truthy(state.lifecycle_epoch > enabled_epoch, "disable should advance the lifecycle epoch")
  local retained_virtual_text = vim.diagnostic.config().virtual_text
  assert_truthy(
    type(retained_virtual_text) == "table"
      and retained_virtual_text.spacing == external_virtual_text.spacing
      and retained_virtual_text.prefix == external_virtual_text.prefix,
    "disable should preserve externally replaced diagnostic virtual text"
  )
  if supports_mousemoveevent then
    assert_truthy(
      not vim.o.mousemoveevent,
      "disable should preserve an externally replaced mousemoveevent value"
    )
  end
end

local ok, error_message = xpcall(run, debug.traceback)
if ok then
  print("aligned-inline-diagnostic.nvim: tests passed")
  vim.cmd("qa!")
else
  vim.api.nvim_err_writeln(error_message)
  vim.cmd("cquit")
end
