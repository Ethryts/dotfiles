local scene = require('imageui.scene')

local M = {}

local function padding(value)
  if type(value) == 'number' then
    return { left = value, right = value, top = value, bottom = value }
  end
  return vim.tbl_extend('force', { left = 0, right = 0, top = 0, bottom = 0 }, value or {})
end

local function display_text(text, start_col, tabstop)
  local col = start_col
  for index = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, index, 1)
    if char == '\t' then
      col = col + tabstop - (col % tabstop)
    elseif char == '\n' or char == '\r' then
      col = col + 1
    else
      col = col + vim.fn.strdisplaywidth(char, col)
    end
  end
  return col - start_col
end

local function text_metrics(node, tabstop)
  local display_col = 0
  local width = 0
  local height = node.font_scale or 1
  for _, span in ipairs(node.spans or { { text = node.text or '' } }) do
    local cells = display_text(span.text, display_col, tabstop)
    local scale = span.font_scale or node.font_scale or 1
    display_col = display_col + cells
    width = width + cells * scale
    height = math.max(height, scale)
  end
  return width, height
end

local function explicit(node, name)
  return node[name] or node[name .. '_cells']
end

local function measure(node, context, inherited)
  local result = {
    node = node,
    highlight = scene.highlight(node, inherited),
    children = {},
  }
  if node.type == 'text' then
    local width, height = text_metrics(node, context.tabstop)
    result.width = math.max(explicit(node, 'width') or 0, width)
    result.height = math.max(explicit(node, 'height') or 0, height)
  elseif node.type == 'spacer' then
    result.width = explicit(node, 'width') or 0
    result.height = explicit(node, 'height') or 0
  elseif node.type == 'stack' then
    local direction = node.direction or 'vertical'
    local gap = node.gap or 0
    for _, child in ipairs(node.children) do
      result.children[#result.children + 1] = measure(child, context, result.highlight)
    end
    if direction == 'horizontal' then
      result.width = math.max(0, (#result.children - 1) * gap)
      result.height = 0
      for _, child in ipairs(result.children) do
        result.width = result.width + child.width
        result.height = math.max(result.height, child.height)
      end
    else
      result.width = 0
      result.height = math.max(0, (#result.children - 1) * gap)
      for _, child in ipairs(result.children) do
        result.width = math.max(result.width, child.width)
        result.height = result.height + child.height
      end
    end
    result.width = math.max(result.width, explicit(node, 'width') or 0)
    result.height = math.max(result.height, explicit(node, 'height') or 0)
  elseif node.type == 'box' then
    result.padding = padding(node.padding)
    result.border = node.border and context.resolve_border(node.border) or nil
    result.border_insets = result.border and result.border.insets
      or { top = 0, right = 0, bottom = 0, left = 0 }
    result.children[1] = measure(node.child, context, result.highlight)
    local child = result.children[1]
    result.width = child.width
      + result.padding.left
      + result.padding.right
      + result.border_insets.left
      + result.border_insets.right
    result.height = child.height
      + result.padding.top
      + result.padding.bottom
      + result.border_insets.top
      + result.border_insets.bottom
    result.width = math.max(result.width, explicit(node, 'width') or 0)
    result.height = math.max(result.height, explicit(node, 'height') or 0)
    if result.border then
      result.width = math.ceil(result.width)
      result.height = math.ceil(result.height)
    end
  end
  return result
end

local function align_offset(available, size, alignment)
  if alignment == 'center' then
    return (available - size) / 2
  elseif alignment == 'end' then
    return available - size
  end
  return 0
end

local function add_region(output, measured, x, y, width, height)
  local node = measured.node
  if not node.id then
    return
  end
  output.paint_order = output.paint_order + 1
  output.regions[#output.regions + 1] = {
    id = node.id,
    visual = { x = x, y = y, width = width, height = height },
    hit_rect = vim.deepcopy(node.hit_rect or node.hitbox),
    focusable = node.focusable == true,
    disabled = node.disabled == true,
    pointer = node.pointer or 'auto',
    paint_order = output.paint_order,
  }
end

local function place(measured, x, y, width, height, output)
  local node = measured.node
  width = width or measured.width
  height = height or measured.height
  add_region(output, measured, x, y, width, height)
  if node.background then
    output.display[#output.display + 1] = {
      kind = 'rect',
      x = x,
      y = y,
      width = width,
      height = height,
      highlight = measured.highlight,
      opacity = node.opacity,
    }
  end
  if node.type == 'text' then
    output.display[#output.display + 1] = {
      kind = 'text',
      x = x,
      y = y,
      width = width,
      height = height,
      highlight = measured.highlight,
      spans = vim.deepcopy(node.spans or { { text = node.text or '' } }),
      font_scale = node.font_scale or 1,
      position = node.position or 'center',
      opacity = node.opacity,
    }
  elseif node.type == 'stack' then
    local direction = node.direction or 'vertical'
    local gap = node.gap or 0
    local natural_main = math.max(0, (#measured.children - 1) * gap)
    for _, child in ipairs(measured.children) do
      natural_main = natural_main + (direction == 'horizontal' and child.width or child.height)
    end
    local available_main = direction == 'horizontal' and width or height
    local extra = math.max(0, available_main - natural_main)
    local cursor = (node.justify == 'center' and extra / 2)
      or (node.justify == 'end' and extra)
      or 0
    local actual_gap = gap
    if node.justify == 'space_between' and #measured.children > 1 then
      actual_gap = gap + extra / (#measured.children - 1)
      cursor = 0
    end
    for _, child in ipairs(measured.children) do
      if direction == 'horizontal' then
        local child_height = node.align == 'stretch' and height or child.height
        local child_y = y + align_offset(height, child_height, node.align)
        place(child, x + cursor, child_y, child.width, child_height, output)
        cursor = cursor + child.width + actual_gap
      else
        local child_width = node.align == 'stretch' and width or child.width
        local child_x = x + align_offset(width, child_width, node.align)
        place(child, child_x, y + cursor, child_width, child.height, output)
        cursor = cursor + child.height + actual_gap
      end
    end
  elseif node.type == 'box' then
    local child = measured.children[1]
    local insets = measured.border_insets
    local inner_x = x + insets.left + measured.padding.left
    local inner_y = y + insets.top + measured.padding.top
    local inner_width = width
      - insets.left
      - insets.right
      - measured.padding.left
      - measured.padding.right
    local inner_height = height
      - insets.top
      - insets.bottom
      - measured.padding.top
      - measured.padding.bottom
    local child_width = node.align == 'stretch' and inner_width or child.width
    local child_height = node.valign == 'stretch' and inner_height or child.height
    place(
      child,
      inner_x + align_offset(inner_width, child_width, node.align),
      inner_y + align_offset(inner_height, child_height, node.valign),
      child_width,
      child_height,
      output
    )
    if measured.border then
      output.display[#output.display + 1] = {
        kind = 'border',
        x = x,
        y = y,
        width = width,
        height = height,
        highlight = measured.border.highlight or 'FloatBorder',
        highlights = vim.deepcopy(measured.border.highlights),
        chars = measured.border.chars,
        opacity = node.opacity,
      }
    end
  end
end

---@param root table
---@param context {tabstop: integer, resolve_border: fun(border: any): table?}
---@return table
function M.compile(root, context)
  local measured = measure(root, context, 'Normal')
  local output = { display = {}, regions = {}, paint_order = 0 }
  place(measured, 0, 0, measured.width, measured.height, output)
  return {
    width_cells = math.max(1, math.ceil(measured.width)),
    height_cells = math.max(1, math.ceil(measured.height)),
    display = output.display,
    regions = output.regions,
  }
end

return M
