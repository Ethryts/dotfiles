vim.pack.add({
  "https://github.com/ibhagwan/fzf-lua",
  "https://github.com/nvim-tree/nvim-web-devicons",
})

local fzf = require("fzf-lua")

local function nerd_glyphs(opts)
  opts = opts or {}

  local cache_dir = vim.fn.stdpath("cache")
  local cache_file = cache_dir .. "/nerd_glyphs.txt"

  vim.fn.mkdir(cache_dir, "p")

  if vim.fn.filereadable(cache_file) == 0 then
    vim.notify(
      "Downloading Nerd Font glyph database...",
      vim.log.levels.INFO
    )

    local command = string.format(
      [[curl -fsSL https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json |
        jq -r 'to_entries[] | "\(.value.char)  \(.key)"' > %s]],
      vim.fn.shellescape(cache_file)
    )

    vim.fn.system(command)

    if vim.v.shell_error ~= 0 then
      vim.notify(
        "Failed to download Nerd Font glyph database",
        vim.log.levels.ERROR
      )
      return
    end
  end

  local picker_opts = vim.tbl_deep_extend("force", {
    prompt = "Nerd Glyphs> ",

    actions = {
      default = function(selected)
        if not selected or #selected == 0 then
          return
        end

        local char = vim.split(selected[1], "%s+")[1]
        vim.api.nvim_put({ char }, "c", true, true)
      end,

      ["ctrl-y"] = function(selected)
        if not selected or #selected == 0 then
          return
        end

        local char = vim.split(selected[1], "%s+")[1]
        vim.fn.setreg("+", char)
        vim.notify("Copied " .. char .. " to clipboard")
      end,
    },
  }, opts)

  fzf.fzf_exec(
    "cat " .. vim.fn.shellescape(cache_file),
    picker_opts
  )
end

fzf.setup({
  fzf_opts = {},

  keymap = {
    fzf = {
      ["ctrl-y"] = "accept",
      ["ctrl-u"] = "preview-page-up",
      ["ctrl-d"] = "preview-page-down",
      ["tab"] = "toggle+down",
      ["shift-tab"] = "up+toggle",
    },

    builtin = {
      ["<F1>"] = "toggle-help",
      ["<C-v>"] = "file_vsplit",
      ["<C-x>"] = "file_split",
      ["<C-t>"] = "file_tabedit",
    },
  },

  keymaps = {
    prompt = "Keymaps> ",
    ignore_patterns = false,
  },
})

-- Expose the custom picker through :FzfLua nerd_glyphs and the builtin list.
fzf.nerd_glyphs = nerd_glyphs

local mappings = {
  { "<leader>ff", "<cmd>FzfLua files<cr>",     "Find files" },
  { "<leader>fg", "<cmd>FzfLua live_grep<cr>", "Find grep" },
  { "<leader>fn", nerd_glyphs,                 "Find Nerd glyphs" },
  { "<leader>fc", "<cmd>FzfLua commands<cr>",  "Find commands" },
  { "<leader>fq", "<cmd>FzfLua quickfix<cr>",  "Find quickfix" },
  { "<leader>fb", "<cmd>FzfLua buffers<cr>",   "Find buffers" },
  { "<leader>fh", "<cmd>FzfLua helptags<cr>",  "Find help tags" },
  { "<leader>ft", "<cmd>FzfLua builtin<cr>",   "Find pickers" },
  { "<leader>fr", "<cmd>FzfLua resume<cr>",    "Resume picker" },
}

for _, mapping in ipairs(mappings) do
  vim.keymap.set("n", mapping[1], mapping[2], {
    desc = mapping[3],
  })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "fzf",
  callback = function(event)
    vim.keymap.set("t", "jk", "<Nop>", {
      buffer = event.buf,
      silent = true,
      desc = "Disable jk in FzfLua",
    })
  end,
})

fzf.register_ui_select()
