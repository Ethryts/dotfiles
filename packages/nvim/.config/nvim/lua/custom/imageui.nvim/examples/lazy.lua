return {
  dir = vim.fn.expand('~/src/imageui.nvim'),
  version = false,
  opts = {
    style = {
      font_family = 'JetBrainsMono Nerd Font',
      cell_width = 9,
      cell_height = 18,
    },
    placement = {
      partial = 'clip',
      occlusion = 'clip',
      scroll_debounce = 32,
    },
    render = {
      max_jobs = 4,
      max_queue = 256,
    },
    integrations = {
      codelens = {
        enabled = true,
        placement_order = { 'above_blank', 'above_clear', 'overlay', 'right', 'native' },
        relayout_debounce = 50,
        font_scale = 0.52,
        right = {
          always = false,
          anchor = 'window', -- or 'colorcolumn'
          side = 'before', -- or 'after' when using colorcolumn
          distance = 2,
        },
      },
    },
  },
}
