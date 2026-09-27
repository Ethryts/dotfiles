vim.pack.add({
  "https://github.com/stevearc/oil.nvim",
})

require("oil").setup({
  columns = {
    "permissions",
    "size",
  },
})

vim.keymap.set("n", "-", "<cmd>Oil<cr>", {
  desc = "Open parent directory",
})
