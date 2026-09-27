vim.opt.autoindent = true  -- Autoindent
vim.opt.smartindent = true -- Autoindent
vim.opt.tabstop = 2        -- tab
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smd = false                              --turn off mode mesage
vim.opt.nu = true                                -- number
vim.opt.rnu = true                               -- relative number
vim.opt.ignorecase = true                        --ignore case on search
vim.opt.smartcase = true                         --ignore case only if all lower
vim.opt.scrolloff = 8                            --scroll off amount
vim.opt.incsearch = true                         -- search incremently
vim.opt.hlsearch = true                          -- highlight search as you type
vim.opt.mouse = "a"                              -- where you can use mouse
vim.opt.autoread = true                          -- auto-reload files changed outside
vim.opt.writebackup = true                       -- temp backup during write
vim.opt.guifont = { "CaskaydiaCove NF", ":h12" } --font in gui environments "Font:fontsize"
vim.opt.termguicolors = true
vim.opt.laststatus = 3
-- vim.opt.fileformat = 'unix'
-- vim.opt.winbar=" " -- Start with an empty winbar so that it doesn't require resize on load

vim.opt.signcolumn = "yes" -- always show sign column to prevent text shifting

vim.g.splitright = true
vim.g.health = { style = 'float' }
vim.opt.completeopt = { "menuone", "noselect" }
-- vim.diagnostic.config({
--   virtual_text = true,
--   severity_sort = true,
--   float = {
--     source = true,
--   }
-- })
-- vim.diagnostic.config({
--   virtual_text = {
--     -- Prefix handles padding and tree branch icons for multiple errors on one line
--     prefix = function(diagnostic, i, total)
--       local bufnr = diagnostic.bufnr
--       local max_col_limit = 80 -- Extended alignment limit
--
--       -- 1. Find longest line with diagnostics in current buffer
--       local diagnostics = vim.diagnostic.get(bufnr)
--       local max_line_len = 0
--       for _, d in ipairs(diagnostics) do
--         local line_text = vim.api.nvim_buf_get_lines(bufnr, d.lnum, d.lnum + 1, false)[1] or ""
--         if #line_text > max_line_len then
--           max_line_len = #line_text
--         end
--       end
--
--       -- 2. Calculate padding spaces to target column
--       local target_col = math.min(max_line_len, max_col_limit)
--       local current_line_text = vim.api.nvim_buf_get_lines(bufnr, diagnostic.lnum, diagnostic.lnum + 1, false)[1] or ""
--       local current_len = #current_line_text
--       local padding = math.max(1, target_col - current_len)
--
--       -- 3. Highlight group (transparent background padding)
--       local severity_names = { "Error", "Warn", "Info", "Hint" }
--       local prefix_hl = "DiagnosticSign" .. (severity_names[diagnostic.severity] or "Error")
--
--       -- 4. Tree branch icon formatting (● for first error, └ for subsequent errors)
--       local icon = (i == 1) and "● " or "└ "
--       local pad_str = (i == 1) and string.rep(" ", padding) or " "
--
--       return pad_str .. icon, prefix_hl
--     end,
--
--     -- Format diagnostic message + append error code/source if present
--     format = function(diagnostic)
--       local code = diagnostic.code or
--           (diagnostic.user_data and diagnostic.user_data.lsp and diagnostic.user_data.lsp.code)
--       if code then
--         return string.format("%s [%s]", diagnostic.message, code)
--       end
--       return diagnostic.message
--     end,
--   },
-- })
vim.opt.updatetime = 300
--
-- local diag_winid = nil
-- local diag_lnum = nil
-- local active_target_col = nil
--
-- -- Adjust this if you ever need to micro-adjust horizontal alignment (+5 added here)
-- local SHIFT_RIGHT = 5
--
-- local augroup = vim.api.nvim_create_augroup("AlignedDiagnosticFloat", { clear = true })
--
-- -- Soft severity mapping (uses foreground colors for border/icon instead of harsh solid backgrounds)
-- local severity_map = {
--   [1] = { border_hl = "DiagnosticError" },
--   [2] = { border_hl = "DiagnosticWarn" },
--   [3] = { border_hl = "DiagnosticInfo" },
--   [4] = { border_hl = "DiagnosticHint" },
-- }
--
-- local function get_line_severity(diags)
--   local min_sev = 4
--   for _, d in ipairs(diags) do
--     if d.severity < min_sev then min_sev = d.severity end
--   end
--   return min_sev
-- end
--
-- local function update_or_open_float()
--   local bufnr = vim.api.nvim_get_current_buf()
--   local cursor = vim.api.nvim_win_get_cursor(0)
--   local lnum = cursor[1] - 1
--   local col = cursor[2]
--
--   -- 1. If window is already open on this line, update relative offset on horizontal move
--   if diag_winid and vim.api.nvim_win_is_valid(diag_winid) and diag_lnum == lnum then
--     local col_offset = active_target_col - col + SHIFT_RIGHT
--     local win_config = vim.api.nvim_win_get_config(diag_winid)
--     win_config.relative = "cursor"
--     win_config.row = 0
--     win_config.col = col_offset
--     vim.api.nvim_win_set_config(diag_winid, win_config)
--     return
--   end
--
--   -- Close existing window when changing lines
--   if diag_winid and vim.api.nvim_win_is_valid(diag_winid) then
--     vim.api.nvim_win_close(diag_winid, true)
--     diag_winid = nil
--   end
--
--   local line_diags = vim.diagnostic.get(bufnr, { lnum = lnum })
--   if #line_diags == 0 then return end
--
--   -- 2. Calculate Target Column using display width (handles UTF-8 and tabs)
--   local max_col_limit = 80
--   local all_diags = vim.diagnostic.get(bufnr)
--   local max_line_len = 0
--   for _, d in ipairs(all_diags) do
--     local line_text = vim.api.nvim_buf_get_lines(bufnr, d.lnum, d.lnum + 1, false)[1] or ""
--     local line_width = vim.fn.strdisplaywidth(line_text)
--     if line_width > max_line_len then max_line_len = line_width end
--   end
--
--   local current_line_text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
--   local current_width = vim.fn.strdisplaywidth(current_line_text)
--
--   active_target_col = math.min(max_line_len, max_col_limit)
--   active_target_col = math.max(active_target_col, current_width + 1)
--
--   local col_offset = active_target_col - col + SHIFT_RIGHT
--
--   -- 3. Determine Highest Severity on Line for Border Color
--   local top_sev = get_line_severity(line_diags)
--   local sev_info = severity_map[top_sev] or severity_map[1]
--
--   -- 4. Open Float Window
--   local _, winid = vim.diagnostic.open_float(nil, {
--     scope = "line",
--     focusable = false,
--     border = "rounded", -- Soft rounded edges
--     header = "",
--     prefix = function(diagnostic, i)
--       local icon = (i == 1) and "● " or "└ "
--       return icon, sev_info.border_hl
--     end,
--     format = function(diagnostic)
--       local code = diagnostic.code or
--       (diagnostic.user_data and diagnostic.user_data.lsp and diagnostic.user_data.lsp.code)
--       if code then
--         return string.format("%s [%s]", diagnostic.message, code)
--       end
--       return diagnostic.message
--     end,
--     source = "always",
--     close_events = { "BufLeave", "InsertEnter", "FocusLost" },
--   })
--
--   if winid and vim.api.nvim_win_is_valid(winid) then
--     diag_winid = winid
--     diag_lnum = lnum
--
--     -- Position float directly on line height with rightward offset
--     local win_config = vim.api.nvim_win_get_config(winid)
--     win_config.relative = "cursor"
--     win_config.row = 0
--     win_config.col = col_offset
--     vim.api.nvim_win_set_config(winid, win_config)
--
--     -- Soft Highlight: standard float background with colored rounded border
--     vim.wo[winid].winblend = 0
--     vim.wo[winid].winhighlight = string.format(
--       "NormalFloat:NormalFloat,FloatBorder:%s",
--       sev_info.border_hl
--     )
--   end
-- end
--
-- -- Autocommands
-- vim.api.nvim_create_autocmd("CursorHold", {
--   group = augroup,
--   callback = update_or_open_float,
-- })
--
-- vim.api.nvim_create_autocmd("CursorMoved", {
--   group = augroup,
--   callback = function()
--     if not diag_winid or not vim.api.nvim_win_is_valid(diag_winid) then return end
--     local cursor = vim.api.nvim_win_get_cursor(0)
--     local current_lnum = cursor[1] - 1
--
--     if current_lnum == diag_lnum then
--       update_or_open_float()
--     else
--       vim.api.nvim_win_close(diag_winid, true)
--       diag_winid = nil
--       diag_lnum = nil
--     end
--   end,
-- })
--

