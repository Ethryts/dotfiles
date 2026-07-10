return {
  {
    'MeanderingProgrammer/render-markdown.nvim',
    enabled = true,
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {
      file_types = { 'markdown', 'codecompanion' },
      code = {
        conceal_delimiters = false,
      },
      patterns = {

        markdown = {
          disable = true,
          directives = {
            { name = 'conceal_lines' },
            { id = 17,               name = 'conceal_lines' },
            { id = 18,               name = 'conceal_lines' },
          },
        },
      }
      -- win_options = {
      --   conceallevel = { default = 0, rendered = 0 },
      -- }

    },
  },
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && yarn install",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    config = function()
      vim.cmd([[
            function OpenMarkdownPreview (url)
                " execute "silent ! start chrome --app=" . a:url
                " execute "silent !  chrome --app=" . a:url
                execute "silent ! open -a chrome.exe -n --args --new-window " . a:url
            endfunction
            let g:mkdp_browserfunc = 'OpenMarkdownPreview'
            ]])
    end,
    ft = { "markdown" },
  },

}
