return {
  "rcarriga/nvim-notify",
  opts = {
    on_open = function(win)
      vim.api.nvim_set_option_value("number", false, { win = win })
      vim.api.nvim_set_option_value("relativenumber", false, { win = win })
      vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
    end,
    render = "wrapped-compact",
    stages = {
      function(state)
        return {
          relative = "editor",
          anchor = "NE",
          row = 2, -- push down from the top
          col = vim.o.columns,
          width = state.message.width,
          height = state.message.height,
        }
      end,
      function()
        return { time = true }
      end,
      function(state, win)
        return {
          row = 2,
          col = vim.o.columns,
          width = state.message.width,
          height = state.message.height,
        }
      end,
    },
  },
  config = function(_, opts)
    vim.notify = require("notify")
    require("notify").setup(opts)
  end
}