----
-- Global Options
vim.g.noru = true -- turno off ruler
vim.g.netrw_winsize = 20
-- vim.env.HOME = vim.env.USERPROFILE
vim.opt_global.winborder = "single"


vim.opt.shortmess:append("I") -- No intro message

vim.api.nvim_create_autocmd(
  { "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" },
  {
    callback = function()
      if vim.fn.getcmdwintype() == "" then
        vim.cmd("checktime")
      end
    end,
  })

vim.schedule(function() -- Set showtabline after other plugins have loaded
  vim.o.showtabline = 4
end
)

-- TODO: I should move this to a custom plugin

local function darken(color, amount)
  local input_type = type(color)

  if input_type == "string" then
    color = color:gsub("^#", "")
    color = assert(tonumber(color, 16), "invalid hex color")
  elseif input_type ~= "number" then
    error("color must be a #RRGGBB string or integer")
  end

  local factor = 1 - amount

  local r = math.floor(bit.band(bit.rshift(color, 16), 0xff) * factor)
  local g = math.floor(bit.band(bit.rshift(color, 8), 0xff) * factor)
  local b = math.floor(bit.band(color, 0xff) * factor)

  local result =
      bit.lshift(r, 16) +
      bit.lshift(g, 8) +
      b

  if input_type == "string" then
    return string.format("#%06x", result)
  end

  return result
