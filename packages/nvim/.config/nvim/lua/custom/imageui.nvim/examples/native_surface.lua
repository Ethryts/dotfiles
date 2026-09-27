local imageui = require('imageui')
local scene = imageui.scene

-- This is a visual enhancement attached to a normal buffer position. Neovim
-- still owns the buffer, cursor, selection, scrolling, and window chrome.
local actions = imageui.surface({
  anchor = { kind = 'buffer', buffer = 0, row = 20, col = 4 },
  appearance = 'inline',
  scene = scene.row({
    gap = 0.5,
    children = {
      scene.text({
        id = 'docs',
        text = '󰋖 docs',
        role = 'link',
        font_scale = 0.68,
        focusable = true,
        states = { focused = { role = 'selection', background = true } },
      }),
      scene.text({
        id = 'apply',
        text = '󰄬 apply',
        role = 'muted',
        font_scale = 0.68,
        focusable = true,
        states = { focused = { role = 'selection', background = true } },
      }),
    },
  }),
  focus = { order = { 'docs', 'apply' }, initial = 'docs', wrap = true },
  actions = {
    docs = {
      activate = function()
        vim.notify('Open documentation with a native Neovim action')
      end,
      click = function()
        vim.notify('Open documentation with a native Neovim action')
      end,
      -- Run the enhancement action and then replay <LeftMouse>, preserving
      -- Neovim's normal cursor/selection behavior underneath.
      consume = false,
    },
    apply = {
      activate = function()
        vim.notify('Apply with a native Neovim action')
      end,
      click = function()
        vim.notify('Apply with a native Neovim action')
      end,
    },
  },
})

-- Integrations decide their own mappings; ImageUI installs no focus mappings.
vim.keymap.set('n', ']i', function()
  actions:focus_next()
end, { desc = 'Focus next ImageUI action' })
vim.keymap.set('n', '[i', function()
  actions:focus_prev()
end, { desc = 'Focus previous ImageUI action' })
vim.keymap.set('n', '<leader>ia', function()
  actions:activate()
end, { desc = 'Activate focused ImageUI action' })

return actions
