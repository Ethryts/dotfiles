local keymap = vim.keymap.set
local buf_opts = { buffer = true, silent = true }

keymap("n", "j", "gj", buf_opts)
keymap("n", "k", "gk", buf_opts)

vim.opt_local.spell = true

-- This was used from the quarto nvim kickstarter, no idea what it does
-- vim.b.slime_cell_delimiter = '```'

-- wrap text, but by word no character
-- indent the wrappped line
-- vim.wo.wrap = true
-- vim.wo.linebreak = true
-- vim.wo.breakindent = true
-- vim.wo.showbreak = '|'
