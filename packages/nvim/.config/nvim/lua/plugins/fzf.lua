local function diagnostics_with_toggle()
  local fzf = require("fzf-lua")
  local bufHasDiag = #vim.diagnostic.get(0) > 0
  if not bufHasDiag then
    fzf.diagnostics_workspace({
      header = "Workspace Diagnostics (Press Ctrl-G to toggle Document Diagnostics)",
      actions = {
        ["ctrl-g"] = function()
          fzf.diagnostics_document({
            header = "Document Diagnostics (Press Ctrl-G to toggle Workspace Diagnostics)",
            actions = { ["ctrl-g"] = diagnostics_with_toggle }
          })
        end,
      },
    })
    return
  end
  fzf.diagnostics_document({
    header = "Document Diagnostics (Press Ctrl-G to toggle Workspace Diagnostics)",
    actions = {
      ["ctrl-g"] = function()
        fzf.diagnostics_workspace({
          header = "Workspace Diagnostics (Press Ctrl-G to toggle Document Diagnostics)",
          actions = { ["ctrl-g"] = diagnostics_with_toggle }
        })
      end,
    },
  })
end

local function nerd_glyphs(opts)
  opts = opts or {}
  local cache_dir = vim.fn.stdpath('cache')
  local cache_file = cache_dir .. '/nerd_glyphs.txt'

  -- Download & cache glyph database if missing
  if vim.fn.filereadable(cache_file) == 0 then
    vim.notify("Downloading Nerd Font glyph database...", vim.log.levels.INFO)
    local cmd = string.format(
      "curl -s https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json | jq -r 'to_entries[] | \"\\(.value.char)  \\(.key)\"' > %s",
      vim.fn.shellescape(cache_file)
    )
    vim.fn.system(cmd)
  end

  require('fzf-lua').fzf_exec("cat " .. vim.fn.shellescape(cache_file), vim.tbl_deep_extend("force", {
    prompt = 'Nerd Glyphs> ',
    actions = {
      -- Press Enter to insert glyph at cursor position
      ['default'] = function(selected)
        if not selected or #selected == 0 then return end
        local char = vim.split(selected[1], '%s+')[1]
        vim.api.nvim_put({ char }, 'c', true, true)
      end,
      -- Press Ctrl+Y to copy glyph to clipboard
      ['ctrl-y'] = function(selected)
        if not selected or #selected == 0 then return end
        local char = vim.split(selected[1], '%s+')[1]
        vim.fn.setreg('+', char)
        vim.notify('Copied ' .. char .. ' to clipboard!')
      end,
    },
  }, opts))
end

return {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { '<leader>ff', "<cmd>FzfLua files<cr>",                      "Find File" },
    { '<leader>fg', "<cmd>FzfLua live_grep<cr>",                  "Find Grep" },
    { '<leader>fn', "<cmd>FzfLua nerd_glyphs<cr>",                "Find Nerd Glyphs" },
    { '<leader>fc', "<cmd>FzfLua commands<cr>",                   "Find Commands" },
    { '<leader>fq', "<cmd>FzfLua quickfix<cr>",                   "Find Quickfix" },
    { '<leader>fb', "<cmd>FzfLua buffers<cr>",                    "Find Buffers" },
    { '<leader>fh', "<cmd>FzfLua help_tags<cr>",                  "Find Help Tags" },
    { '<leader>fd', diagnostics_with_toggle,                      "Find Diagnostics" },
    { '<leader>ft', "<cmd>FzfLua builtin<cr>",                    "Find Pickers" },
    { '<leader>fl', "<cmd>FzfLua lsp_live_workspace_symbols<cr>", "Find Lsp symbols" },
    { 'grd',        "<cmd>FzfLua lsp_definitions<cr>",            "Find Lsp symbols" },
    { 'grr',        "<cmd>FzfLua lsp_references<cr>",             "Find Lsp symbols" },
    { '<leader>fwt',
      function()
        local wtp = require("plugins.fzf_custom.worktree_picker")
        wtp.pick()
      end,
      "Git Worktrees" },
    { '<leader>fp',
      function()
        require("fzf-lua").files({
          cwd = "~/dev/",
          cmd = [[
          (
            fd --type d --exclude .git --max-depth 3 --exec sh -c 'test -d "{}/.git" && echo {}' 2>/devnull
          ) || (
            fd --type d --exclude .git --max-depth 3 --exec sh -c 'test ! -d "{}/.git" && test ! -d "$(dirname {})/.git" && test ! -d "$(dirname $(dirname {}))/.git" && echo {}' 2>/devnull
          )
          ]],
          previewer = false,
          fzf_opts = {
            ['--tiebreak'] = 'length',
            ['--preview'] = [[
               target=~/dev/$(echo {} | sed 's/^[^\.a-zA-Z0-9\/]*//')
               echo $target
               ls -lhF --color=always "$target" | awk '{printf "%-30s %-10s %-40s\n", $9, $5, $6" "$7" "$8}'
               count=$(ls -1 "$target" | wc -l)
               pad=$((10 - count))
               if [ $pad -gt 0 ]; then
                  for i in $(seq 1 $pad); do
                    echo ""
                  done
               fi
                readme=$(fd --max-depth 2 --type f "readme.*" "$target"  | head -n 1)
                if [ -f "$readme" ]; then
                  echo "Previewing README:"
                  bat --style=header,grid --color=always "$readme"
                else
                  echo "No README file found"
                fi
               echo "Directory size:"
               du -sh "$target" | awk '{printf "%-10s %-20s\n", $1, $2}'
              ]]
          },
          prompt = "Dirs>",
          actions = {
            ["default"] = function(selected)
              local fzf = require("fzf-lua")
              local entry = fzf.path.entry_to_file(selected[1])
              local dir = entry.path
              vim.cmd("cd ~/dev/" .. dir)
              require("fzf-lua").files()
            end,
          },
        })
      end,
      "Find Projects"
    }
  },
  ---@module 'fzf-lua'
  ---@type fzf-lua.config
  ---@diagnostic disable-next-line: missing-fields
  opts = {
    fzf_opts = {},
    keymap = {
      fzf = {
        ["ctrl-y"] = "accept",
        ["ctrl-u"] = "preview-page-up",
        ["ctrl-d"] = "preview-page-down",
        ["tab"] = "toggle+down",
        ["shift-tab"] = "up+toggle"
      },
      builtin = {
        ["<F1>"] = "toggle-help",
        ["<C-v>"] = "file_vsplit",
        ["<C-x>"] = "file_split",
        ["<C-t>"] = "file_tabedit",
      }
    },
    keymaps = {
      prompt = "Keymaps> ",
      ignore_patters = false,
    },
  },
  config = function(_, opts)
    local fzf = require("fzf-lua")
    fzf.setup(opts)

    -- Register function reference on fzf-lua module so `:FzfLua builtin` picks it up
    fzf.nerd_glyphs = nerd_glyphs

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "fzf",
      callback = function(ev)
        vim.keymap.set("t", "jk", "<Nop>", { buffer = ev.buf, silent = true, desc = "Disable jk in FzfLua" })
      end
    })
    fzf.register_ui_select()
  end,
}
