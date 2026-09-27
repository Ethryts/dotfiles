local xml = require('imageui.util.xml')

local M = {}

---@class ImageUI.TextSpan
---@field text string
---@field style? table
---@field highlight? string

---@class ImageUI.TextScene
---@field kind 'text'
---@field spans ImageUI.TextSpan[]
---@field style table
---@field styles? table<string, table>
---@field font_scale? number
---@field position? 'top'|'center'|'bottom'
---@field padding? {left?: number, right?: number, top?: number, bottom?: number}
---@field background? string|false
---@field opacity? number
---@field min_width_cells? integer
---@field height_cells? integer

---@param text string
---@param start_col integer
---@param tabstop integer
---@return string, integer
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

---@param scene ImageUI.TextScene
---@return string svg
---@return table metrics
function M.text(scene)
  local base = scene.style
  local scale = scene.font_scale or 1
  local render_scale = scene.render_scale or 1
  local cell_width = base.cell_width * render_scale
  local cell_height = base.cell_height * render_scale
  local font_size = cell_height * scale
  local padding =
    vim.tbl_extend('force', { left = 1, right = 1, top = 0, bottom = 0 }, scene.padding or {})
  local x = padding.left * render_scale
  local spans = {}
  local display_col = 0
  local tabstop = scene.tabstop or 8

  for _, span in ipairs(scene.spans) do
    local style = span.style or (scene.styles and scene.styles[span.highlight]) or base
    local text, cells = display_text(span.text, display_col, tabstop)
    local width = cells * cell_width * scale
    spans[#spans + 1] = {
      text = text,
      style = style,
      x = x,
      width = width,
    }
    x = x + width
    display_col = display_col + cells
  end

  local content_width = x + padding.right * render_scale
  local width_cells = math.max(scene.min_width_cells or 1, math.ceil(content_width / cell_width))
  local height_cells = scene.height_cells or 1
  local pixel_width = width_cells * cell_width
  local pixel_height = height_cells * cell_height
  local position = scene.position or 'center'
  local baseline
  if position == 'top' then
    baseline = padding.top * render_scale + font_size * 0.86
  elseif position == 'bottom' then
    baseline = pixel_height - padding.bottom * render_scale - font_size * 0.16
  else
    baseline = (pixel_height / 2) + (font_size * 0.34)
  end

  local body = {}
  local font_face = ''
  if base.font_file then
    local uri = vim.uri_from_fname(vim.fs.abspath(base.font_file))
    font_face = ('<style>@font-face { font-family: "ImageUIConfiguredFont"; src: url("%s"); }</style>'):format(
      xml.escape(uri)
    )
  end
  if scene.background and scene.background ~= false then
    body[#body + 1] = ('<rect width="100%%" height="100%%" fill="%s" fill-opacity="%s"/>'):format(
      xml.escape(scene.background),
      scene.opacity or 1
    )
  end

  for _, span in ipairs(spans) do
    local style = span.style
    local attrs = {
      ('x="%.3f"'):format(span.x),
      ('y="%.3f"'):format(baseline),
      ('fill="%s"'):format(xml.escape(style.fg or base.fg)),
      ('font-family="%s"'):format(
        xml.escape(
          (style.font_file or base.font_file) and 'ImageUIConfiguredFont'
            or style.font_family
            or base.font_family
        )
      ),
      ('font-size="%.3f"'):format(font_size),
      ('font-weight="%s"'):format(style.bold and '700' or '400'),
      ('font-style="%s"'):format(style.italic and 'italic' or 'normal'),
      ('textLength="%.3f"'):format(span.width),
      'lengthAdjust="spacingAndGlyphs"',
    }
    local decorations = {}
    if style.underline then
      decorations[#decorations + 1] = 'underline'
      attrs[#attrs + 1] = ('text-decoration-color="%s"'):format(xml.escape(style.sp or style.fg))
    elseif style.undercurl then
      decorations[#decorations + 1] = 'underline'
      attrs[#attrs + 1] = 'text-decoration-style="wavy"'
      attrs[#attrs + 1] = ('text-decoration-color="%s"'):format(xml.escape(style.sp or style.fg))
    elseif style.underdouble then
      decorations[#decorations + 1] = 'underline'
      attrs[#attrs + 1] = 'text-decoration-style="double"'
      attrs[#attrs + 1] = ('text-decoration-color="%s"'):format(xml.escape(style.sp or style.fg))
    elseif style.underdotted then
      decorations[#decorations + 1] = 'underline'
      attrs[#attrs + 1] = 'text-decoration-style="dotted"'
      attrs[#attrs + 1] = ('text-decoration-color="%s"'):format(xml.escape(style.sp or style.fg))
    elseif style.underdashed then
      decorations[#decorations + 1] = 'underline'
      attrs[#attrs + 1] = 'text-decoration-style="dashed"'
      attrs[#attrs + 1] = ('text-decoration-color="%s"'):format(xml.escape(style.sp or style.fg))
    end
    if style.strikethrough then
      decorations[#decorations + 1] = 'line-through'
    end
    if #decorations > 0 then
      attrs[#attrs + 1] = ('text-decoration="%s"'):format(table.concat(decorations, ' '))
    end
    body[#body + 1] = ('<text %s>%s</text>'):format(table.concat(attrs, ' '), xml.escape(span.text))
  end

  local svg = table.concat({
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
  }, '\n')

  return svg,
    {
      width_cells = width_cells,
      height_cells = height_cells,
      pixel_width = pixel_width,
      pixel_height = pixel_height,
      render_scale = render_scale,
    }
end

return M
