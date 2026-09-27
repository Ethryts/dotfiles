local state = require("aligned-inline-diagnostic.state")

local M = {}

local function report_multiwindow_buffers()
  local counts = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    counts[bufnr] = (counts[bufnr] or 0) + 1
  end
  local found = false
  for bufnr, count in pairs(counts) do
    if count > 1 then
      found = true
      vim.health.warn(
        ("buffer %d is visible in %d windows; preview extmarks are buffer-global"):format(
          bufnr,
          count
        )
      )
    end
  end
  if not found then
    vim.health.ok("no same-buffer split conflicts detected")
  end
end

function M.check()
  vim.health.start("aligned-inline-diagnostic.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim 0.10+ detected")
  else
    vim.health.error("Neovim 0.10 or newer is required")
    return
  end

  if not state.config then
    vim.health.warn("setup() has not been called")
    return
  end

  vim.health.ok(state.enabled and "plugin is enabled" or "plugin is configured but disabled")
  if state.config.hover.input_mode ~= "cursor" then
    if vim.fn.exists("+mousemoveevent") == 1 then
      vim.health.ok("mouse movement events are supported")
    else
      vim.health.warn("mouse hover is configured but 'mousemoveevent' is unavailable")
    end
  end

  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  if normal.bg == nil then
    vim.health.info(
      "Normal has a transparent background; generated surfaces use the configured light/dark fallback"
    )
  else
    vim.health.ok("Normal provides a background for palette generation")
  end

  for _, name in ipairs({ "left", "right" }) do
    local glyph = state.config.icons[name]
    local width = vim.fn.strdisplaywidth(glyph)
    if glyph ~= "" and width > 2 then
      vim.health.warn(
        ("icons.%s occupies %d cells and may produce unusually wide edges"):format(name, width)
      )
    end
  end

  report_multiwindow_buffers()
end

return M
