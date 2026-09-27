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
vim.opt.updatetime = 300
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
