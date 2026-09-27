local xml = require('imageui.util.xml')

local M = {}

local function display_text(text, start_col, tabstop)
  local output = {}
  local col = start_col
  for index = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, index, 1)
    if char == '\t' then
      local width = tabstop - (col % tabstop)
      output[#output + 1] = string.rep(' ', width)
      col = col + width
    elseif char == '\n' or char == '\r' then
      output[#output + 1] = ' '
      col = col + 1
    else
      output[#output + 1] = char
      col = col + vim.fn.strdisplaywidth(char, col)
    end
  end
  return table.concat(output), col - start_col
end

local function decoration(style)
  local values = {}
  if
    style.underline
    or style.undercurl
    or style.underdouble
    or style.underdotted
    or style.underdashed
  then
    values[#values + 1] = 'underline'
  end
  if style.strikethrough then
    values[#values + 1] = 'line-through'
  end
  return table.concat(values, ' ')
end

local function text_attrs(style, base, font_size, x, baseline, width, opacity)
  local attrs = {
    ('x="%.3f"'):format(x),
    ('y="%.3f"'):format(baseline),
    ('fill="%s"'):format(xml.escape(style.fg or base.fg or '#d0d0d0')),
    ('font-family="%s"'):format(
      xml.escape(
        (style.font_file or base.font_file) and 'ImageUIConfiguredFont'
          or style.font_family
          or base.font_family
          or 'monospace'
      )
    ),
    ('font-size="%.3f"'):format(font_size),
    ('font-weight="%s"'):format(style.bold and '700' or '400'),
    ('font-style="%s"'):format(style.italic and 'italic' or 'normal'),
    ('textLength="%.3f"'):format(math.max(0.001, width)),
    'lengthAdjust="spacingAndGlyphs"',
  }
  if opacity ~= nil then
    attrs[#attrs + 1] = ('fill-opacity="%.3f"'):format(opacity)
  end
  local decorations = decoration(style)
  if decorations ~= '' then
    attrs[#attrs + 1] = ('text-decoration="%s"'):format(decorations)
    attrs[#attrs + 1] = ('text-decoration-color="%s"'):format(
      xml.escape(style.sp or style.fg or base.fg or '#d0d0d0')
    )
    if style.undercurl then
      attrs[#attrs + 1] = 'text-decoration-style="wavy"'
    elseif style.underdouble then
      attrs[#attrs + 1] = 'text-decoration-style="double"'
    elseif style.underdotted then
      attrs[#attrs + 1] = 'text-decoration-style="dotted"'
    elseif style.underdashed then
      attrs[#attrs + 1] = 'text-decoration-style="dashed"'
    end
  end
  return attrs
end

local function emit_text(body, item, context, forced_text)
  local base = context.styles[item.highlight] or context.styles.Normal or {}
  local cell_width = context.cell_width * context.render_scale
  local cell_height = context.cell_height * context.render_scale
  local font_scale = item.font_scale or 1
  local font_size = cell_height * font_scale
  local pixel_height = item.height * cell_height
  local position = item.position or 'center'
  local baseline
  if position == 'top' then
    baseline = item.y * cell_height + font_size * 0.86
  elseif position == 'bottom' then
    baseline = item.y * cell_height + pixel_height - font_size * 0.16
  else
    baseline = item.y * cell_height + pixel_height / 2 + font_size * 0.34
  end
  local x = item.x * cell_width
  local display_col = 0
  local spans = forced_text and { { text = forced_text, highlight = item.highlight } } or item.spans
  for _, span in ipairs(spans) do
    local highlight = span.highlight or context.roles[span.role] or item.highlight
    local style = context.styles[highlight] or base
    local text, cells = display_text(span.text, display_col, context.tabstop)
    local span_scale = span.font_scale or font_scale
    local width = cells * cell_width * span_scale
    body[#body + 1] = ('<text %s>%s</text>'):format(
      table.concat(
        text_attrs(style, base, cell_height * span_scale, x, baseline, width, item.opacity),
        ' '
      ),
      xml.escape(text)
    )
    x = x + width
    display_col = display_col + cells
  end
end

local function emit_border(body, item, context)
  local chars = item.chars
  local width = math.max(1, math.floor(item.width + 0.5))
  local height = math.max(1, math.floor(item.height + 0.5))
  local cell_width = context.cell_width * context.render_scale
  local cell_height = context.cell_height * context.render_scale
  local function glyph(x, y, value, side)
    if not value or value == '' then
      return
    end
    local highlight = (item.highlights and item.highlights[side]) or item.highlight
    local style = context.styles[highlight] or context.styles.FloatBorder or {}
    if value == ' ' then
      local fill = style.bg or style.fg
      if fill then
        local opacity = item.opacity
        if opacity == nil then
          opacity = ((100 - (style.blend or 0)) / 100) * ((100 - (style.winblend or 0)) / 100)
        end
        body[#body + 1] = ('<rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="%s"%s/>'):format(
          x * cell_width,
          y * cell_height,
          cell_width,
          cell_height,
          xml.escape(fill),
          opacity < 1 and (' fill-opacity="%.3f"'):format(opacity) or ''
        )
      end
      return
    end
    emit_text(body, {
      x = x,
      y = y,
      width = 1,
      height = 1,
      highlight = highlight,
      font_scale = 1,
      position = 'center',
      opacity = item.opacity,
    }, context, value)
  end
  glyph(item.x, item.y, chars.top_left, 'top_left')
  if width > 1 then
    glyph(item.x + width - 1, item.y, chars.top_right, 'top_right')
  end
  for col = 1, width - 2 do
    glyph(item.x + col, item.y, chars.horizontal, 'horizontal')
  end
  if height > 1 then
    glyph(item.x, item.y + height - 1, chars.bottom_left, 'bottom_left')
    if width > 1 then
      glyph(item.x + width - 1, item.y + height - 1, chars.bottom_right, 'bottom_right')
    end
    for col = 1, width - 2 do
      glyph(item.x + col, item.y + height - 1, chars.bottom or chars.horizontal, 'bottom')
    end
  end
  for row = 1, height - 2 do
    glyph(item.x, item.y + row, chars.left or chars.vertical, 'left')
    if width > 1 then
      glyph(item.x + width - 1, item.y + row, chars.right or chars.vertical, 'right')
    end
  end
end

---@param compiled table
---@param context table
---@return string, table
function M.render(compiled, context)
  local cell_width = context.cell_width * context.render_scale
  local cell_height = context.cell_height * context.render_scale
  local pixel_width = compiled.width_cells * cell_width
  local pixel_height = compiled.height_cells * cell_height
  local body = {}
  for _, item in ipairs(compiled.display) do
    if item.kind == 'rect' then
      local style = context.styles[item.highlight] or context.styles.Normal or {}
      if style.bg then
        local opacity = item.opacity
        if opacity == nil then
          opacity = ((100 - (style.blend or 0)) / 100) * ((100 - (style.winblend or 0)) / 100)
        end
        body[#body + 1] = ('<rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" fill="%s"%s/>'):format(
          item.x * cell_width,
          item.y * cell_height,
          item.width * cell_width,
          item.height * cell_height,
          xml.escape(style.bg),
          opacity < 1 and (' fill-opacity="%.3f"'):format(opacity) or ''
        )
      end
    elseif item.kind == 'text' then
      emit_text(body, item, context)
    elseif item.kind == 'border' then
      emit_border(body, item, context)
    end
  end

  local font_file
  for _, style in pairs(context.styles) do
    font_file = font_file or style.font_file
  end
  local font_face = ''
  if font_file then
    font_face = ('<style>@font-face { font-family: "ImageUIConfiguredFont"; src: url("%s"); }</style>'):format(
      xml.escape(vim.uri_from_fname(vim.fs.abspath(font_file)))
    )
  end
  return table.concat({
    '<?xml version="1.0" encoding="UTF-8"?>',
    ('<svg xmlns="http://www.w3.org/2000/svg" xml:space="preserve" width="%d" height="%d" viewBox="0 0 %d %d">'):format(
      pixel_width,
      pixel_height,
      pixel_width,
      pixel_height
    ),
    font_face,
    '<g text-rendering="geometricPrecision">',
    table.concat(body, '\n'),
    '</g>',
    '</svg>',
  }, '\n'),
    {
      width_cells = compiled.width_cells,
      height_cells = compiled.height_cells,
      pixel_width = pixel_width,
      pixel_height = pixel_height,
      render_scale = context.render_scale,
    }
end

return M
