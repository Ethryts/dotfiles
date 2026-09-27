local M = {}

local ESC = '\027'

---@param value? string
---@return boolean
function M.detected(value)
  value = value == nil and vim.env.TMUX or value
  return type(value) == 'string' and value ~= ''
end

---@param mode? 'auto'|'on'|'off'|boolean
---@param value? string
---@return boolean
function M.resolve(mode, value)
  mode = mode == nil and 'auto' or mode
  if mode == true or mode == 'on' then
    return true
  end
  if mode == false or mode == 'off' then
    return false
  end
  assert(mode == 'auto', 'imageui.nvim: transport.tmux must be "auto", "on", or "off"')
  return M.detected(value)
end

---Wrap one complete outer-terminal operation for tmux passthrough. Placement
---operations include their projected cursor move in the same envelope.
---@param graphics string
---@return string
function M.wrap(graphics)
  local escaped = graphics:gsub(ESC, ESC .. ESC)
  return ESC .. 'Ptmux;' .. escaped .. ESC .. '\\'
end

---@class ImageUI.TmuxStatus
---@field detected boolean
---@field executable boolean
---@field enabled boolean
---@field value string?
---@field scope 'pane'|'effective'|'global'?
---@field error string?
---@field focus_events boolean?
---@field focus_error string?

---@class ImageUI.TmuxGeometry
---@field valid boolean
---@field row integer? Zero-based outer-terminal row offset for pane-local cells.
---@field col integer? Zero-based outer-terminal column offset for pane-local cells.
---@field pane_top integer?
---@field pane_left integer?
---@field window_offset_y integer?
---@field window_offset_x integer?
---@field status_lines integer?
---@field status_position string?
---@field client_name string?
---@field client_width integer?
---@field client_height integer?
---@field attached_clients integer?
---@field client_termname string?
---@field client_termfeatures string?
---@field error string?

local function default_run(command)
  return vim.system(command, { text = true }):wait(500)
end

local function command_result(run, command)
  local ok, result = pcall(run, command)
  if not ok then
    return nil, tostring(result)
  end
  if type(result) ~= 'table' then
    return nil, 'tmux command returned no result'
  end
  if result.code ~= 0 then
    local error = vim.trim(result.stderr or '')
    return nil, error ~= '' and error or 'tmux command failed'
  end
  return result
end

---@param opts? {env?: string, pane?: string, executable?: fun(): boolean, run?: fun(command: string[]): table}
---@return ImageUI.TmuxStatus
function M.status(opts)
  opts = opts or {}
  local detected = M.detected(opts.env)
  if not detected then
    return { detected = false, executable = false, enabled = false }
  end

  local executable = opts.executable and opts.executable() or vim.fn.executable('tmux') == 1
  if not executable then
    return {
      detected = true,
      executable = false,
      enabled = false,
      error = 'tmux executable is unavailable',
    }
  end

  local run = opts.run or default_run
  local pane = opts.pane == nil and vim.env.TMUX_PANE or opts.pane
  local queries = {}
  if type(pane) == 'string' and pane ~= '' then
    queries[#queries + 1] = {
      scope = 'pane',
      command = { 'tmux', 'show-options', '-pAv', '-t', pane, 'allow-passthrough' },
    }
    queries[#queries + 1] = {
      scope = 'effective',
      command = { 'tmux', 'show-options', '-Av', '-t', pane, 'allow-passthrough' },
    }
  end
  queries[#queries + 1] = {
    scope = 'global',
    command = { 'tmux', 'show-options', '-gv', 'allow-passthrough' },
  }

  local result, query_error, scope
  for _, query in ipairs(queries) do
    result, query_error = command_result(run, query.command)
    if result then
      scope = query.scope
      break
    end
  end
  if not result then
    return {
      detected = true,
      executable = true,
      enabled = false,
      error = query_error or 'unable to read allow-passthrough',
    }
  end

  local value = vim.trim(result.stdout or '')
  local focus_ok, focus_result = pcall(run, { 'tmux', 'show-options', '-sv', 'focus-events' })
  local focus_value = focus_ok and focus_result.code == 0 and vim.trim(focus_result.stdout or '')
    or nil
  return {
    detected = true,
    executable = true,
    enabled = value == 'on' or value == 'all',
    value = value ~= '' and value or nil,
    scope = scope,
    focus_events = focus_value == 'on',
    focus_error = not focus_ok and tostring(focus_result)
      or (focus_result.code ~= 0 and vim.trim(focus_result.stderr or '') or nil),
  }
