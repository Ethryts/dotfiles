return {
  {
    dir = vim.fn.stdpath("config") .. "/lua/custom/PyFix/",
    enabled = true,
    name = "Pyfix",
    ft = "python",
    dev = true,
    opts = {}
  },
  {
    dir = vim.fn.stdpath("config") .. "/lua/custom/imageui.nvim/",
    name = "imageui.nvim",
    dev = true,
    opts = {
      style = {
        font_family = "JetBrainsMono Nerd Font",
        cell_width = 9,
        cell_height = 18,
      },
      transport = {
        tmux = "on",
      },
      integrations = {
        codelens = {
          enabled = true,
          placement_order = { "above_blank", "above_clear", "right" },

          right = {
            always = true,
            anchor = "colorcolumn", -- or "window"
            side = "after",
            distance = 2,
          },
        },
      }
    },
  }

}
