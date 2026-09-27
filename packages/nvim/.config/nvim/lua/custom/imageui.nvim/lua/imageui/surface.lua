local log = require('imageui.util.log')
local interaction_geometry = require('imageui.interaction_geometry')
local manager = require('imageui.manager')
local scene = require('imageui.scene')

local M = {}

local Surface = {}
Surface.__index = Surface

local surfaces = {}
local next_id = 0
local augroup

local action_names = {
  activate = true,
  blur = true,
  click = true,
  enter = true,
  focus = true,
  hover = true,
  leave = true,
}

local function normalize_host(host)
  host = vim.deepcopy(host or { kind = 'view' })
  host.kind = host.kind or 'view'
  assert(host.kind == 'view' or host.kind == 'window', 'surface host must be view or window')
  assert(
    host.owned ~= true,
    'owned surface windows are not supported; pass an existing Neovim window'
  )
  if host.kind == 'window' then
    local win = host.window or host.win or 0
    win = win == 0 and vim.api.nvim_get_current_win() or win
    assert(vim.api.nvim_win_is_valid(win), 'surface host window is invalid')
    host.window = win
    host.win = nil
  else
    host.window = nil
    host.win = nil
  end
  host.owned = false
  return host
end

local function inferred_appearance(spec, host)
  if spec.appearance then
    assert(
      spec.appearance == 'inline' or spec.appearance == 'float' or spec.appearance == 'menu',
      'surface appearance must be inline, float, or menu'
    )
    return spec.appearance
  end
  if host.kind == 'window' then
    local config = vim.api.nvim_win_get_config(host.window)
    if config.relative ~= '' then
      return 'float'
    end
  end
  return 'inline'
end

local function apply_appearance(root, appearance)
  root = vim.deepcopy(root)
  if root.highlight == nil and root.role == nil then
    root.role = appearance
  end
  local function apply(node)
    if node.role then
      local highlight = scene.role_highlight(node.role, appearance)
      if highlight ~= scene.roles[node.role] then
        node.highlight = highlight
        node.role = nil
      end
    end
    for _, span in ipairs(node.spans or {}) do
      if span.role then
        local highlight = scene.role_highlight(span.role, appearance)
        if highlight ~= scene.roles[span.role] then
          span.highlight = highlight
          span.role = nil
        end
      end
    end
    if node.type == 'stack' then
      for _, child in ipairs(node.children) do
        apply(child)
      end
    elseif node.type == 'box' then
      apply(node.child)
    end
  end
  apply(root)
  return root
end

local function normalize_actions(actions, ids)
  local result = {}
  for id, entry in pairs(actions or {}) do
    assert(type(id) == 'string' and ids[id], ('surface action targets unknown node %q'):format(id))
    if type(entry) == 'function' then
      result[id] = entry
    else
      assert(type(entry) == 'table', ('surface action %q must be a function or table'):format(id))
      local normalized = {}
      for name, value in pairs(entry) do
        if name == 'consume' then
          assert(type(value) == 'boolean', ('surface action %q consume must be boolean'):format(id))
        else
          assert(action_names[name], ('surface action %q has unknown event %q'):format(id, name))
          assert(
            type(value) == 'function',
            ('surface action %q event %q must be a function'):format(id, name)
          )
        end
        normalized[name] = value
      end
      result[id] = normalized
    end
  end
  return result
end

local function normalize_focus(focus, root)
  if focus == false then
    return { order = {}, wrap = false }
  end
  focus = vim.deepcopy(focus or {})
  local focusable = scene.focusable_ids(root)
  local allowed = {}
  for _, id in ipairs(focusable) do
    allowed[id] = true
  end
  local order = focus.order or focusable
  local seen = {}
  for index, id in ipairs(order) do
    assert(
      type(id) == 'string' and allowed[id],
      ('surface focus.order[%d] is not focusable'):format(index)
    )
    assert(not seen[id], ('surface focus.order repeats %q'):format(id))
    seen[id] = true
  end
  assert(focus.wrap == nil or type(focus.wrap) == 'boolean', 'surface focus.wrap must be boolean')
  local initial = focus.initial
  if initial == true then
    initial = order[1]
  end
  if initial ~= nil then
    assert(
      type(initial) == 'string' and seen[initial],
      'surface focus.initial is not in focus.order'
    )
  end
  return { order = vim.deepcopy(order), wrap = focus.wrap == true, initial = initial }
end

