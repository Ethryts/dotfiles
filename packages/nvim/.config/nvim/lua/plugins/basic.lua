return {
  { 'lewis6991/gitsigns.nvim' },
  { 'kyazdani42/nvim-web-devicons', lazy = true },
  {
    "tpope/vim-fugitive",
    event = "VeryLazy",
  },
  {
    "vhyrro/luarocks.nvim",
    priority = 9999, -- Very high priority is required, luarocks.nvim should run as the first plugin in your config.
    config = true,
  },                 -- This is for luarocks, used by other plugins
  {
    'TimUntersberger/neogit',
    dependencies = 'nvim-lua/plenary.nvim',
    event = "VeryLazy",
    enabled = false
  },

}
