local config = require("aligned-inline-diagnostic.config")
local highlights = require("aligned-inline-diagnostic.highlights")
local hover = require("aligned-inline-diagnostic.hover")
local renderer = require("aligned-inline-diagnostic.renderer")
local state = require("aligned-inline-diagnostic.state")

local M = {}

local function require_setup(operation)
  if state.config then
    return
  end
  error(("aligned-inline-diagnostic: setup() must be called before %s()"):format(operation), 3)
end

local function advance_lifecycle()
  state.lifecycle_epoch = (state.lifecycle_epoch or 0) + 1
  return state.lifecycle_epoch
end

local function resolve_buffer(bufnr, operation)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if type(bufnr) ~= "number" or bufnr % 1 ~= 0 or not vim.api.nvim_buf_is_valid(bufnr) then
    error(("aligned-inline-diagnostic: %s() requires a valid buffer"):format(operation), 3)
  end
  return bufnr
end

local function defer_hover_current(callback, delay)
  local epoch = state.lifecycle_epoch
  local generation = state.hover.generation
  vim.defer_fn(function()
    if state.lifecycle_epoch == epoch and state.config and state.hover.generation == generation then
      callback()
    end
  end, delay)
end

local function schedule_current(callback)
  local epoch = state.lifecycle_epoch
  vim.schedule(function()
    if state.lifecycle_epoch == epoch and state.config then
      callback()
    end
  end)
end

local function track_active_input()
  hover.track_active()
end

local function visible_buffers()
  local result = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local window_config = vim.api.nvim_win_get_config(winid)
    if window_config.relative == "" then
      result[vim.api.nvim_win_get_buf(winid)] = true
    end
  end
  return result
end

local function render_visible()
  for bufnr in pairs(visible_buffers()) do
    renderer.schedule(bufnr)
  end
end

local function setup_virtual_text()
  if state.config.disable_default_virtual_text then
    local current = vim.diagnostic.config().virtual_text
    -- Another component changed the option after we installed our value.
    -- Treat that value as the new baseline rather than restoring a stale one.
    if state.saved_virtual_text and current ~= state.installed_virtual_text then
      state.saved_virtual_text = false
      state.previous_virtual_text = nil
      state.installed_virtual_text = nil
    end
    if not state.saved_virtual_text then
      state.previous_virtual_text = vim.deepcopy(current)
      state.saved_virtual_text = true
    end
    state.installed_virtual_text = false
    if current ~= false then
      vim.diagnostic.config({ virtual_text = false })
    end
  elseif state.saved_virtual_text then
    local current = vim.diagnostic.config().virtual_text
    if current == state.installed_virtual_text then
      vim.diagnostic.config({ virtual_text = state.previous_virtual_text })
    end
    state.saved_virtual_text = false
    state.previous_virtual_text = nil
    state.installed_virtual_text = nil
  end
end

local function restore_virtual_text()
  if state.saved_virtual_text then
    local current = vim.diagnostic.config().virtual_text
    if current == state.installed_virtual_text then
      vim.diagnostic.config({ virtual_text = state.previous_virtual_text })
    end
    state.saved_virtual_text = false
    state.previous_virtual_text = nil
    state.installed_virtual_text = nil
  end
end

local function teardown_mouse_listener()
  state.mouse_update_scheduled = false
  if state.mouse_listener then
    vim.on_key(nil, state.mouse_listener)
    state.mouse_listener = nil
  end
  if state.previous_mousemoveevent ~= nil then
    if vim.o.mousemoveevent == state.installed_mousemoveevent then
      vim.o.mousemoveevent = state.previous_mousemoveevent
    end
    state.previous_mousemoveevent = nil
    state.installed_mousemoveevent = nil
  end
end

