local M = {}

M.roles = {
  inline = 'Normal',
  float = 'NormalFloat',
  float_border = 'FloatBorder',
  float_title = 'FloatTitle',
  float_footer = 'FloatFooter',
  selection = 'Visual',
  cursorline = 'CursorLine',
  menu = 'Pmenu',
  menu_selected = 'PmenuSel',
  muted = 'Comment',
  link = 'Underlined',
  codelens = 'LspCodeLens',
  diagnostic_error = 'DiagnosticError',
  diagnostic_warn = 'DiagnosticWarn',
  diagnostic_info = 'DiagnosticInfo',
  diagnostic_hint = 'DiagnosticHint',
}

local floating_roles = {
  diagnostic_error = 'DiagnosticFloatingError',
  diagnostic_warn = 'DiagnosticFloatingWarn',
  diagnostic_info = 'DiagnosticFloatingInfo',
  diagnostic_hint = 'DiagnosticFloatingHint',
}

---@param role string
---@param appearance? 'inline'|'float'|'menu'
---@return string?
function M.role_highlight(role, appearance)
  if appearance == 'float' and floating_roles[role] then
    return floating_roles[role]
  end
  return M.roles[role]
end

local node_types = { text = true, stack = true, box = true, spacer = true }
local state_fields = {
  background = true,
  highlight = true,
  opacity = true,
  role = true,
}

local function constructor(kind, opts)
  opts = vim.deepcopy(opts or {})
  opts.type = kind
  return opts
end

function M.text(opts)
  if type(opts) == 'string' then
    opts = { text = opts }
  end
  return constructor('text', opts)
end

function M.stack(opts)
  return constructor('stack', opts)
end

function M.row(opts)
  opts = vim.deepcopy(opts or {})
  opts.direction = 'horizontal'
  return constructor('stack', opts)
end

function M.column(opts)
  opts = vim.deepcopy(opts or {})
  opts.direction = 'vertical'
  return constructor('stack', opts)
end

function M.box(opts)
  return constructor('box', opts)
end

function M.spacer(opts)
  if type(opts) == 'number' then
    opts = { width = opts }
  end
  return constructor('spacer', opts)
end

---@param node table
---@param inherited? string
---@return string
function M.highlight(node, inherited)
  return node.highlight or M.roles[node.role] or inherited or 'Normal'
end

local function validate_number(value, name)
  if value ~= nil then
    assert(type(value) == 'number' and value >= 0, name .. ' must be a non-negative number')
  end
end

local function validate_node(node, path, ids)
  assert(type(node) == 'table', path .. ' must be a scene node')
  node.type = node.type or node.kind
  assert(node_types[node.type], path .. ' has unsupported type ' .. tostring(node.type))
  if node.id ~= nil then
    assert(type(node.id) == 'string' and node.id ~= '', path .. '.id must be a non-empty string')
    assert(not ids[node.id], ('duplicate scene node id %q'):format(node.id))
    ids[node.id] = true
  end
  if node.role ~= nil then
    assert(M.roles[node.role], path .. ' has unknown role ' .. tostring(node.role))
  end
  if node.highlight ~= nil then
    assert(type(node.highlight) == 'string', path .. '.highlight must be a string')
  end
  if node.pointer ~= nil then
    assert(
      node.pointer == 'auto' or node.pointer == 'none',
      path .. '.pointer must be auto or none'
    )
  end
  validate_number(node.width or node.width_cells, path .. '.width')
  validate_number(node.height or node.height_cells, path .. '.height')
  validate_number(node.gap, path .. '.gap')
  validate_number(node.font_scale, path .. '.font_scale')

  if node.type == 'text' then
    assert(node.text ~= nil or type(node.spans) == 'table', path .. ' text requires text or spans')
    if node.text ~= nil then
      assert(type(node.text) == 'string', path .. '.text must be a string')
    end
    for index, span in ipairs(node.spans or {}) do
      assert(
        type(span) == 'table' and type(span.text) == 'string',
        path .. '.spans contains invalid span'
      )
      assert(
        span.highlight == nil or type(span.highlight) == 'string',
        path .. '.spans highlight must be a string'
      )
      assert(span.role == nil or M.roles[span.role], path .. '.spans contains an unknown role')
      assert(type(span.action) ~= 'function', path .. '.spans callbacks belong in surface actions')
      validate_number(span.font_scale, ('%s.spans[%d].font_scale'):format(path, index))
    end
  elseif node.type == 'stack' then
    assert(type(node.children) == 'table', path .. ' stack requires children')
    assert(
      node.direction == nil or node.direction == 'horizontal' or node.direction == 'vertical',
      path .. '.direction must be horizontal or vertical'
    )
    for index, child in ipairs(node.children) do
      validate_node(child, ('%s.children[%d]'):format(path, index), ids)
    end
  elseif node.type == 'box' then
    assert(type(node.child) == 'table', path .. ' box requires child')
    assert(type(node.border) ~= 'function', path .. '.border must be data')
    validate_node(node.child, path .. '.child', ids)
  end

  assert(type(node.action) ~= 'function', path .. ' callbacks belong in surface actions')
  for state, patch in pairs(node.states or {}) do
    assert(
      type(state) == 'string' and type(patch) == 'table',
      path .. '.states must contain tables'
    )
    for field in pairs(patch) do
      assert(
        state_fields[field],
        ('%s.states.%s cannot change layout field %q'):format(path, state, field)
      )
    end
    if patch.role ~= nil then
      assert(M.roles[patch.role], path .. '.states contains an unknown role')
    end
    if patch.highlight ~= nil then
      assert(type(patch.highlight) == 'string', path .. '.states highlight must be a string')
    end
  end
