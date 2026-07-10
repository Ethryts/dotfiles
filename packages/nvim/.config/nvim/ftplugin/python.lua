
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.makeprg = 'python %'
vim.opt.efm = [[%C %.%#,%A  File "%f"\, line %l%.%#,%Z%[%^ ]%\@=%m]]

-- This was used from the quarto nvim kickstarter, no idea what it does
vim.b.slime_cell_delimiter = '#\\s\\=%%'

