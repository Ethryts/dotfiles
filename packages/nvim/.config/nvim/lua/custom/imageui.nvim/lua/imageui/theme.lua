local M = {}

---@param value integer?
---@return string?
local function color(value)
  return value and ('#%06x'):format(value) or nil
end

---@param win integer
---@return table<string, string>
local function winhighlight(win)
  local mappings = {}
  local value = vim.wo[win].winhighlight
  for item in value:gmatch('[^,]+') do
    local from, to = item:match('^([^:]+):(.*)$')
    if from then
      mappings[from:lower()] = to
    end
  end
  return mappings
end

local function raw_hl(namespace, name)
  if name == '' then
    return {}
  end
  local ok, hl = pcall(vim.api.nvim_get_hl, namespace, {
    name = name,
    link = false,
    create = false,
  })
  if not ok then
    ok, hl = pcall(vim.api.nvim_get_hl, namespace, { name = name, link = false })
  end
  return ok and hl or {}
end

local function namespace_hl(namespace, name)
  local hl = raw_hl(namespace, name)
  if not vim.tbl_isempty(hl) or namespace == 0 then
    return hl, not vim.tbl_isempty(hl)
  end
  local ok, groups = pcall(vim.api.nvim_get_hl, namespace, {})
  if ok then
    for group, value in pairs(groups) do
      if group:lower() == name:lower() then
        return value, true
      end
    end
  end
  return {}, false
end

local function query_hl(namespace, name, seen)
  if name == '' then
    return {}, true
  end
  seen = seen or {}
  local cycle_key = namespace .. ':' .. name:lower()
  if seen[cycle_key] then
    return {}, true
  end
  seen[cycle_key] = true
  local hl, defined = namespace_hl(namespace, name)
  if hl.link then
    local linked, linked_defined = query_hl(namespace, hl.link, seen)
    if not linked_defined and namespace ~= 0 then
      linked, linked_defined = query_hl(0, hl.link, seen)
    end
    return linked, linked_defined
  end
  return hl, defined
end

---@param win integer
---@param name string
---@return table
local function get_hl(win, name)
  local namespace = vim.api.nvim_get_hl_ns({ winid = win })
  if namespace >= 0 then
    local hl, defined = query_hl(namespace, name)
    if defined then
      return hl
    end
    -- A window highlight namespace takes precedence over and disables
    -- 'winhighlight'. Missing groups fall back to the same global group.
    return query_hl(0, name)
  end

  local mapped = winhighlight(win)[name:lower()]
  return query_hl(0, mapped == nil and name or mapped)
end

---@param win integer
---@return string
local function normal_group(win)
  local win_config = vim.api.nvim_win_get_config(win)
  if win_config.relative ~= '' then
    return 'NormalFloat'
  end
  if win ~= vim.api.nvim_get_current_win() then
    return 'NormalNC'
  end
  return 'Normal'
end

---@param win integer
---@return table<string, string>
local function option(win, name, fallback)
  local ok, value = pcall(vim.api.nvim_get_option_value, name, { win = win })
  if ok then
    return value
  end
  return fallback
end

local border_presets = {
  none = false,
  single = { '┌', '─', '┐', '│', '┘', '─', '└', '│' },
  double = { '╔', '═', '╗', '║', '╝', '═', '╚', '║' },
  bold = { '┏', '━', '┓', '┃', '┛', '━', '┗', '┃' },
  rounded = { '╭', '─', '╮', '│', '╯', '─', '╰', '│' },
  solid = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
  shadow = {
    '',
    '',
    { ' ', 'FloatShadowThrough' },
    { ' ', 'FloatShadow' },
    { ' ', 'FloatShadow' },
    { ' ', 'FloatShadow' },
    { ' ', 'FloatShadowThrough' },
    '',
  },
}

local border_keys = {
  'top_left',
  'horizontal',
  'top_right',
  'right',
  'bottom_right',
  'bottom',
  'bottom_left',
  'left',
}

local function mapped_chars(value)
  if type(value) ~= 'table' then
    return nil
  end
  if value.top_left or value.horizontal then
    return {
      value.top_left or '╭',
      value.top or value.horizontal or '─',
      value.top_right or '╮',
      value.right or value.vertical or '│',
      value.bottom_right or '╯',
      value.bottom or value.horizontal or '─',
      value.bottom_left or '╰',
      value.left or value.vertical or '│',
    }
  end
  return value
