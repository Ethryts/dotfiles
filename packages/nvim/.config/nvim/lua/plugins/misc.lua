return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    ---@class wk.Opts
    opts = {
      presets = 'helix',
      spec = {
        { "<leader>f", group = "find" },
        { "<leader>a", group = "AI" },
        { "<leader>c", group = "code actions" }
      }

      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Local Keymaps (which-key)",
      },
    },
  },
  {
    "akinsho/toggleterm.nvim",
    enabled = true,
    opts = {
      open_mapping = [[<C-T>]],
      insert_mappings = false,
      -- shell = 'bash',
      winbar = {
        enabled = true,
        name_formatter = function(term) --  term: Terminal
          return term.name
        end
      }
    }
  },
}
