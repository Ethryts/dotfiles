local M = {}

local configured = false
local active = false

M.config = nil

---@param opts? table
function M.setup(opts)
  if configured then
    assert(
      M.disable() ~= false,
      'imageui.nvim: terminal cleanup failed; retry :ImageUI reset before reconfiguring'
    )
  end
  M.config = require('imageui.config').normalize(opts)

  require('imageui.backend').setup(M.config.backend, M.config)
  require('imageui.manager').setup(M.config)
  require('imageui.interactions').setup(M.config)
  require('imageui.surface').setup(M.config)
  require('imageui.integrations.codelens').setup(M.config)
  require('imageui.commands').setup()
  configured = true

  if M.config.enabled then
    M.enable()
  end
  return M
end

function M.enable()
  if active then
    return
  end
  if not configured then
    M.setup()
    return
  end
  require('imageui.manager').enable()
  require('imageui.surface').enable()
  require('imageui.interactions').enable()
  if M.config.integrations.codelens.enabled then
    require('imageui.integrations.codelens').enable()
  end
  active = true
end

function M.disable()
  if not configured then
    return
  end
  require('imageui.integrations.codelens').disable()
  require('imageui.interactions').disable()
  local disabled = require('imageui.manager').disable()
  if disabled == false then
    active = false
    return false
  end
  require('imageui.surface').disable()
  active = false
  return true
end

---@return boolean
function M.is_configured()
  return configured
end

---@return boolean
function M.is_enabled()
  return active
end

---@param probe? boolean
---@return boolean, string?
function M.supported(probe)
  local backend = require('imageui.backend').get()
  local available, reason = backend.available()
  if not available or not probe or type(backend.supported) ~= 'function' then
    return available, reason
  end
  return backend.supported({ timeout = 500 })
end

function M.create(spec)
  assert(configured, 'imageui.nvim: call setup() before create()')
  return require('imageui.manager').create(spec)
end

function M.update(id, patch)
  return require('imageui.manager').update(id, patch)
end

function M.delete(id)
  return require('imageui.manager').delete(id)
end

function M.clear(filter)
  return require('imageui.manager').clear(filter)
end

function M.refresh()
  return require('imageui.manager').refresh()
end

function M.invalidate_styles()
  return require('imageui.manager').invalidate_styles()
end

function M.reset_transport()
  return require('imageui.manager').reset_transport()
end

function M.on_redraw(name, callback)
  return require('imageui.manager').subscribe_redraw(name, callback)
end

function M.flush()
  return require('imageui.manager').flush()
end

function M.hit_test(row, col)
  return require('imageui.manager').hit_test(row, col)
end

function M.hit_target(row, col)
  return require('imageui.manager').hit_target(row, col)
end

function M.surface(spec)
  assert(configured, 'imageui.nvim: call setup() before surface()')
  return require('imageui.surface').create(spec)
end

function M.dispatch(action, mouse)
  return require('imageui.manager').dispatch(action, mouse)
end

function M.export(directory)
  return require('imageui.manager').export(directory)
end

function M.inspect()
  local result = require('imageui.manager').inspect()
  result.configured = configured
  result.active = active
  result.surfaces = require('imageui.surface').inspect()
  result.codelens = require('imageui.integrations.codelens').inspect()
  return result
end

M.scene = require('imageui.scene')

return M