end

local function normalized_chars(value)
  value = mapped_chars(value)
  local count = type(value) == 'table' and #value or 0
  if count == 0 or 8 % count ~= 0 then
    return nil
  end
  local chars = {}
  local highlights = {}
  for index = 1, 8 do
    local item = value[((index - 1) % count) + 1]
    chars[index] = type(item) == 'table' and item[1] or item
    if type(chars[index]) ~= 'string' then
      return nil
    end
    if type(item) == 'table' and type(item[2]) == 'string' and item[2] ~= '' then
      highlights[border_keys[index]] = item[2]
    end
  end
  local solid = true
  for _, char in ipairs(chars) do
    solid = solid and char == ' '
  end
  local result = {
    top_left = chars[1],
    horizontal = chars[2],
    top_right = chars[3],
    right = chars[4],
    bottom_right = chars[5],
    bottom = chars[6],
    bottom_left = chars[7],
    left = chars[8],
    vertical = chars[8],
    solid = solid,
    highlights = highlights,
    insets = {
      top = chars[2] ~= '' and 1 or 0,
      right = chars[4] ~= '' and 1 or 0,
      bottom = chars[6] ~= '' and 1 or 0,
      left = chars[8] ~= '' and 1 or 0,
    },
  }
  return result
end

local function string_border(value)
  if value == nil or value == '' or value == 'none' then
    return nil
  end
  if border_presets[value] ~= nil then
    return border_presets[value]
  end
  local parts = vim.split(value, ',', { plain = true })
  return 8 % #parts == 0 and parts or nil
end

local function editor_border(win)
  local win_config = vim.api.nvim_win_get_config(win)
  if
    win_config.relative ~= ''
    and type(win_config.border) == 'table'
    and #win_config.border > 0
  then
    return win_config.border, 'window'
  end
  local configured = option(win, 'winborder', '')
  return string_border(configured), configured == '' and 'none' or configured
end

---@param win integer
---@param border any
---@param config table
---@return table?
function M.resolve_border(win, border, config)
  local native_list = type(border) == 'table' and #border > 0
  local mapped_list = type(border) == 'table' and (border.top_left or border.horizontal)
  local spec = (native_list or mapped_list) and { style = 'custom', chars = vim.deepcopy(border) }
    or (type(border) == 'table' and vim.deepcopy(border) or { style = border })
  local style = spec.style or 'editor'
  style = style == true and 'editor' or style
  local chars = spec.chars and normalized_chars(spec.chars) or nil
  if not chars and config.style.box_chars then
    chars = normalized_chars(config.style.box_chars)
  end
  if not chars then
    if style == 'editor' then
      local source
      source, style = editor_border(win)
      chars = normalized_chars(source)
    else
      chars = normalized_chars(string_border(style))
    end
  end
  if not chars then
    return nil
  end
  local highlight = spec.highlight or 'FloatBorder'
  local highlights = {}
  for key, value in pairs(chars.highlights) do
    highlights[key] = spec.highlight or value
  end
  return {
    chars = chars,
    highlights = highlights,
    highlight = highlight,
    style = style,
    insets = vim.deepcopy(chars.insets),
  }
end

