local util = require("aligned-inline-diagnostic.util")

local M = {}

M.defaults = {
  enabled = true,
  disable_default_virtual_text = true,
  throttle_ms = 20,
  priority = 2048,
  disabled_filetypes = {},

  diagnostics = {
    -- Optional inclusion filters. Severity accepts a name, number, or list.
    severity = nil,
    sources = nil,
    exclude_sources = {},
    namespaces = nil,
    -- Optional final predicate: function(diagnostic, bufnr) -> boolean.
    filter = nil,
    -- Off by default to preserve the diagnostics exposed by Neovim exactly.
    deduplicate = false,
  },

  alignment = {
    -- "block" aligns nearby diagnostic lines, "buffer" aligns the entire
    -- buffer, and "none" only adds `padding` after each line.
    mode = "block",
    min_col = 36,
    padding = 3,
    -- Keep previews beside short multiline ranges by including the widest
    -- covered line in their alignment clearance. Very large ranges remain
    -- start-line based to keep rendering bounded.
    include_range_width = true,
    max_range_lines = 50,
    -- Number of clean lines allowed between diagnostics in the same block.
    max_gap = 4,
    -- Optional hard cap for the shared anchor. Long code lines still receive
    -- `padding`, so virtual text never overwrites buffer text.
    max_col = nil,
  },

  preview = {
    max_width = 52,
    ellipsis = "…",
    show_count = true,
    -- "fit" keeps every pill compact, "block" gives nearby diagnostics a
    -- shared width, and "fixed" always uses max_width.
    width_mode = "block",
    count_align = "right", -- "inline" or "right"
    padding_left = 1,
    padding_right = 1,
    inactive = {
      enabled = true,
      scope = "block", -- "block" or "buffer"
    },
    -- Optional callback: function(diagnostic, context) -> string|nil
    format = nil,
    -- Optional callback: function(extra, total) -> string
    count_format = nil,
  },

  hover = {
    enabled = true,
    -- nil inherits 'updatetime'; a number is a plugin-local delay in ms.
    delay_ms = nil,
    -- Preserve the timer and open float while moving within the same
    -- diagnostic range. When false, every movement rearms the hover.
    sticky = true,
    -- "cursor", "mouse", or "both". Explicit input_mode takes precedence
    -- over the deprecated use_mouse compatibility option.
    input_mode = "both",
    -- Deprecated: true maps to input_mode="mouse" and false to "cursor"
    -- when input_mode is not supplied by the user.
    use_mouse = false,
    -- Mouse activation can be limited to the diagnosed code and/or preview.
    mouse_scope = "diagnostic", -- "diagnostic", "code", "preview", or "line"
    -- These retain the current line-grouped behavior. More exact selection
    -- modes can be enabled without changing existing configurations.
    cursor_scope = "line", -- "line" or "diagnostic"
    group_by = "line", -- "line", "range", or "block"
    hide_preview = true,
    border = "none",
    min_width = 30,
    max_width = 72,
    -- A stable target below max_width. "preferred" uses it, "fit" hugs
    -- content, and "fixed" always requests max_width.
    preferred_width = 54,
    width_mode = "preferred", -- "fit", "preferred", or "fixed"
    -- Use the rendered inline pill as the preferred expanded width. Existing
    -- min/max constraints remain authoritative when exact matching cannot fit.
    match_preview_width = true,
    max_height = 18,
    -- Zero starts the float directly over the persistent inline preview so it
    -- appears to expand in place.
    row_offset = 0,
    col_offset = 0,
    zindex = 60,
    winblend = 0,
    show_source = true,
    show_code = true,
    show_severity = false,
    deduplicate_source = true,
    message_first = true,
    metadata_position = "below", -- "below", "inline", or "hidden"
    metadata_separator = " · ",
    item_spacing = 0,
    padding_left = 1,
    padding_right = 1,
    wrap_mode = "balanced", -- "balanced" or "greedy"
    highlight_tokens = true,
    cap_style = "ends", -- "ends", "all", or "none"
    placement = {
      order = { "right", "below", "above" },
      gap = 0,
      edge_margin = 1,
      avoid_source = true,
      -- Keep an in-place expansion attached to the preview's exact top-left
      -- cell, shrinking or truncating before trying a relocated fallback.
      preserve_anchor = true,
    },
    dim_inactive = true,
    -- false, "primary", or "all".
    highlight_target = "all",
    show_related = true,
    -- Optional callback: function(diagnostic) -> string|string[]|nil
    -- Returned text is appended to the expanded diagnostic body.
    details = nil,
    -- Optional callbacks returning string|string[]|nil. They change content,
    -- while the plugin retains wrapping, geometry, and highlighting.
    format_message = nil,
    format_metadata = nil,
  },

  appearance = {
    preview_blend = 0.14,
    hover_blend = 0.12,
    -- Palette entries accept #RRGGBB, integer colors, or highlight groups.
    -- One low blend strength keeps every severity in the same soft palette.
    hover_tints = {
      error = "DiagnosticError",
      warn = "DiagnosticWarn",
      info = "DiagnosticInfo",
      hint = "DiagnosticHint",
    },
    preview_tints = {
      error = "DiagnosticError",
      warn = "DiagnosticWarn",
      info = "DiagnosticInfo",
      hint = "DiagnosticHint",
    },
    -- Exact per-severity colors override generated tint colors.
    preview_backgrounds = {},
    hover_backgrounds = {},
    -- Optional shared tint overriding hover_tints.
    hover_tint = nil,
    -- Optional exact shared color. This bypasses severity-generated hover
    -- backgrounds while keeping the body, caps, and glyphs unified.
    hover_background = nil,
    inactive_blend = 0.55,
    active_blend = 0.10,
    metadata_blend = 0.58,
    ensure_contrast = true,
    minimum_contrast = 3.0,
    edge_underlay = {
      -- Preview edges omit their background and combine with native window
      -- highlights where possible. Floats resolve these sources explicitly.
      combine = true,
      normal = "Normal",
      colorcolumn = "ColorColumn",
      overflow = "PastColorColumn",
      -- nil uses the greatest configured 'colorcolumn', when available.
      overflow_column = nil,
      respect_colorcolumn = true,
      -- Optional: function(context) -> "inherit"|region|color|highlight|nil
      resolve = nil,
    },
  },

  -- Applied after generated defaults. Values are nvim_set_hl() specs.
  -- Example: { AlignedDiagnosticFloatBody = { bg = "#405060" } }
  highlights = {},

  icons = {
    error = "●",
    warn = "▲",
    info = "◆",
    hint = "○",
    branch = "├",
    continuation = "│",
    last = "╰",
    related = "↳",
    left = "",
    right = "",
  },
}