local function setup_mouse_listener()
  teardown_mouse_listener()
  if
    not state.config.hover.enabled
    or not hover.uses_mouse()
    or vim.fn.exists("+mousemoveevent") ~= 1
  then
    return
  end

  state.previous_mousemoveevent = vim.o.mousemoveevent
  state.installed_mousemoveevent = true
  vim.o.mousemoveevent = true
  local mouse_key = vim.keycode("<MouseMove>")
  local namespace = vim.api.nvim_create_namespace("aligned-inline-diagnostic-mouse")
  state.mouse_listener = vim.on_key(function(key, typed)
    if key == mouse_key or typed == mouse_key then
      if state.mouse_update_scheduled then
        return
      end
      state.mouse_update_scheduled = true
      schedule_current(function()
        state.mouse_update_scheduled = false
        hover.track_mouse()
      end)
    end
  end, namespace)
end

local function setup_commands()
  vim.api.nvim_create_user_command("AlignedDiagnostic", function(command)
    local action = command.args == "" and "toggle" or command.args
    if action == "enable" then
      M.enable()
    elseif action == "disable" then
      M.disable()
    elseif action == "toggle" then
      M.toggle()
    elseif action == "refresh" then
      M.refresh()
    elseif action == "open" then
      M.open()
    elseif action == "close" then
      M.close()
    elseif action == "pin" then
      M.pin()
    elseif action == "unpin" then
      M.unpin()
    elseif action == "enable-buffer" then
      M.enable_buffer()
    elseif action == "disable-buffer" then
      M.disable_buffer()
    elseif action == "toggle-buffer" then
      M.toggle_buffer()
    else
      vim.notify("Unknown AlignedDiagnostic action: " .. action, vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    force = true,
    desc = "Control aligned inline diagnostics",
    complete = function()
      return {
        "enable",
        "disable",
        "toggle",
        "refresh",
        "open",
        "close",
        "pin",
        "unpin",
        "enable-buffer",
        "disable-buffer",
        "toggle-buffer",
      }
    end,
  })
end

