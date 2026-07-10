return {
  "zbirenbaum/copilot.lua",
  event = "VeryLazy",
  dependencies = {
    "copilotlsp-nvim/copilot-lsp", -- (optional) for NES functionality
  },
  opts = function()
    vim.env.NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt"
    vim.env.NODE_OPTIONS = "--use-openssl-ca"
    local dirs = { "~/.config/codecompanion/memories/python27.md" }
    -- insert the current git root if it exists
    local git_response = vim.system({ 'git', 'rev-parse', '--show-toplevel' })
    if git_response.code == 0 then
      local git_root = vim.trim(git_response.stdout)
      if git_root and git_root ~= "" then
        table.insert(dirs, git_root)
      end
    end
    return {
      workspace_folders = dirs,
      logger = {
        file_log_level = vim.log.levels.ERROR,
      },
      pannel = {
        enabled = false,
      },
      suggestion = {
        keymap = {
          accept = "<C-S-y>",
          accept_word = "<C-l>",
          next = "<C-N>",
          prev = "<C-P>",
          dismiss = "<C-E>",
        },
        auto_trigger = true,
      },
      nes = {
        -- enabled = true,
        -- auto_trigger = true,
      },
    }
  end
}