local function assert_number(name, value, minimum)
  if type(value) ~= "number" or value < minimum then
    error(("aligned-inline-diagnostic: %s must be a number >= %s"):format(name, minimum))
  end
end

local function assert_integer(name, value, minimum)
  assert_number(name, value, minimum)
  if value % 1 ~= 0 then
    error(("aligned-inline-diagnostic: %s must be an integer"):format(name))
  end
end

local function assert_ratio(name, value)
  if type(value) ~= "number" or value < 0 or value > 1 then
    error(("aligned-inline-diagnostic: %s must be a number between 0 and 1"):format(name))
  end
end

local function assert_color(name, value)
  if value == nil then
    return
  end
  if type(value) ~= "string" and type(value) ~= "number" then
    error(("aligned-inline-diagnostic: %s must be a color or highlight group"):format(name))
  end
  if type(value) == "string" and value:find("[\r\n]") then
    error(("aligned-inline-diagnostic: %s must not contain a newline"):format(name))
  end
  if type(value) == "number" and (value < 0 or value > 0xffffff or value % 1 ~= 0) then
    error(("aligned-inline-diagnostic: numeric %s must be 0x000000..0xffffff"):format(name))
  end
end

local function assert_boolean(name, value)
  if type(value) ~= "boolean" then
    error(("aligned-inline-diagnostic: %s must be a boolean"):format(name))
  end
end

local function assert_enum(name, value, choices)
  if not choices[value] then
    local values = {}
    for choice in pairs(choices) do
      table.insert(values, ("'%s'"):format(choice))
    end
    table.sort(values)
    error(("aligned-inline-diagnostic: %s must be %s"):format(name, table.concat(values, ", ")))
  end
end

local function assert_optional_function(name, value)
  if value ~= nil and type(value) ~= "function" then
    error(("aligned-inline-diagnostic: %s must be a function or nil"):format(name))
  end
end

local function assert_string(name, value)
  if type(value) ~= "string" then
    error(("aligned-inline-diagnostic: %s must be a string"):format(name))
  end