end

local function status_size(value)
  if value == 'on' then
    return 1
  end
  if value == 'off' or value == '' then
    return 0
  end
  return tonumber(value) or 0
end

---@param opts? {env?: string, pane?: string, executable?: fun(): boolean, run?: fun(command: string[]): table}
---@return ImageUI.TmuxGeometry
function M.geometry(opts)
  opts = opts or {}
  if not M.detected(opts.env) then
    return { valid = false, error = 'not running inside tmux' }
  end

  local executable = opts.executable and opts.executable() or vim.fn.executable('tmux') == 1
  if not executable then
    return { valid = false, error = 'tmux executable is unavailable' }
  end

  local pane = opts.pane == nil and vim.env.TMUX_PANE or opts.pane
  if type(pane) ~= 'string' or pane == '' then
    return { valid = false, error = 'TMUX_PANE is unavailable' }
  end

  local fields = {
    '#{pane_left}',
    '#{pane_top}',
    '#{window_offset_x}',
    '#{window_offset_y}',
    '#{status}',
    '#{status-position}',
    '#{client_name}',
    '#{client_width}',
    '#{client_height}',
    '#{session_attached}',
    '#{client_termname}',
    '#{client_termfeatures}',
  }
  local result, command_error = command_result(opts.run or default_run, {
    'tmux',
    'display-message',
    '-p',
    '-t',
    pane,
    table.concat(fields, '\t'),
  })
  if not result then
    return { valid = false, error = command_error or 'unable to read tmux pane geometry' }
  end

  local output = (result.stdout or ''):gsub('[\r\n]+$', '')
  local values = vim.split(output, '\t', { plain = true, trimempty = false })
  local pane_left = tonumber(values[1])
  local pane_top = tonumber(values[2])
  if not pane_left or not pane_top then
    return {
      valid = false,
      error = 'tmux returned incomplete pane geometry: ' .. vim.inspect(output),
    }
  end

  local window_offset_x = tonumber(values[3]) or 0
  local window_offset_y = tonumber(values[4]) or 0
  local status_lines = status_size(values[5] or '')
  local status_position = values[6] or 'bottom'
  local top_status_lines = (status_position == 'top' or status_position == '0') and status_lines
    or 0
  return {
    valid = true,
    row = pane_top - window_offset_y + top_status_lines,
    col = pane_left - window_offset_x,
    pane_top = pane_top,
    pane_left = pane_left,
    window_offset_y = window_offset_y,
    window_offset_x = window_offset_x,
    status_lines = status_lines,
    status_position = status_position,
    client_name = values[7] ~= '' and values[7] or nil,
    client_width = tonumber(values[8]),
    client_height = tonumber(values[9]),
    attached_clients = tonumber(values[10]),
    client_termname = values[11] ~= '' and values[11] or nil,
    client_termfeatures = values[12] ~= '' and values[12] or nil,
  }
end

---@param geometry ImageUI.TmuxGeometry
---@param row integer One-based pane-local row.
---@param col integer One-based pane-local column.
---@return integer, integer
function M.project(geometry, row, col)
  assert(geometry and geometry.valid, geometry and geometry.error or 'tmux geometry is unavailable')
  return row + geometry.row, col + geometry.col
end

return M