local function normalize_spec(spec)
  vim.validate('surface', spec, 'table')
  local host = normalize_host(spec.host)
  local raw_root = spec.scene or spec.root or (spec.content and spec.content.root)
  assert(type(raw_root) == 'table', 'surface requires a scene/root')
  local root = scene.normalize(raw_root)
  local ids = scene.ids(root)
  for id, node in pairs(ids) do
    if node.hit_rect or node.hitbox then
      local ok, err = pcall(interaction_geometry.hit_rect, {
        visual = { x = 0, y = 0, width = 1, height = 1 },
        hit_rect = node.hit_rect or node.hitbox,
      })
      assert(ok, ('surface node %q has an invalid hit rectangle: %s'):format(id, err))
    end
  end
  local actions = normalize_actions(spec.actions, ids)
  local focus = normalize_focus(spec.focus, root)
  local anchor_spec = spec.anchor
  local derived_anchor = spec._derived_anchor == true
  if not anchor_spec and host.kind == 'window' then
    anchor_spec = {
      kind = 'window',
      window = host.window,
      origin = 'content',
      row = spec.row or 0,
      col = spec.col or 0,
    }
    derived_anchor = true
  end
  assert(type(anchor_spec) == 'table', 'surface requires an anchor unless hosted by a window')

  local normalized = vim.deepcopy(spec)
  normalized.scene = root
  normalized.root = nil
  normalized.content = nil
  normalized.anchor = vim.deepcopy(anchor_spec)
  normalized._derived_anchor = derived_anchor
  normalized.host = host
  normalized.actions = actions
  normalized.focus = focus
  normalized.appearance = inferred_appearance(spec, host)
  if normalized.zindex == nil and host.kind == 'window' then
    local window_config = vim.api.nvim_win_get_config(host.window)
    if window_config.relative ~= '' then
      normalized.zindex = window_config.zindex or 50
    end
  end
  normalized.row = nil
  normalized.col = nil
  return normalized
end

local function rendered_scene(spec, focused)
  return apply_appearance(scene.with_state(spec.scene, focused, 'focused'), spec.appearance)
end

local function widget_spec(surface, spec, focused)
  local result = vim.deepcopy(spec)
  local user_on_delete = result.on_delete
  result.scene = nil
  result.root = nil
  result.focus = nil
  result.appearance = nil
  result._derived_anchor = nil
  result.widget_actions = nil
  result.content = {
    kind = 'scene',
    root = rendered_scene(spec, focused),
  }
  result.actions = vim.deepcopy(spec.widget_actions)
  result.region_actions = vim.deepcopy(spec.actions)
  result.surface_id = surface.id
  result.on_delete = function(widget_id)
    if surface.widget_id == widget_id then
      surfaces[surface.id] = nil
      surface.closed = true
    end
    if type(user_on_delete) == 'function' then
      user_on_delete(surface, widget_id)
    end
  end
  return result
end

local function focus_index(surface, id)
  for index, current in ipairs(surface._spec.focus.order) do
    if current == id then
      return index
    end
  end
end

function Surface:is_open()
  return not self.closed and manager.get(self.widget_id) ~= nil
end

function Surface:update(patch)
  if not self:is_open() then
    return false
  end
  vim.validate('patch', patch, 'table')
  local candidate = vim.tbl_deep_extend('force', vim.deepcopy(self._spec), vim.deepcopy(patch))
  for _, key in ipairs({ 'actions', 'focus', 'host', 'widget_actions' }) do
    if patch[key] ~= nil then
      candidate[key] = vim.deepcopy(patch[key])
    end
  end
  if patch.anchor ~= nil then
    candidate._derived_anchor = false
  elseif
    self._spec._derived_anchor and (patch.host ~= nil or patch.row ~= nil or patch.col ~= nil)
  then
    candidate.anchor = nil
    candidate._derived_anchor = false
  end
  if patch.scene ~= nil then
    candidate.scene = vim.deepcopy(patch.scene)
    candidate.root = nil
    candidate.content = nil
  elseif patch.root ~= nil then
    candidate.scene = vim.deepcopy(patch.root)
    candidate.root = nil
    candidate.content = nil
  elseif patch.content ~= nil then
    candidate.scene = nil
    candidate.root = nil
    candidate.content = vim.deepcopy(patch.content)
  end
  candidate = normalize_spec(candidate)
  local previous = self._focused
  local focused = self._focused
  if patch.focus ~= nil and candidate.focus.initial ~= nil then
    focused = candidate.focus.initial
  elseif focused and not focus_index({ _spec = candidate }, focused) then
    focused = nil
  end
  if previous and previous ~= focused then
    manager.dispatch_node(self.widget_id, previous, 'blur')
  end
  if focused and previous ~= focused then
    manager.dispatch_node(self.widget_id, focused, 'focus', candidate.actions)
  end
  if
    not self:is_open()
    or not manager.update(self.widget_id, widget_spec(self, candidate, focused))
  then
    return false
  end
  self._spec = candidate
  self._focused = focused
  return true
