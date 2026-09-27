local M = {}

local history = {}
local max_history = 100

---@param level integer
---@param message string
---@param notify? boolean
function M.write(level, message, notify)
  history[#history + 1] = {
    time = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    level = level,
    message = message,
  }
  if #history > max_history then
    table.remove(history, 1)
  end
  if notify then
    vim.notify(message, level, { title = 'imageui.nvim' })
  end
end

---@param message string
---@param notify? boolean
function M.error(message, notify)
  M.write(vim.log.levels.ERROR, message, notify)
end

---@param message string
---@param notify? boolean
function M.warn(message, notify)
  M.write(vim.log.levels.WARN, message, notify)
end

---@param message string
function M.info(message)
  M.write(vim.log.levels.INFO, message, false)
end

---@return table[]
function M.history()
  return vim.deepcopy(history)
end

function M.clear()
  history = {}
end

return M
