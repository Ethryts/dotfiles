---@module "lazy"
---@type LazySpec
return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,
  build = ':TSUpdate',
  ---@module "nvim-treesitter"
  ---@type TSConfig
  ---@diagnostic disable-next-line: missing-fields
  opts = {
    ensure_installed = {
      "go",
      "json",
      "python",
      "html",
      "css",
      "sql",
      "dockerfile",
      "javascript",
      "typescript",
      "tsx",
      "lua",
      "bash",
      "desktop",
      "git_commit",
      "vim",
      "vimdoc",
    },
  },
  config = function(_, opts)
    require("nvim-treesitter").setup(opts)
    require("nvim-treesitter").install(opts.ensure_installed, { with_sync = true })
    vim.api.nvim_create_autocmd("FileType", {
      pattern = opts.ensure_installed,
      callback = function() vim.treesitter.start() end,
    })
  end
}
