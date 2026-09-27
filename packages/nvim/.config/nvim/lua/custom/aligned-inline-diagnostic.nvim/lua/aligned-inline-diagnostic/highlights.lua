local M = {}

local severities = {
  Error = "DiagnosticError",
  Warn = "DiagnosticWarn",
  Info = "DiagnosticInfo",
  Hint = "DiagnosticHint",
}

local edge_runtime = nil

local function get_hl(name)
  local ok, value = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and value or {}
end

local function blend_channel(background, foreground, amount)
  return math.floor(background + ((foreground - background) * amount) + 0.5)
end

local function blend(background, foreground, amount)
  if not background or not foreground then
    return nil
  end

  local br = math.floor(background / 0x10000) % 0x100
  local bg = math.floor(background / 0x100) % 0x100
  local bb = background % 0x100
  local fr = math.floor(foreground / 0x10000) % 0x100
  local fg = math.floor(foreground / 0x100) % 0x100
  local fb = foreground % 0x100

  return (blend_channel(br, fr, amount) * 0x10000)
    + (blend_channel(bg, fg, amount) * 0x100)
    + blend_channel(bb, fb, amount)
end

local function resolve_color(value)
  if type(value) == "number" then
    return value
  end
  if type(value) ~= "string" then
    return nil
  end
  local hex = value:match("^#(%x%x%x%x%x%x)$")
  if hex then
    return tonumber(hex, 16)
  end
  local highlight = get_hl(value)
  return highlight.bg or highlight.fg
end

local function linear_channel(value)
  value = value / 255
  return value <= 0.04045 and (value / 12.92) or (((value + 0.055) / 1.055) ^ 2.4)
end

local function luminance(color)
  if not color then
    return nil
  end
  local red = math.floor(color / 0x10000) % 0x100
  local green = math.floor(color / 0x100) % 0x100
  local blue = color % 0x100
  return (0.2126 * linear_channel(red))
    + (0.7152 * linear_channel(green))
    + (0.0722 * linear_channel(blue))
end

local function contrast_ratio(left, right)
  local a = luminance(left)
  local b = luminance(right)
  if not a or not b then
    return 0
  end
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05)
end

local function readable_foreground(preferred, background, appearance)
  if not appearance.ensure_contrast or not background then
    return preferred
  end
  local minimum = appearance.minimum_contrast or 3
  if preferred and contrast_ratio(preferred, background) >= minimum then
    return preferred
  end
  local light = 0xf2f2f2
  local dark = 0x202020
  if contrast_ratio(light, background) >= contrast_ratio(dark, background) then
    return light
  end
  return dark
end

local function set(name, spec)
  vim.api.nvim_set_hl(0, name, spec)
end

local function as_spec(spec)
  return type(spec) == "string" and { link = spec } or spec
end

