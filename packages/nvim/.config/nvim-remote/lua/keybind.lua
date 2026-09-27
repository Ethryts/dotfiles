local keymap = vim.keymap.set
local M = {}

local function opts(desc)
  return { noremap = true, silent = true, desc = desc }
end

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Basic keybinds
keymap('i', 'jk', '<Esc>', opts("Exit insert mode"))
keymap('t', 'jk', '<C-\\><C-n>', opts("Exit terminal mode"))
keymap("v", "p", '"_dP', opts("Visual Mode Paste, maintains clipboard"))
keymap('n', 'gp', '`[v`]', opts("Select last pasted content"))


keymap('n', '<leader>/', "<cmd>execute 'lvimgrep /'.@/.'/ % | lopen'<CR>",
  opts("Open Last search in local quick fix list"))

local diagnostic = vim.diagnostic
keymap('n', '<leader>q', diagnostic.setloclist, opts("Set Location List with Diagnostics"))


local lsp = vim.lsp.buf

keymap('n', 'K', lsp.hover, opts("Show hover documentation"))
keymap('n', '<C-k>', lsp.signature_help, opts("Show signature help"))
keymap('n', '<leader>wa', lsp.add_workspace_folder, opts("Add Workspace Folder"))
keymap('n', '<leader>wr', lsp.remove_workspace_folder, opts("Remove Workspace Folder"))
keymap('n', '<leader>wl', function()
  print(vim.inspect(lsp.list_workspace_folders()))
end, opts("List Workspace Folder"))


keymap({ 'n', 'v' }, '<leader>ca', lsp.code_action, opts("select code action"))
keymap('n', '<leader>cl', vim.lsp.codelens.run, opts("select code lens"))
keymap('n', '<leader>rn', lsp.rename, opts("rename symbol"))

return M
