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
vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = {
    source = true,
  }
})

-- Global Options
vim.g.noru = true -- turno off ruler
vim.g.netrw_winsize = 20
-- vim.env.HOME = vim.env.USERPROFILE
vim.opt_global.winborder = "single"


vim.opt.shortmess:append("I") -- No intro message

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
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