end
local start = 99
local finish = start + 255

vim.opt.colorcolumn = table.concat(
  vim.iter(vim.fn.range(start, finish))
  :map(tostring)
  :totable(),
  ","
)

local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
local colorcolumn = darken(normal.bg, -0.1)
vim.api.nvim_set_hl(0, "ColorColumn", {
  bg = colorcolumn,
})
local function remove_bg(group)
  local hl = vim.api.nvim_get_hl(0, {
    name = group,
    link = false,
  })

  hl.bg = nil

  vim.api.nvim_set_hl(0, group, hl)
end

remove_bg("LspCodeLens")
remove_bg("LspCodeLensSeparator")
vim.api.nvim_set_hl(0, "PastColorColumn", {
  bg = colorcolumn,
})

vim.fn.matchadd("PastColorColumn", [[.\%>100v]])



local state_dir = vim.fn.stdpath("state")
vim.fn.mkdir(state_dir .. "/swap", "p")
vim.fn.mkdir(state_dir .. "/backup", "p")
vim.fn.mkdir(state_dir .. "/shada", "p")
vim.fn.mkdir(state_dir .. "/undo", "p")

vim.opt.swapfile = true
vim.opt.directory = state_dir .. "/swap//"
vim.opt.backup = false
vim.opt.backupdir = state_dir .. "/backup//"
vim.opt.backupskip = { "/tmp/*", "/var/tmp/*", "/run/*", "*/.git/*" }
vim.opt.undofile = true
vim.opt.undodir = state_dir .. "/undo"
vim.opt.shada = "!,'100,<50,s10,h"
vim.opt.shadafile = state_dir .. "/shada/main.shada"