end

local function assert_single_line_string(name, value)
  assert_string(name, value)
  if value:find("[\r\n]") then
    error(("aligned-inline-diagnostic: %s must not contain a newline"):format(name))
  end
end

local function assert_highlight_color(name, value)
  if value == nil then
    return
  end
  if type(value) == "number" then
    if value < 0 or value > 0xffffff or value % 1 ~= 0 then
      error(("aligned-inline-diagnostic: numeric %s must be 0x000000..0xffffff"):format(name))
    end
    return
  end
  if type(value) ~= "string" then
    error(("aligned-inline-diagnostic: %s must be #RRGGBB or an integer color"):format(name))
  end
  local named_color = vim.api.nvim_get_color_by_name(value)
  if
    value ~= "NONE"
    and value ~= "fg"
    and value ~= "bg"
    and not value:match("^#%x%x%x%x%x%x$")
    and named_color == -1
  then
    error(
      ("aligned-inline-diagnostic: %s must be #RRGGBB, 'fg', 'bg', 'NONE', or an integer color"):format(
        name
      )
    )
  end
end

local function assert_highlight_spec(name, spec)
  -- Keep unknown keys forward-compatible with newer nvim_set_hl() versions,
  -- but validate every stable field the plugin currently documents or uses.
  for _, field in ipairs({ "fg", "bg", "sp" }) do
    assert_highlight_color(name .. "." .. field, spec[field])
  end

  if spec.blend ~= nil then
    assert_integer(name .. ".blend", spec.blend, 0)
    if spec.blend > 100 then
      error(("aligned-inline-diagnostic: %s.blend must not exceed 100"):format(name))
    end
  end

  for _, field in ipairs({
    "bold",
    "standout",
    "underline",
    "undercurl",
    "underdouble",
    "underdotted",
    "underdashed",
    "strikethrough",
    "italic",
    "reverse",
    "nocombine",
    "default",
    "force",
  }) do
    if spec[field] ~= nil then
      assert_boolean(name .. "." .. field, spec[field])
    end
  end

  if spec.link ~= nil then
    assert_single_line_string(name .. ".link", spec.link)
    if spec.link == "" then
      error(("aligned-inline-diagnostic: %s.link must not be empty"):format(name))
    end
  end
end

local function assert_table(name, value)
  if type(value) ~= "table" then
    error(("aligned-inline-diagnostic: %s must be a table"):format(name))
  end
end

local function assert_list(name, value)
  assert_table(name, value)
  local count = 0
  local greatest = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      error(("aligned-inline-diagnostic: %s must be a list"):format(name))
    end
    count = count + 1
    greatest = math.max(greatest, key)
  end
  if greatest ~= count then
    error(("aligned-inline-diagnostic: %s must be a dense list"):format(name))
  end
  return count
end

local function assert_string_list(name, value, optional)
  if optional and value == nil then
    return
  end
  assert_list(name, value)
  for index, item in ipairs(value) do
    assert_single_line_string(("%s[%d]"):format(name, index), item)
  end
end

local function assert_integer_list(name, value, optional)
  if optional and value == nil then
    return
  end
  assert_list(name, value)
  for index, item in ipairs(value) do
    assert_integer(("%s[%d]"):format(name, index), item, 0)
  end
end

local function assert_signed_integer(name, value)
  if type(value) ~= "number" or value % 1 ~= 0 then
    error(("aligned-inline-diagnostic: %s must be an integer"):format(name))
  end
end

local function assert_border(name, value)
  if type(value) == "string" then
    assert_enum(name, value, {
      [""] = true,
      none = true,
      single = true,
      double = true,
      rounded = true,
      solid = true,
      shadow = true,
    })
    return
  end

  local length = assert_list(name, value)
  if length ~= 1 and length ~= 2 and length ~= 4 and length ~= 8 then
    error(("aligned-inline-diagnostic: %s list must contain 1, 2, 4, or 8 entries"):format(name))
  end
  for index, item in ipairs(value) do
    local item_name = ("%s[%d]"):format(name, index)
    if type(item) == "string" then
      assert_single_line_string(item_name, item)
    elseif type(item) == "table" then
      if assert_list(item_name, item) ~= 2 then
        error(("aligned-inline-diagnostic: %s must be { text, highlight }"):format(item_name))
      end
      assert_single_line_string(item_name .. "[1]", item[1])
      assert_single_line_string(item_name .. "[2]", item[2])
    else
      error(
        ("aligned-inline-diagnostic: %s must be a string or { text, highlight }"):format(item_name)
      )
    end
  end