end

function Surface:focus(id)
  if not self:is_open() then
    return false
  end
  if id ~= nil and not focus_index(self, id) then
    return false
  end
  if id == self._focused then
    return true
  end
  local previous = self._focused
  if previous then
    manager.dispatch_node(self.widget_id, previous, 'blur')
  end
  if id then
    manager.dispatch_node(self.widget_id, id, 'focus')
  end
  if not self:is_open() then
    return false
  end
  local next_content = {
    kind = 'scene',
    root = rendered_scene(self._spec, id),
  }
  if not manager.update(self.widget_id, { content = next_content }) then
    return false
  end
  self._focused = id
  return true
end

function Surface:focused()
  return self._focused
end

function Surface:focus_next()
  local order = self._spec.focus.order
  if #order == 0 then
    return false
  end
  local index = focus_index(self, self._focused)
  if not index then
    return self:focus(order[1])
  end
  if index == #order and not self._spec.focus.wrap then
    return false
  end
  return self:focus(order[(index % #order) + 1])
end

function Surface:focus_prev()
  local order = self._spec.focus.order
  if #order == 0 then
    return false
  end
  local index = focus_index(self, self._focused)
  if not index then
    return self:focus(order[#order])
  end
  if index == 1 and not self._spec.focus.wrap then
    return false
  end
  return self:focus(order[((index - 2) % #order) + 1])
end

function Surface:activate(id)
  if not self:is_open() then
    return false
  end
  id = id or self._focused
  if not id or not scene.ids(self._spec.scene)[id] then
    return false
  end
  return manager.dispatch_node(self.widget_id, id, 'activate')
end

function Surface:close()
  if self.closed then
    return true
  end
  return manager.delete(self.widget_id)
end

function Surface:inspect()
  return {
    id = self.id,
    widget_id = self.widget_id,
    open = self:is_open(),
    focused = self._focused,
    focus_order = vim.deepcopy(self._spec.focus.order),
    host = vim.deepcopy(self._spec.host),
    appearance = self._spec.appearance,
  }
end

---@param spec table
---@return table
function M.create(spec)
  spec = normalize_spec(spec)
  next_id = next_id + 1
  local surface = setmetatable({
    id = next_id,
    closed = false,
    _spec = spec,
    _focused = spec.focus.initial,
  }, Surface)
  surfaces[surface.id] = surface
  local ok, widget_id = pcall(manager.create, widget_spec(surface, spec, surface._focused))
  if not ok then
    surfaces[surface.id] = nil
    surface.closed = true
    error(widget_id)
  end
  surface.widget_id = widget_id
  if surface._focused then
    manager.dispatch_node(widget_id, surface._focused, 'focus')
  end
  return surface
end

function M.get(id)
  return surfaces[id]
end

function M.inspect()
  local result = {}
  for id, surface in pairs(surfaces) do
    result[id] = surface:inspect()
  end
  return result
end

local function matching_surfaces(predicate)
  local result = {}
  for _, surface in pairs(surfaces) do
    if predicate(surface) then
      result[#result + 1] = surface
    end
  end
  return result
end

local function enable_autocmds()
  if augroup then
    return
  end
  augroup = vim.api.nvim_create_augroup('ImageUISurfaces', { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(args)
      local closed = tonumber(args.match)
      for _, surface in
        ipairs(matching_surfaces(function(current)
          local widget = manager.get(current.widget_id)
          local anchor = widget and widget.anchor
          return current._spec.host.window == closed
            or (anchor and anchor.window and anchor.window ~= 0 and anchor.window == closed)
        end))
      do
        if not surface:close() then
          log.warn(
            ('surface %d could not release after its window closed'):format(surface.id),
            true
          )
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = augroup,
    callback = function(args)
      for _, surface in
        ipairs(matching_surfaces(function(current)
          local widget = manager.get(current.widget_id)
          return widget and widget.anchor.kind == 'buffer' and widget.anchor.buffer == args.buf
        end))
      do
        if not surface:close() then
          log.warn(
            ('surface %d could not release after its buffer was wiped'):format(surface.id),
            true
          )
        end
      end
    end,
  })
end

function M.setup()
  enable_autocmds()
end

function M.enable()
  enable_autocmds()
end

function M.disable()
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  for _, surface in pairs(surfaces) do
    surface.closed = true
  end
  surfaces = {}
end

return M
