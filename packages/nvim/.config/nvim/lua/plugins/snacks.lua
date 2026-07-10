return {
  "folke/snacks.nvim",
  ---@module "snacks.nvim"
  ---@type snacks.Config
  opts = {
    bigfile = {},
    input = {},
    indent = {},
    statuscolumn = {
      left = { "mark", "sign" }, -- priority of signs on the left (high to low)
      right = { "fold", "git" },
      -- right = { },     -- priority of signs on the right (high to low)
      folds = {
        open = false,   -- show open fold icons
        git_hl = false, -- use Git Signs hl for fold icons
      },
      git = {
        -- patterns to match Git signs
        patterns = { "GitSign", "MiniDiffSign" },
      },
      refresh = 50, -- refresh at most every 50ms
    },
  }
}