end

local severity_names = { error = true, warn = true, info = true, hint = true }

local function assert_severity(name, value)
  if type(value) == "number" then
    assert_integer(name, value, 1)
    if value > 4 then
      error(("aligned-inline-diagnostic: %s must be a diagnostic severity (1..4)"):format(name))
    end
    return
  end
  if type(value) == "string" then
    assert_enum(name, value:lower(), severity_names)
    return
  end
  error(("aligned-inline-diagnostic: %s must be a severity name or number"):format(name))
end

local function assert_severity_filter(name, value)
  if value == nil then
    return
  end
  if type(value) ~= "table" then
    assert_severity(name, value)
    return
  end
  assert_list(name, value)
  for index, severity in ipairs(value) do
    assert_severity(("%s[%d]"):format(name, index), severity)
  end
end

local function validate(config)
  assert_boolean("enabled", config.enabled)
  assert_boolean("disable_default_virtual_text", config.disable_default_virtual_text)
  assert_integer("throttle_ms", config.throttle_ms, 0)
  assert_integer("priority", config.priority, 0)
  assert_string_list("disabled_filetypes", config.disabled_filetypes)

  for _, name in ipairs({
    "alignment",
    "preview",
    "hover",
    "appearance",
    "highlights",
    "icons",
    "diagnostics",
  }) do
    assert_table(name, config[name])
  end

  assert_severity_filter("diagnostics.severity", config.diagnostics.severity)
  assert_string_list("diagnostics.sources", config.diagnostics.sources, true)
  assert_string_list("diagnostics.exclude_sources", config.diagnostics.exclude_sources)
  assert_integer_list("diagnostics.namespaces", config.diagnostics.namespaces, true)
  assert_optional_function("diagnostics.filter", config.diagnostics.filter)
  assert_boolean("diagnostics.deduplicate", config.diagnostics.deduplicate)

  local modes = { block = true, buffer = true, none = true }
  if not modes[config.alignment.mode] then
    error("aligned-inline-diagnostic: alignment.mode must be 'block', 'buffer', or 'none'")
  end

  assert_integer("alignment.min_col", config.alignment.min_col, 0)
  assert_integer("alignment.padding", config.alignment.padding, 0)
  assert_boolean("alignment.include_range_width", config.alignment.include_range_width)
  assert_integer("alignment.max_range_lines", config.alignment.max_range_lines, 1)
  assert_integer("alignment.max_gap", config.alignment.max_gap, 0)
  if config.alignment.max_col ~= nil then
    assert_integer("alignment.max_col", config.alignment.max_col, 1)
  end
  assert_integer("preview.max_width", config.preview.max_width, 4)
  assert_single_line_string("preview.ellipsis", config.preview.ellipsis)
  assert_boolean("preview.show_count", config.preview.show_count)
  assert_enum("preview.width_mode", config.preview.width_mode, {
    fit = true,
    block = true,
    fixed = true,
  })
  assert_enum("preview.count_align", config.preview.count_align, { inline = true, right = true })
  assert_integer("preview.padding_left", config.preview.padding_left, 0)
  assert_integer("preview.padding_right", config.preview.padding_right, 0)
  assert_boolean("preview.inactive.enabled", config.preview.inactive.enabled)
  assert_enum("preview.inactive.scope", config.preview.inactive.scope, {
    block = true,
    buffer = true,
  })
  assert_optional_function("preview.format", config.preview.format)
  assert_optional_function("preview.count_format", config.preview.count_format)
  assert_integer("hover.min_width", config.hover.min_width, 1)
  assert_integer("hover.max_width", config.hover.max_width, config.hover.min_width)
  assert_integer("hover.preferred_width", config.hover.preferred_width, config.hover.min_width)
  if config.hover.preferred_width > config.hover.max_width then
    error("aligned-inline-diagnostic: hover.preferred_width must not exceed hover.max_width")
  end
  assert_enum("hover.width_mode", config.hover.width_mode, {
    fit = true,
    preferred = true,
    fixed = true,
  })
  assert_boolean("hover.match_preview_width", config.hover.match_preview_width)
  assert_integer("hover.max_height", config.hover.max_height, 1)
  assert_signed_integer("hover.row_offset", config.hover.row_offset)
  assert_signed_integer("hover.col_offset", config.hover.col_offset)
  assert_integer("hover.zindex", config.hover.zindex, 1)
  assert_integer("hover.winblend", config.hover.winblend, 0)
  if config.hover.winblend > 100 then
    error("aligned-inline-diagnostic: hover.winblend must not exceed 100")
  end
  if config.hover.delay_ms ~= nil then
    assert_integer("hover.delay_ms", config.hover.delay_ms, 0)
  end
  assert_boolean("hover.enabled", config.hover.enabled)
  assert_boolean("hover.sticky", config.hover.sticky)
  assert_enum("hover.input_mode", config.hover.input_mode, {
    cursor = true,
    mouse = true,
    both = true,
  })
  assert_boolean("hover.use_mouse", config.hover.use_mouse)
  assert_boolean("hover.hide_preview", config.hover.hide_preview)
  assert_enum("hover.mouse_scope", config.hover.mouse_scope, {
    diagnostic = true,
    code = true,
    preview = true,
    line = true,
  })
  assert_enum("hover.cursor_scope", config.hover.cursor_scope, {
    line = true,
    diagnostic = true,
  })
  assert_enum("hover.group_by", config.hover.group_by, {
    line = true,
    range = true,
    block = true,
  })
  assert_border("hover.border", config.hover.border)
  assert_boolean("hover.show_severity", config.hover.show_severity)
  assert_boolean("hover.show_source", config.hover.show_source)
  assert_boolean("hover.show_code", config.hover.show_code)
  assert_boolean("hover.deduplicate_source", config.hover.deduplicate_source)
  assert_boolean("hover.message_first", config.hover.message_first)
  assert_enum("hover.metadata_position", config.hover.metadata_position, {
    below = true,
    inline = true,
    hidden = true,
  })
  assert_string("hover.metadata_separator", config.hover.metadata_separator)
  assert_integer("hover.item_spacing", config.hover.item_spacing, 0)
  assert_integer("hover.padding_left", config.hover.padding_left, 0)
  assert_integer("hover.padding_right", config.hover.padding_right, 0)
  assert_enum("hover.wrap_mode", config.hover.wrap_mode, { balanced = true, greedy = true })
  assert_boolean("hover.highlight_tokens", config.hover.highlight_tokens)
  assert_enum("hover.cap_style", config.hover.cap_style, {
    ends = true,
    all = true,
    none = true,
  })
  assert_table("hover.placement", config.hover.placement)
  assert_list("hover.placement.order", config.hover.placement.order)
  local placements = { right = true, below = true, above = true }
  for index, value in ipairs(config.hover.placement.order) do
    assert_enum(("hover.placement.order[%d]"):format(index), value, placements)
  end
  if #config.hover.placement.order == 0 then
    error("aligned-inline-diagnostic: hover.placement.order must not be empty")
  end
  assert_integer("hover.placement.gap", config.hover.placement.gap, 0)
  assert_integer("hover.placement.edge_margin", config.hover.placement.edge_margin, 0)
  assert_boolean("hover.placement.avoid_source", config.hover.placement.avoid_source)
  assert_boolean("hover.placement.preserve_anchor", config.hover.placement.preserve_anchor)
  assert_boolean("hover.dim_inactive", config.hover.dim_inactive)
  if
    config.hover.highlight_target ~= false
    and config.hover.highlight_target ~= "primary"
    and config.hover.highlight_target ~= "all"
  then
    error("aligned-inline-diagnostic: hover.highlight_target must be false, 'primary', or 'all'")
  end
  assert_optional_function("hover.details", config.hover.details)
  assert_boolean("hover.show_related", config.hover.show_related)
  assert_optional_function("hover.format_message", config.hover.format_message)
  assert_optional_function("hover.format_metadata", config.hover.format_metadata)
  assert_ratio("appearance.preview_blend", config.appearance.preview_blend)
  assert_ratio("appearance.hover_blend", config.appearance.hover_blend)
  assert_ratio("appearance.inactive_blend", config.appearance.inactive_blend)
  assert_ratio("appearance.active_blend", config.appearance.active_blend)
  assert_ratio("appearance.metadata_blend", config.appearance.metadata_blend)
  assert_boolean("appearance.ensure_contrast", config.appearance.ensure_contrast)
  assert_number("appearance.minimum_contrast", config.appearance.minimum_contrast, 1)
  if config.appearance.minimum_contrast > 21 then
    error("aligned-inline-diagnostic: appearance.minimum_contrast must not exceed 21")
  end
  if type(config.appearance.edge_underlay) ~= "table" then
    error("aligned-inline-diagnostic: appearance.edge_underlay must be a table")
  end
  local edge_underlay = config.appearance.edge_underlay
  assert_boolean("appearance.edge_underlay.combine", edge_underlay.combine)
  assert_boolean("appearance.edge_underlay.respect_colorcolumn", edge_underlay.respect_colorcolumn)
  assert_color("appearance.edge_underlay.normal", edge_underlay.normal)
  assert_color("appearance.edge_underlay.colorcolumn", edge_underlay.colorcolumn)
  assert_color("appearance.edge_underlay.overflow", edge_underlay.overflow)
  if edge_underlay.overflow_column ~= nil then
    assert_integer("appearance.edge_underlay.overflow_column", edge_underlay.overflow_column, 1)
  end
  assert_optional_function("appearance.edge_underlay.resolve", edge_underlay.resolve)
  if type(config.appearance.hover_tints) ~= "table" then
    error("aligned-inline-diagnostic: appearance.hover_tints must be a table")
  end
  for _, name in ipairs({ "preview_tints", "preview_backgrounds", "hover_backgrounds" }) do
    if type(config.appearance[name]) ~= "table" then
      error(("aligned-inline-diagnostic: appearance.%s must be a table"):format(name))
    end
  end
  for _, key in ipairs({ "error", "warn", "info", "hint" }) do
    assert_color("appearance.hover_tints." .. key, config.appearance.hover_tints[key])
    assert_color("appearance.preview_tints." .. key, config.appearance.preview_tints[key])
    assert_color(
      "appearance.preview_backgrounds." .. key,
      config.appearance.preview_backgrounds[key]
    )
    assert_color("appearance.hover_backgrounds." .. key, config.appearance.hover_backgrounds[key])
  end
  assert_color("appearance.hover_tint", config.appearance.hover_tint)
  assert_color("appearance.hover_background", config.appearance.hover_background)
  for name, spec in pairs(config.highlights) do
    if type(name) ~= "string" or name == "" then
      error("aligned-inline-diagnostic: highlights keys must be non-empty strings")
    end
    if type(spec) == "string" then
      assert_single_line_string("highlights." .. name, spec)
      if spec == "" then
        error(("aligned-inline-diagnostic: highlights.%s must not be empty"):format(name))
      end
    elseif type(spec) ~= "table" then
      error(("aligned-inline-diagnostic: highlights.%s must be a table or link"):format(name))
    else
      assert_highlight_spec("highlights." .. name, spec)
    end
  end
  for _, key in ipairs({
    "error",
    "warn",
    "info",
    "hint",
    "branch",
    "continuation",
    "last",
    "related",
    "left",
    "right",
  }) do
    assert_single_line_string("icons." .. key, config.icons[key])
  end
  local structural_width = util.hover_structural_width(config)
  if config.hover.max_width < structural_width then
    error(
      ("aligned-inline-diagnostic: hover.max_width must be >= %d for the configured caps, padding, and glyphs"):format(
        structural_width
      )
    )
  end
end

function M.resolve(options)
  if options ~= nil and type(options) ~= "table" then
    error("aligned-inline-diagnostic: setup options must be a table or nil")
  end
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), options or {})
  -- Preserve the old switch for existing configurations. New configurations
  -- should use input_mode, which can enable both inputs simultaneously.
  local hover_options = options and options.hover or nil
  if hover_options and hover_options.input_mode == nil and hover_options.use_mouse ~= nil then
    config.hover.input_mode = hover_options.use_mouse and "mouse" or "cursor"
  end
  if not (options and options.hover and options.hover.preferred_width ~= nil) then
    config.hover.preferred_width = math.max(
      config.hover.min_width,
      math.min(config.hover.max_width, config.hover.preferred_width)
    )
  end
  -- Lists are replacements, not maps. tbl_deep_extend would otherwise retain
  -- trailing default candidates when a user supplies a shorter order.
  if options and options.hover and options.hover.placement and options.hover.placement.order then
    config.hover.placement.order = vim.deepcopy(options.hover.placement.order)
  end
  validate(config)
  return config
end

return M
