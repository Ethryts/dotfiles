if vim.g.loaded_imageui_nvim then
  return
end
vim.g.loaded_imageui_nvim = true

vim.api.nvim_create_user_command('ImageUI', function(opts)
  local imageui = require('imageui')
  if not imageui.is_configured() then
    imageui.setup()
  end
  require('imageui.commands').execute(opts)
end, {
  nargs = '*',
  desc = 'Manage imageui.nvim overlays',
})