function M.border_fingerprint(win, borders, config)
  local parts = {}
  local highlight_names = {}
  for _, border in ipairs(borders or {}) do
    local resolved = M.resolve_border(win, border, config)
    if resolved then
      parts[#parts + 1] = resolved.highlight
      highlight_names[resolved.highlight] = true
      parts[#parts + 1] = resolved.style
      for _, key in ipairs(border_keys) do
        parts[#parts + 1] = resolved.chars[key]
        parts[#parts + 1] = resolved.highlights[key] or resolved.highlight
        highlight_names[resolved.highlights[key] or resolved.highlight] = true
      end
    else
      parts[#parts + 1] = 'none'
    end
  end
  local names = vim.tbl_keys(highlight_names)
  if #names > 0 then
    parts[#parts + 1] = M.fingerprint(win, names, config, false)
  end
  return table.concat(parts, '\0')
end

---@param win integer
---@param name string
---@param config table
---@param base_name? string
---@return table
function M.resolve(win, name, config, base_name)
  win = win == 0 and vim.api.nvim_get_current_win() or win
  local normal_name = base_name and base_name ~= 'Normal' and base_name or normal_group(win)
  local normal = get_hl(win, normal_name)
  if vim.tbl_isempty(normal) and normal_name ~= 'Normal' then
    normal = get_hl(win, 'Normal')
  end
  local effective_name = name == 'Normal' and normal_name or name
  local hl = get_hl(win, effective_name)
  local fg = hl.fg or normal.fg
  local bg = hl.bg or normal.bg
  if hl.reverse or hl.standout then
    fg, bg = bg, fg
  end

  return {
    name = name,
    normal = normal_name,
    fg = color(fg) or config.style.fallback_fg,
    bg = color(bg),
    sp = color(hl.sp or hl.fg or normal.fg) or config.style.fallback_fg,
    bold = hl.bold == true,
    italic = hl.italic == true,
    underline = hl.underline == true,
    undercurl = hl.undercurl == true,
    underdouble = hl.underdouble == true,
    underdotted = hl.underdotted == true,
    underdashed = hl.underdashed == true,
    strikethrough = hl.strikethrough == true,
    blend = hl.blend or 0,
    font_family = config.style.font_family,
    font_file = config.style.font_file,
    cell_width = config.style.cell_width,
    cell_height = config.style.cell_height,
    winblend = option(win, 'winblend', 0),
    box_chars = (M.resolve_border(win, { style = 'rounded' }, config) or {}).chars,
  }
end

local fingerprint_fields = {
  'normal',
  'fg',
  'bg',
  'sp',
  'bold',
  'italic',
  'underline',
  'undercurl',
  'underdouble',
  'underdotted',
  'underdashed',
  'strikethrough',
  'blend',
  'font_family',
  'font_file',
  'cell_width',
  'cell_height',
  'winblend',
}

local text_fingerprint_fields = {
  'fg',
  'sp',
  'bold',
  'italic',
  'underline',
  'undercurl',
  'underdouble',
  'underdotted',
  'underdashed',
  'strikethrough',
  'font_family',
  'font_file',
  'cell_width',
  'cell_height',
}

---@param win integer
---@param materials table<string, table<string, boolean>>
---@param config table
---@param base_name? string
---@return string
function M.material_fingerprint(win, materials, config, base_name)
  local parts = {}
  local names = vim.tbl_keys(materials)
  table.sort(names)
  for _, name in ipairs(names) do
    local style = M.resolve(win, name, config, base_name)
    parts[#parts + 1] = name
    local fields = vim.tbl_keys(materials[name])
    table.sort(fields)
    for _, field in ipairs(fields) do
      parts[#parts + 1] = field
      parts[#parts + 1] = tostring(style[field])
    end
  end
  return vim.fn.sha256(table.concat(parts, '\0'))
end

---@param win integer
---@param names string[]
---@param config table
---@param rendered_text_only? boolean
---@return string
function M.fingerprint(win, names, config, rendered_text_only)
  local parts = {}
  names = vim.deepcopy(names)
  table.sort(names)
  local snapshot = M.snapshot(win, names, config)
  for _, name in ipairs(names) do
    local style = snapshot[name]
    parts[#parts + 1] = name
    for _, field in ipairs(rendered_text_only and text_fingerprint_fields or fingerprint_fields) do
      parts[#parts + 1] = tostring(style[field])
    end
    if not rendered_text_only then
      for _, key in ipairs({
        'horizontal',
        'vertical',
        'top_left',
        'top_right',
        'bottom_left',
        'bottom_right',
      }) do
        parts[#parts + 1] = tostring(style.box_chars[key])
      end
    end
  end
  return vim.fn.sha256(table.concat(parts, '\0'))
end

---@param win integer
---@param names string[]
---@param config table
---@param base_name? string
---@return table<string, table>
function M.snapshot(win, names, config, base_name)
  local result = {}
  for _, name in ipairs(names) do
    result[name] = M.resolve(win, name, config, base_name)
  end
  return result
end

return M
