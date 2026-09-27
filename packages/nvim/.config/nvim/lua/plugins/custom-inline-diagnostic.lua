return {
  dir = vim.fn.stdpath("config") .. "/lua/custom/aligned-inline-diagnostic.nvim/",
  name = "aligned-inline-diagnostic.nvim",
  main = "aligned-inline-diagnostic",
  event = "VeryLazy",
  opts = {
    alignment = {
      mode = "block",
      padding = 8,
    },
    hover = {
      input_mode = "both", -- "cursor", "mouse", or "both"
    }
  },
}
