local patterns = {
  "from",
  "join",
  "update",
  "into",
  "table",
}
return {
  'saghen/blink.cmp',
  event = "VeryLazy",
  -- optional: provides snippets for the snippet source
  dependencies = {
    'rafamadriz/friendly-snippets',
    'Kaiser-Yang/blink-cmp-avante',
    'folke/lazydev.nvim',

    { 'fang2hou/blink-copilot',           opts = {} },
    -- 'Kaiser-Yang/blink-cmp-avante',
    { 'Kaiser-Yang/blink-cmp-dictionary', dependencies = { 'nvim-lua/plenary.nvim' } }
  },

  -- use a release tag to download pre-built binaries
  version = '1.*',
  -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
  -- build = 'cargo build --release',
  -- If you use nix, you can build from source using latest nightly rust with:
  -- build = 'nix run .#build-plugin',
  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    -- 'default' (recommended) for mappings similar to built-in completions (C-y to accept)
    -- 'super-tab' for mappings similar to vscode (tab to accept)
    -- 'enter' for enter to accept
    -- 'none' for no mappings
    --
    -- All presets have the following mappings:
    -- C-space: Open menu or open docs if already open
    -- C-n/C-p or Up/Down: Select next/previous item
    -- C-e: Hide menu
    -- C-k: Toggle signature help (if signature.enabled = true)
    --
    -- See :h blink-cmp-config-keymap for defining your own keymap
    keymap = {
      preset = 'default',
      ['<C-n>'] = { 'select_next', 'show', 'fallback_to_mappings' },
    },

    appearance = {
      -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
      -- Adjusts spacing to ensure icons are aligned
      nerd_font_variant = 'mono'
    },

    -- (Default) Only show the documentation popup when manually triggered
    completion = { documentation = { auto_show = false }, trigger = { prefetch_on_insert = false } },

    -- Default list of enabled providers defined so that you can extend it
    -- elsewhere in your config, without redefining it, due to `opts_extend`
    sources = {
      default = { 'lazydev', 'avante', 'lsp', 'snippets', 'path', 'buffer', },
      per_filetype = {
        sql = { inherit_defaults = true, 'dictionary' }
      },
      providers = {
        copilot = {
          name = "copilot",
          module = "blink-copilot",
          score_offset = 100,
          async = true,
          opts = {
            -- Local options override global ones
            max_completions = 3, -- Override global max_completions

            -- Final settings:
            -- * max_completions = 3
            -- * max_attempts = 2
            -- * all other options are default
          }
        },
        lazydev = {
          name = "LazyDev",
          module = "lazydev.integrations.blink",
          score_offset = 100
        },
        avante = {
          module = 'blink-cmp-avante',
          name = 'Avante',

        },

        -- avante = {
        --     module = 'blink-cmp-avente',
        --     name = 'Avante',
        --     opts =  {}
        -- },
        dictionary = {
          module = "blink-cmp-dictionary",
          name = "Tables",
          min_keyword_length = 2,
          opts = {
            get_insert_text = function(item)
              local right = item:match("%.([^%.]+)")
              if right then
                return right
              end
              return item
            end,
            dictionary_files = function()
              local dictsPaths = {
                schema = vim.fn.expand("~/nvim-data/schemas.dict"),
                table = vim.fn.expand("~/nvim-data/tables.dict"),
                column = vim.fn.expand("~/nvim-data/columns.dict")
              }
              local window = vim.api.nvim_get_current_win()
              local cursor = vim.api.nvim_win_get_cursor(window)
              local row, col = cursor[1], cursor[2]

              -- Get all lines up to the cursor row
              local lines = vim.api.nvim_buf_get_lines(0, 0, row, false)
              local before = ""
              if #lines > 0 then
                -- Concatenate all previous lines
                for i = 1, #lines - 1 do
                  before = before .. lines[i] .. "\n"
                end
                -- Add the current line up to the cursor column
                before = before .. lines[#lines]:sub(1, col)
              end
              before = before:match("^%s*(.-)%s*$") -- trim whitespace

              local head = before:gsub("%s[%w_%.]+$", "")
              local keyword = head:match("([%w]+)$")
              for _, i in ipairs(patterns) do
                if keyword == i then
                  local last_word = before:match("([%w_%.]+)$")
                  if last_word then
                    last_word = last_word:match("^%s*(.-)%s*$") -- trim whitespace
                    -- Match schema.table, ignoring spaces around period
                    if last_word:match("([%w_]+)%s*%.%s*[%w_]+") then
                      return { dictsPaths.table }
                    end
                  end
                  return { dictsPaths.schema }
                end
              end
              return { dictsPaths.column }
            end,
            case_insensitive = true,
          },
        }

      }
    },
    snippets = { preset = 'luasnip' },
    -- signature = {enabled=true},

    -- (Default) Rust fuzzy matcher for typo resistance and significantly better performance
    -- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
    -- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
    --
    -- See the fuzzy documentation for more information
    fuzzy = { implementation = "prefer_rust_with_warning" }
  },
  opts_extend = { "sources.default" }
}
