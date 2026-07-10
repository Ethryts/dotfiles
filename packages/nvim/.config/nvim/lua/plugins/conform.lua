return {
  {
    'stevearc/conform.nvim',
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      {
        -- Customize or remove this keymap to your liking
        "<leader>cf",
        function()
          require("conform").format({ async = true, lsp_format = "fallback" })
        end,
        mode = "n",
        desc = "Format buffer",
      },
    },
    ---@module "conform"
    ---@type conform.setupOpts
    opts = {
      -- Define your formatters
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "black" },
        javascript = { "eslint" },
        typescript = { "eslint" },
        sql = { "sql_formatter" }
      },
      -- Set default options
      default_format_opts = {
        lsp_format = "fallback",
      },
      -- Set up format-on-save
      -- format_on_save = { timeout_ms = 500 },
      -- Customize formatters
      formatters = {
        sql_formatter = {
          prepend_args = { "--config", [[{"language":"tsql"}]] }
        },
        injected = {
          lang_to_format = {
            sql = { "sql_formatter" }
          }
        },
        shfmt = {
          prepend_args = { "-i", "2" },
        },
      },
    },
    init = function()
      vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = { "*.lua" },
        desc = "Format specific filetypes on save",
        callback = function(args)
          require("conform").format({ bufnr = args.buf, async = false, lsp_fallback = true })
        end
      })
    end
  }
}
