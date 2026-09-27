return {
  "nvim.difftool",
  virtual = true,
  cmd = "DiffTool",
  config = function()
    vim.cmd("packadd nvim.difftool")
  end
}
