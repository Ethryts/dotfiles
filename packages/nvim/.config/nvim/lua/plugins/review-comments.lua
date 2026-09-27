return {
  dir = vim.fn.stdpath("config") .. "/lua/custom/review-comments.nvim/",
  enabled = true,
  name = "review-comments",
  -- ft = "markdown",
  dev = true,
  opts = {
    display = {
      sign_text = '󰆈'
    }
    -- header_indent = true,
    -- list_continue = true,
  },
}