local function window_option(name, winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return nil
  end
  local scope = { win = winid }
  if name == "textwidth" then
    local buffer_ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
    if not buffer_ok then
      return nil
    end
    scope = { buf = bufnr }
  end
  local ok, value = pcall(vim.api.nvim_get_option_value, name, scope)
  return ok and value or nil
end

local function colorcolumns(winid)
  local result = {}
  local maximum = nil
  local value = window_option("colorcolumn", winid)
  if type(value) ~= "string" or value == "" then
    return result, maximum
  end
  local textwidth = window_option("textwidth", winid) or 0
  for item in value:gmatch("[^,]+") do
    local column
    if textwidth > 0 and item:match("^[+-]%d+$") then
      column = textwidth + tonumber(item)
    elseif not item:match("^[+-]") then
      column = tonumber(item)
    end
    if column and column > 0 then
      result[column] = true
      maximum = maximum and math.max(maximum, column) or column
    end
  end
  return result, maximum
end

-- Resolve window-local edge regions once for a batch of virtual-text cells.
-- Callers may pass the returned descriptor to edge_group() as
-- context.edge_descriptor. Keeping this separate from edge_group() matters for
-- aligned previews, where a long padding run would otherwise query two window
-- options for every cell.
function M.prepare_edge_descriptor(source_win)
  local columns, maximum = colorcolumns(source_win)
  return {
    source_win = source_win,
    columns = columns,
    maximum = maximum,
  }
end

local function edge_region(context, options)
  local descriptor = context.edge_descriptor
  if descriptor and descriptor.source_win ~= context.source_win then
    descriptor = nil
  end
  local columns, maximum
  if descriptor then
    columns = descriptor.columns or {}
    maximum = descriptor.maximum
  else
    columns, maximum = colorcolumns(context.source_win)
  end
  local overflow_column = options.overflow_column or maximum
  local column = context.virtual_column
  if column and overflow_column and column > overflow_column then
    return "overflow"
  end
  if column and options.respect_colorcolumn and columns[column] then
    return "colorcolumn"
  end
  return "normal"
end

local function edge_base_group(view, severity_key, inactive)
  if view == "hover" then
    return "AlignedDiagnosticFloatCap" .. severity_key
  end
  return (inactive and "AlignedDiagnosticInactiveCap" or "AlignedDiagnosticCap") .. severity_key
end

local function resolved_edge_value(context, options)
  local region = edge_region(context, options)
  local customized = false
  context.region = region
  local value = options[region]
  if type(options.resolve) == "function" then
    local ok, resolved = pcall(options.resolve, context)
    if ok and resolved ~= nil then
      if resolved == "normal" or resolved == "colorcolumn" or resolved == "overflow" then
        region = resolved
        context.region = region
        value = options[region]
      else
        value = resolved
        customized = true
      end
    elseif not ok and edge_runtime and not edge_runtime.resolve_error_notified then
      edge_runtime.resolve_error_notified = true
      local runtime = edge_runtime
      vim.schedule(function()
        if edge_runtime == runtime then
          vim.notify(
            "aligned-inline-diagnostic appearance.edge_underlay.resolve: " .. tostring(resolved),
            vim.log.levels.ERROR
          )
        end
      end)
    end
  end
  return region, value, customized
end

local function apply_overrides(overrides)
  for name, spec in pairs(overrides) do
    set(name, as_spec(spec))
  end

  -- Generic role overrides flow to per-severity groups unless the latter has
  -- an explicit value. This keeps theme integrations small and predictable.
  for _, base in ipairs({
    "AlignedDiagnosticPreviewBody",
    "AlignedDiagnosticPreviewIcon",
    "AlignedDiagnosticPreviewCount",
    "AlignedDiagnosticCap",
    "AlignedDiagnosticInactiveBody",
    "AlignedDiagnosticInactiveIcon",
    "AlignedDiagnosticInactiveCount",
    "AlignedDiagnosticInactiveCap",
    "AlignedDiagnosticFloatBody",
    "AlignedDiagnosticFloatMessage",
    "AlignedDiagnosticFloatMetadata",
    "AlignedDiagnosticFloatDetail",
    "AlignedDiagnosticFloatCode",
    "AlignedDiagnosticFloatCap",
    "AlignedDiagnosticHover",
    "AlignedDiagnosticActiveRange",
  }) do
    local spec = overrides[base]
    if spec then
      spec = as_spec(spec)
      for key in pairs(severities) do
        if overrides[base .. key] == nil then
          set(base .. key, spec)
        end
      end
    end
  end

  -- Before message/metadata roles existed, FloatBody styled every non-detail
  -- character. Preserve that reach unless a new role has an explicit value.
  for key in pairs(severities) do
    local body = overrides["AlignedDiagnosticFloatBody" .. key]
      or overrides.AlignedDiagnosticFloatBody
    if body then
      body = as_spec(body)
      for _, role in ipairs({ "Message", "Metadata", "Code" }) do
        local generic = "AlignedDiagnosticFloat" .. role
        if overrides[generic] == nil and overrides[generic .. key] == nil then
          set(generic .. key, body)
        end
      end
    end
    local detail = overrides["AlignedDiagnosticFloatDetail" .. key]
      or overrides.AlignedDiagnosticFloatDetail
    if
      detail
      and overrides.AlignedDiagnosticFloatMetadata == nil
      and overrides["AlignedDiagnosticFloatMetadata" .. key] == nil
    then
      set("AlignedDiagnosticFloatMetadata" .. key, as_spec(detail))
    end
  end

  -- Published legacy groups remain canonical overrides for the new preview
  -- roles. New role-specific values always win when both are supplied.
  for key in pairs(severities) do
    local legacy = overrides["AlignedDiagnostic" .. key]
    if legacy then
      legacy = as_spec(legacy)
      for _, role in ipairs({ "PreviewBody", "PreviewIcon", "PreviewCount" }) do
        local name = "AlignedDiagnostic" .. role .. key
        if overrides[name] == nil and overrides["AlignedDiagnostic" .. role] == nil then
          set(name, legacy)
        end
      end
    end
  end
end

function M.edge_group(view, severity, inactive, context)
  local severity_key = type(severity) == "string" and severity or "Info"
  local base = edge_base_group(view, severity_key, inactive)
  if not edge_runtime then
    return base
  end

  context = context or {}
  context.view = view
  context.severity = severity_key:lower()
  context.inactive = inactive == true
  local region, value, customized = resolved_edge_value(context, edge_runtime.options)

  -- Native ColorColumn and other window highlights can flow through inline
  -- virtual text when the cap group has no background and hl_mode=combine.
  if
    view == "preview"
    and edge_runtime.options.combine
    and not customized
    and (region == "normal" or region == "colorcolumn")
    and value ~= "inherit"
  then
    return base
  end
  if value == "inherit" then
    return base
  end

  local background = resolve_color(value)
  if not background then
    if view == "preview" and edge_runtime.options.combine then
      return base
    end
    background = edge_runtime.canvas_background
  end

  local key =
    table.concat({ view, severity_key, inactive and "inactive" or "active", background }, ":")
  if edge_runtime.cache[key] then
    return edge_runtime.cache[key]
  end

  edge_runtime.serial = edge_runtime.serial + 1
  local name = "AlignedDiagnosticResolvedEdge" .. edge_runtime.serial
  local source = get_hl(base)
  local spec = {}
  for attribute, attribute_value in pairs(source) do
    if attribute ~= "bg" and attribute ~= "link" then
      spec[attribute] = attribute_value
    end
  end
  spec.bg = background
  set(name, spec)
  edge_runtime.cache[key] = name
  return name
end

function M.setup(config)
  edge_runtime = nil
  config = config or {}
  local appearance = config.appearance or {}
  local normal = get_hl("Normal")
  local normal_float = get_hl("NormalFloat")
  local cursor_line = get_hl("CursorLine")
  local comment = get_hl("Comment")
  local light_background = vim.o and vim.o.background == "light"
  local canvas_background = normal.bg
    or normal_float.bg
    or cursor_line.bg
    or (light_background and 0xf2f2f2 or 0x202020)
  local canvas_foreground = normal.fg
    or normal_float.fg
    or (light_background and 0x202020 or 0xd8d8d8)
  local shared_hover_background = resolve_color(appearance.hover_background)
  local shared_hover_tint = resolve_color(appearance.hover_tint)
  local hover_backgrounds = {}
  local preview_backgrounds = {}

  for key, source_name in pairs(severities) do
    local lower = key:lower()
    local diagnostic = get_hl(source_name)
    local virtual = get_hl("DiagnosticVirtualText" .. key)
    local severity_foreground = diagnostic.fg or virtual.fg or canvas_foreground
    local preview_tint = resolve_color((appearance.preview_tints or {})[lower])
      or severity_foreground
    local preview_background = resolve_color((appearance.preview_backgrounds or {})[lower])
      or blend(canvas_background, preview_tint, appearance.preview_blend or 0.14)
      or virtual.bg
      or cursor_line.bg
      or canvas_background
    local severity_tint = resolve_color((appearance.hover_tints or {})[lower])
    local hover_background = resolve_color((appearance.hover_backgrounds or {})[lower])
      or shared_hover_background
      or blend(
        canvas_background,
        shared_hover_tint or severity_tint or severity_foreground,
        appearance.hover_blend or 0.12
      )
      or cursor_line.bg
      or normal_float.bg
      or canvas_background
    local preview_foreground =
      readable_foreground(canvas_foreground, preview_background, appearance)
    local hover_foreground = readable_foreground(canvas_foreground, hover_background, appearance)
    local preview_meta =
      blend(preview_background, preview_foreground, appearance.metadata_blend or 0.58)
    local hover_meta = blend(hover_background, hover_foreground, appearance.metadata_blend or 0.58)
    local inactive_background =
      blend(preview_background, canvas_background, appearance.inactive_blend or 0.55)
    local inactive_foreground =
      blend(preview_foreground, canvas_background, appearance.inactive_blend or 0.55)
    local inactive_severity =
      blend(severity_foreground, canvas_background, appearance.inactive_blend or 0.55)

    hover_backgrounds[key] = hover_background
    preview_backgrounds[key] = preview_background

    -- Legacy preview groups are retained. New roles give the message neutral
    -- contrast while color remains concentrated in the glyph and surface.
    set("AlignedDiagnostic" .. key, { fg = severity_foreground, bg = preview_background })
    set("AlignedDiagnosticPreviewBody" .. key, {
      fg = preview_foreground,
      bg = preview_background,
    })
    set("AlignedDiagnosticPreviewIcon" .. key, {
      fg = severity_foreground,
      bg = preview_background,
      bold = diagnostic.bold,
    })
    set("AlignedDiagnosticPreviewCount" .. key, { fg = preview_meta, bg = preview_background })
    set("AlignedDiagnosticCap" .. key, { fg = preview_background or severity_foreground })
    set("AlignedDiagnosticInactiveBody" .. key, {
      fg = inactive_foreground,
      bg = inactive_background,
    })
    set("AlignedDiagnosticInactiveIcon" .. key, {
      fg = inactive_severity,
      bg = inactive_background,
    })
    set("AlignedDiagnosticInactiveCount" .. key, {
      fg = blend(inactive_background, inactive_foreground, appearance.metadata_blend or 0.58),
      bg = inactive_background,
    })
    set("AlignedDiagnosticInactiveCap" .. key, { fg = inactive_background })

    set("AlignedDiagnosticHover" .. key, {
      fg = severity_foreground,
      bg = hover_background,
      bold = diagnostic.bold,
    })
    set("AlignedDiagnosticFloatBody" .. key, { fg = hover_foreground, bg = hover_background })
    set("AlignedDiagnosticFloatMessage" .. key, {
      fg = hover_foreground,
      bg = hover_background,
    })
    set("AlignedDiagnosticFloatMetadata" .. key, {
      fg = hover_meta,
      bg = hover_background,
      italic = comment.italic,
    })
    set("AlignedDiagnosticFloatDetail" .. key, {
      fg = hover_meta,
      bg = hover_background,
      italic = comment.italic,
    })
    set("AlignedDiagnosticFloatCode" .. key, {
      fg = readable_foreground(severity_foreground, hover_background, appearance),
      bg = hover_background,
    })
    set("AlignedDiagnosticFloatCap" .. key, { fg = hover_background, bg = canvas_background })
    set("AlignedDiagnosticActiveRange" .. key, {
      bg = blend(canvas_background, severity_foreground, appearance.active_blend or 0.10),
    })
  end

  local fallback_key = hover_backgrounds.Info and "Info"
    or (hover_backgrounds.Hint and "Hint")
    or (hover_backgrounds.Warn and "Warn")
    or "Error"
  local fallback_hover_background = hover_backgrounds[fallback_key]
  local fallback_preview_background = preview_backgrounds[fallback_key]

  set("AlignedDiagnosticFloat", { fg = canvas_foreground, bg = canvas_background })
  set("AlignedDiagnosticFloatBody", { fg = canvas_foreground, bg = fallback_hover_background })
  set("AlignedDiagnosticFloatMessage", { fg = canvas_foreground, bg = fallback_hover_background })
  set("AlignedDiagnosticFloatMetadata", {
    fg = comment.fg or canvas_foreground,
    bg = fallback_hover_background,
    italic = comment.italic,
  })
  set("AlignedDiagnosticFloatDetail", {
    fg = comment.fg or canvas_foreground,
    bg = fallback_hover_background,
    italic = comment.italic,
  })
  set("AlignedDiagnosticFloatCode", { fg = canvas_foreground, bg = fallback_hover_background })
  set("AlignedDiagnosticFloatCap", { fg = fallback_hover_background, bg = canvas_background })
  set("AlignedDiagnosticBorder", { fg = fallback_hover_background, bg = canvas_background })
  set("AlignedDiagnosticPreviewBody", { fg = canvas_foreground, bg = fallback_preview_background })
  set("AlignedDiagnosticPreviewIcon", { fg = canvas_foreground, bg = fallback_preview_background })
  set("AlignedDiagnosticPreviewCount", { fg = canvas_foreground, bg = fallback_preview_background })
  set("AlignedDiagnosticCap", { fg = fallback_preview_background })
  set("AlignedDiagnosticInactiveBody", { fg = canvas_foreground, bg = canvas_background })
  set("AlignedDiagnosticInactiveIcon", { fg = canvas_foreground, bg = canvas_background })
  set("AlignedDiagnosticInactiveCount", { fg = canvas_foreground, bg = canvas_background })
  set("AlignedDiagnosticInactiveCap", { fg = canvas_background })
  set("AlignedDiagnosticHover", { fg = canvas_foreground, bg = fallback_hover_background })
  set("AlignedDiagnosticActiveRange", {
    bg = blend(canvas_background, canvas_foreground, appearance.active_blend or 0.10),
  })

  apply_overrides(config.highlights or {})
  edge_runtime = {
    options = appearance.edge_underlay or {
      combine = true,
      normal = "Normal",
      colorcolumn = "ColorColumn",
      overflow = "PastColorColumn",
      overflow_column = nil,
      respect_colorcolumn = true,
    },
    canvas_background = canvas_background,
    cache = {},
    serial = 0,
    resolve_error_notified = false,
  }
end

return M