local function setup_autocommands()
  local group = vim.api.nvim_create_augroup("AlignedInlineDiagnostic", { clear = true })

  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(event)
      if not state.enabled then
        return
      end
      renderer.schedule(event.buf)
      defer_hover_current(hover.reconcile, state.config.throttle_ms + 1)
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(event)
      if not state.enabled then
        return
      end
      renderer.schedule(event.buf)
      defer_hover_current(track_active_input, state.config.throttle_ms + 1)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    callback = function(event)
      if not state.enabled then
        return
      end
      renderer.schedule(event.buf)
      defer_hover_current(hover.reconcile, state.config.throttle_ms + 1)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(event)
      state.disabled_buffers[event.buf] = nil
      local owned = event.buf == state.hover.buf
        or (state.hover.owned_buffers and state.hover.owned_buffers[event.buf])
      if owned then
        if state.hover.owned_buffers then
          state.hover.owned_buffers[event.buf] = nil
        end
        if event.buf == state.hover.buf and not state.hover.closing then
          schedule_current(function()
            if state.hover.buf == event.buf then
              hover.close({ passive = true })
            end
          end)
        end
        return
      end
      renderer.clear(event.buf)
      schedule_current(hover.reconcile)
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      highlights.setup(state.config)
      if state.enabled then
        render_visible()
        defer_hover_current(hover.refresh, state.config.throttle_ms + 1)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if state.enabled then
        render_visible()
        defer_hover_current(hover.refresh, state.config.throttle_ms + 1)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = hover.track_current,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function(event)
      -- Pinning focuses an owned float, and closing it enters the source while
      -- close_float() is still running. Neither transition is a fresh hover
      -- intent, so do not queue a tracker that can reopen an explicit close.
      local owned = (state.hover.owned_buffers or {})[event.buf]
      if state.enabled and not state.hover.closing and not owned then
        defer_hover_current(track_active_input, state.config.throttle_ms + 1)
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(event)
      if state.enabled and not (state.hover.owned_buffers or {})[event.buf] then
        renderer.schedule(event.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = {
      "colorcolumn",
      "textwidth",
      "tabstop",
      "number",
      "signcolumn",
      "foldcolumn",
      "winbar",
      "conceallevel",
      "concealcursor",
    },
    callback = function()
      if not state.enabled then
        return
      end
      local bufnr = vim.api.nvim_get_current_buf()
      renderer.schedule(bufnr)
      if state.hover.source_buf == bufnr then
        defer_hover_current(hover.refresh, state.config.throttle_ms + 1)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(event)
      if (state.hover.owned_buffers or {})[event.buf] then
        return
      end
      renderer.clear(event.buf)
      if state.hover.source_buf == event.buf then
        hover.close({ passive = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      if state.hover.closing then
        return
      end
      local winid = tonumber(event.match)
      if winid and (winid == state.hover.source_win or winid == state.hover.win) then
        hover.close({ passive = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = group,
    callback = hover.on_leave,
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function(event)
      local winid = tonumber(event.match)
      if not winid and vim.v and type(vim.v.event) == "table" then
        winid = tonumber(vim.v.event.winid)
      end
      if winid and winid == state.hover.win then
        return
      end
      if winid and state.hover.source_win and winid ~= state.hover.source_win then
        return
      end
      hover.refresh({ preserve_geometry = true })
    end,
  })
end

function M.setup(options)
  if vim.fn.has("nvim-0.10") == 0 then
    error("aligned-inline-diagnostic.nvim requires Neovim >= 0.10")
  end

  -- Validate before mutating an existing setup so a config typo cannot leave
  -- the running instance half torn down.
  local resolved = config.resolve(options)
  advance_lifecycle()

  -- setup() may be called again by a config reload. Tear down the old target
  -- before replacing its options so a hidden preview is always restored.
  hover.close({ passive = true })
  state.config = resolved
  highlights.setup(state.config)
  setup_commands()
  setup_autocommands()

  if state.config.enabled then
    M.enable()
  else
    M.disable()
  end
end

function M.enable()
  require_setup("enable")
  advance_lifecycle()
  state.enabled = true
  setup_virtual_text()
  setup_mouse_listener()
  render_visible()
  defer_hover_current(track_active_input, state.config.throttle_ms + 1)
end

function M.disable()
  advance_lifecycle()
  state.enabled = false
  hover.close({ passive = true })
  teardown_mouse_listener()
  restore_virtual_text()
  renderer.clear_all()
end

function M.toggle()
  require_setup("toggle")
  if state.enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.refresh(bufnr)
  require_setup("refresh")
  renderer.render(bufnr or vim.api.nvim_get_current_buf())
  hover.reconcile()
end

function M.open()
  require_setup("open")
  return hover.open_current()
end

function M.close()
  hover.close()
end

function M.pin()
  require_setup("pin")
  return hover.pin()
end

function M.unpin()
  require_setup("unpin")
  return hover.unpin()
end

function M.enable_buffer(bufnr)
  require_setup("enable_buffer")
  bufnr = resolve_buffer(bufnr, "enable_buffer")
  state.disabled_buffers[bufnr] = nil
  if state.enabled then
    renderer.schedule(bufnr)
  end
  return true
end

function M.disable_buffer(bufnr)
  require_setup("disable_buffer")
  bufnr = resolve_buffer(bufnr, "disable_buffer")
  state.disabled_buffers[bufnr] = true
  if state.hover.source_buf == bufnr then
    hover.close({ passive = true })
  end
  renderer.clear(bufnr)
  return false
end

function M.toggle_buffer(bufnr)
  require_setup("toggle_buffer")
  bufnr = resolve_buffer(bufnr, "toggle_buffer")
  if state.disabled_buffers[bufnr] then
    return M.enable_buffer(bufnr)
  end
  return M.disable_buffer(bufnr)
end

function M.get_diagnostics_under_cursor()
  require_setup("get_diagnostics_under_cursor")
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  return vim.deepcopy(renderer.diagnostics_at(bufnr, row, col))
end

function M.get_diagnostics_on_line()
  require_setup("get_diagnostics_on_line")
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local layout = renderer.find_layout(bufnr, row)
  return layout and vim.deepcopy(layout.diagnostics) or {}
end

function M.is_enabled(bufnr)
  if bufnr == nil then
    return state.enabled
  end
  bufnr = resolve_buffer(bufnr, "is_enabled")
  return state.enabled and not state.disabled_buffers[bufnr]
end

return M
