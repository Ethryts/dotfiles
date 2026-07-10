return {
  { 'ghassan0/telescope-glyph.nvim', lazy = true, dependencies = { 'kyazdani42/nvim-web-devicons' } },
  {
    'nvim-telescope/telescope.nvim',
    event = "VeryLazy",
    enabled = false,
    dependencies = {
      'nvim-lua/plenary.nvim',
      'BurntSushi/ripgrep',
      "OliverChao/telescope-picker-list.nvim",
      'nvim-telescope/telescope-project.nvim',
      'gbrlsnchs/telescope-lsp-handlers',
      'nvim-telescope/telescope-file-browser.nvim',
      'nvim-telescope/telescope-smart-history.nvim',
      'nvim-telescope/telescope-ui-select.nvim',
      'ghassan0/telescope-glyph.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        run =
        'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build'
      },
    },
    keys = {
      { "<leader>fp", "<CMD>Telescope project<CR>",                                                desc = "Find Project" },
      { "<leader>rr", "<Esc><cmd>lua require('telescope').extensions.refactoring.refactors()<CR>", mode = "v",           desc = "Refactoring Menu" },
    },
    opts = {
      defaults = {
        borderchars          =
        { "─", "│", "─", "│", "┌", "┐", "┘", "└" }
        ,
        mappings             = {
          n = {
            ['<C-y>'] = "select_default"
          },
          i = {
            ['<C-y>'] = "select_default"
          }
        },
        file_ignore_patterns = {
          "node_modules",
          ".git",
          "__pycache__",
          ".jython_cache",
          ".*$py.class",
          ".*$.pyc",
        },
        vimgrep_arguments    = {
          "rg",
          "--color=never",
          "--no-heading",
          "--with-filename",
          "--line-number",
          "--column",
          "--smart-case",
          "--auto-hybrid-regex"

        },
      },
      extensions = {
        file_browser = {},
        project = {},
        lsp_handlers = {
          code_action = {
            -- telescope = require('telescope.themes').get_dropdown({}),
          },
        },
        glyph = {},
        -- fzf = {},
        ["ui-select"] = {
          require("telescope.themes").get_dropdown({
            borderchars = {
              { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
              prompt = { "─", "│", " ", "│", "┌", "┐", "│", "│" },
              results = { "─", "│", "─", "│", "├", "┤", "┘", "└" },
              preview = { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
            },

          })
          -- layout_strategy = "cursor"
        },
        picker_list = {},
      },
    },
    config = function(ts, opts)
      local telescope = require('telescope')
      telescope.setup(opts)

      for ext, _ in pairs(opts.extensions) do
        telescope.load_extension(ext)
      end
    end,
  },
}
