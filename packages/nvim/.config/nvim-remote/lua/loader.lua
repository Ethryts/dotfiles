local M = {}

function M.setup()
  local directory = vim.fn.stdpath("config") .. "/lua/plugins"

  if vim.fn.isdirectory(directory) == 0 then
    return
  end

  local modules = {}

  for filename, kind in vim.fs.dir(directory) do
    if kind == "file" and filename:match("%.lua$") then
      modules[#modules + 1] = filename:gsub("%.lua$", "")
    end
  end

  table.sort(modules)

  for _, module in ipairs(modules) do
    local ok, error_message = pcall(require, "plugins." .. module)

    if not ok then
      vim.notify(
        ("Failed to load plugins.%s:\n%s"):format(module, error_message),
        vim.log.levels.ERROR
      )
    end
  end
end

return M.setup()
