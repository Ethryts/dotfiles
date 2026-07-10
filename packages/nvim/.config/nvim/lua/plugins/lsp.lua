return {
  { "Hoffs/omnisharp-extended-lsp.nvim" },
  {
    "neovim/nvim-lspconfig",
    event = "VeryLazy",
    opts = {

      marksman = {
        filetypes = { "markdown", "quarto" }
      },
      -- copilot = {},
      omnisharp = {
        cmd = { "omnisharp" }, -- Mason installs OmniSharp with this name by default

        enable_roslyn_analyzers = true,
        organize_imports_on_format = true,
        enable_import_completion = true,


        on_attach = function(_, bufnr)
          local opts = { noremap = true, silent = true }
          local function buf_set_option(name, value)
            vim.api.nvim_set_option_value(name, value, { buf = bufnr })
          end
          buf_set_option("omnisharp", "omnisharp")
          vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gd', require('omnisharp_extended').lsp_definitions,
            opts)
          vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gi',
            require('omnisharp_extended').lsp_implementation, opts)
          vim.api.nvim_buf_set_keymap(bufnr, 'n', 'gr', require('omnisharp_extended').lsp_references,
            opts)
          vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>D',
            require('omnisharp_extended').lsp_type_definition, opts)
          -- vim.api.nvim_buf_set_keymap(bufnr, 'n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
        end,

      },
      gopls = {
        settings = {
          codelenses = {
            test = true,
          }
        }
      },
      clangd = {
        cmd = {
          "clangd",
          "--background-index",
          "--query-driver=" .. vim.fn.expand("~") .. "/.arduino15/packages/esp32/tools/esp-x32/*/bin/xtensa-esp32s3-elf-*",
        }
      },
      vtsls = {
        settings = {
          complete_function_calls = true,
          vtsls = {
            enableMoveToFileCodeAction = true,
            autoUseWorkspaceTsdk = true,
            experimental = {
              maxInlayHintLength = 30,
              completion = {
                enableServerSideFuzzyMatch = true,
              },
            },
          },
          typescript = {
            updateImportsOnFileMove = { enabled = "always" },
            suggest = {
              completeFunctionCalls = true,
            },
            inlayHints = {
              enumMemberValues = { enabled = true },
              functionLikeReturnTypes = { enabled = true },
              parameterNames = { enabled = "literals" },
              parameterTypes = { enabled = true },
              propertyDeclarationTypes = { enabled = true },
              variableTypes = { enabled = false },
            },
          },
        }
      },
      jdtls = {
        settings = {
          java = {
            import = {
              gradle = {
                enabled = true,
                wrapper = {
                  enabled = true,
                },
              },
            },
            configuration = {
              updateBuildConfiguration = "automatic",
            },
          },
        },
      },
      ruff = {
        init_options = {
          settings = {
            lint = {
              ignore = { "F405" }

            }
          }
        }
      },
      basedpyright = {
        settings = {
          basedpyright = {
            analysis = {

              diagnosticSeverityOverrides = {
                -- reportWildcardImportFromLibrary = "None",
                reportTypeCommentUsage = false,
                reportUntypedNamedTuple = false,
                reportExplicitAny = false,
                reportAny = false,
                reportUnusedCallResult = 'information',
              },
              extraPaths = (function()
                local success, lsp_env = pcall(require, "lsp_env")
                if success and type(lsp_env) == "table" and lsp_env.python and lsp_env.python.extraPaths then
                  return lsp_env.python.extraPaths
                end
                return {}
              end)()
            }
          }
        }
      },
    },
    config = function(_, opts)
      for lsp_name, config in pairs(opts) do
        vim.lsp.config(lsp_name, config)
      end
      vim.lsp.enable(vim.tbl_keys(opts))
      -- vim.api.nvim_create_autocmd({ "CursorHold", "InsertLeave" }, {
      --   callback = function()
      vim.lsp.codelens.enable()
      --   end,
      -- })
      -- local function get_quarto_resource_path()
      --   local function strsplit(s, delimiter)
      --     local result = {}
      --     for match in (s .. delimiter):gmatch('(.-)' .. delimiter) do
      --       table.insert(result, match)
      --     end
      --     return result
      --   end
      --
      --   local f = assert(io.popen('quarto --paths', 'r'))
      --   local s = assert(f:read '*a')
      --   f:close()
      --   return strsplit(s, '\n')[2]
      -- end
      -- local lua_library_files = vim.api.nvim_get_runtime_file('', true)
      -- local lua_plugin_paths = {}
      -- local resource_path = get_quarto_resource_path()
      -- if resource_path == nil then
      --   vim.notify_once 'quarto not found, lua library files not loaded'
      -- else
      --   table.insert(lua_library_files, resource_path .. '/lua-types')
      --   table.insert(lua_plugin_paths, resource_path .. '/lua-plugin/plugin.lua')
      -- end




      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client.server_capabilities.inlayHintProvider then
            vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
          end
          -- whatever other lsp config you want
        end
      })
    end

  },
  { "williamboman/mason.nvim",          opts = {} },
  {
    "williamboman/mason-lspconfig.nvim",
    event = "VeryLazy",
    opts = {
      ensure_installed = {
        "marksman",
        "lua_ls",
        "bashls",
        "vtsls",
        "basedpyright",
      }
    }
  },
  {
    "folke/lazydev.nvim",
    ft = "lua", -- only load on lua files
    opts = {
      library = {
        -- See the configuration section for more details
        -- Load luvit types when the `vim.uv` word is found
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
      },
    },

  }

}