end

---@param root table
---@return table
function M.normalize(root)
  root = vim.deepcopy(root)
  validate_node(root, 'scene.root', {})
  return root
end

local function add_fields(materials, name, fields)
  local material = materials[name] or {}
  materials[name] = material
  for _, field in ipairs(fields) do
    material[field] = true
  end
end

local text_fields = {
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

local function collect_materials(node, inherited, result)
  local highlight = M.highlight(node, inherited)
  if node.background then
    add_fields(result, highlight, { 'bg', 'blend', 'winblend' })
  end
  if node.type == 'text' then
    local spans = node.spans or { { text = node.text, highlight = highlight } }
    for _, span in ipairs(spans) do
      add_fields(result, span.highlight or M.roles[span.role] or highlight, text_fields)
    end
  elseif node.type == 'box' then
    if node.border and node.border ~= false then
      local border = type(node.border) == 'table' and node.border or { style = node.border }
      add_fields(result, border.highlight or 'FloatBorder', text_fields)
      add_fields(result, border.highlight or 'FloatBorder', { 'bg', 'blend', 'winblend' })
    end
    collect_materials(node.child, highlight, result)
  elseif node.type == 'stack' then
    for _, child in ipairs(node.children) do
      collect_materials(child, highlight, result)
    end
  end
end

---@param root table
---@return table<string, table<string, boolean>>
function M.materials(root)
  local result = {}
  collect_materials(root, 'Normal', result)
  return result
end

---@param root table
---@return string[]
function M.highlights(root)
  local result = vim.tbl_keys(M.materials(root))
  table.sort(result)
  return result
end

local function collect_border_styles(node, result)
  if node.type == 'box' and node.border and node.border ~= false then
    local border = type(node.border) == 'table' and node.border or { style = node.border }
    result[#result + 1] = border
    collect_border_styles(node.child, result)
  elseif node.type == 'stack' then
    for _, child in ipairs(node.children) do
      collect_border_styles(child, result)
    end
  elseif node.type == 'box' then
    collect_border_styles(node.child, result)
  end
end

function M.border_styles(root)
  local result = {}
  collect_border_styles(root, result)
  return result
end

local function collect_focusable(node, result)
  if node.id and node.focusable then
    result[#result + 1] = node.id
  end
  if node.type == 'stack' then
    for _, child in ipairs(node.children) do
      collect_focusable(child, result)
    end
  elseif node.type == 'box' then
    collect_focusable(node.child, result)
  end
end

function M.focusable_ids(root)
  local result = {}
  collect_focusable(root, result)
  return result
end

local function collect_ids(node, result)
  if node.id then
    result[node.id] = node
  end
  if node.type == 'stack' then
    for _, child in ipairs(node.children) do
      collect_ids(child, result)
    end
  elseif node.type == 'box' then
    collect_ids(node.child, result)
  end
end

---@param root table
---@return table<string, table>
function M.ids(root)
  local result = {}
  collect_ids(root, result)
  return result
end

local function apply_state(node, target_id, state)
  local copy = vim.deepcopy(node)
  if copy.id == target_id and copy.states and copy.states[state] then
    copy = vim.tbl_deep_extend('force', copy, vim.deepcopy(copy.states[state]))
  end
  if copy.type == 'stack' then
    for index, child in ipairs(copy.children) do
      copy.children[index] = apply_state(child, target_id, state)
    end
  elseif copy.type == 'box' then
    copy.child = apply_state(copy.child, target_id, state)
  end
  return copy
end

function M.with_state(root, target_id, state)
  if not target_id then
    return vim.deepcopy(root)
  end
  return apply_state(root, target_id, state)
end

return M
