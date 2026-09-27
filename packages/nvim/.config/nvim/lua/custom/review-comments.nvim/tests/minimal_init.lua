local test_file = vim.fn.fnamemodify(vim.fn.expand('<sfile>:p'), ':p')
local plugin_root = vim.fn.fnamemodify(test_file, ':h:h')
local test_runtime = vim.fn.tempname()

vim.fn.mkdir(test_runtime, 'p')
vim.env.XDG_DATA_HOME = test_runtime .. '/data'
vim.env.XDG_STATE_HOME = test_runtime .. '/state'
vim.env.XDG_CACHE_HOME = test_runtime .. '/cache'
vim.g.loaded_remote_plugins = 1

vim.opt.runtimepath:prepend(plugin_root)
package.path = plugin_root .. '/?.lua;' .. plugin_root .. '/?/init.lua;' .. package.path
vim.opt.swapfile = false
vim.opt.shadafile = 'NONE'
vim.opt.shortmess:append('I')
