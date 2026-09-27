local M = {}

---@class ImageUI.Config
---@field enabled boolean
---@field backend 'auto'|'nvim_img'|table
---@field transport table
---@field placement table
---@field render table
---@field style table
---@field interactions table
---@field integrations table
---@field debug table

M.defaults = {
  enabled = true,
  backend = 'auto',
  transport = {
    tmux = 'auto', -- auto | on | off
    safe_reposition = 'auto', -- auto | on | off; auto protects WezTerm placement updates
  },
  placement = {
    clip = 'window', -- window | editor | none
    partial = 'clip', -- clip | hide | allow
    occlusion = 'clip', -- clip | hide | allow
    zindex = 50,
    debounce = 16,
    scroll_debounce = 32,
    max_fragments = 8,
  },
  render = {
    rasterizer = 'auto', -- auto | resvg | inkscape | rsvg-convert | magick | convert
    timeout = 5000,
    max_jobs = 4,
    max_queue = 256,
    scale = 2,
    cache = {
      max_entries = 256,
      max_bytes = 64 * 1024 * 1024,
      directory = vim.fs.joinpath(vim.fn.stdpath('cache'), 'imageui'),
    },
  },
  style = {
    font_family = 'monospace',
    font_file = nil,
    cell_width = 9,
    cell_height = 18,
    fallback_fg = '#d0d0d0',
    box_chars = nil,
  },
  interactions = {
    mouse = false,
    hover = false,
  },
  integrations = {
    codelens = {
      enabled = false,
      refresh = { 'LspAttach', 'BufEnter', 'BufWritePost' },
      refresh_on_change = true,
      debounce = 250,
      relayout_debounce = 50,
      font_scale = 0.52,
      layout = 'smart', -- smart | overlay | blank_line
      placement_order = nil, -- ordered: above_blank | above_clear | overlay | right | native | hide
      position = 'top', -- top | center | bottom
      offset_row = 0,
      offset_col = 0,
      separator = '  ·  ',
      highlight = 'LspCodeLens',
      separator_highlight = 'LspCodeLensSeparator',
      fallback = 'virtual_text', -- compatibility: virtual_text | none
      right = {
        always = false,
        anchor = 'window', -- window | colorcolumn
        side = 'before', -- before | after (colorcolumn only)
        distance = 2,
      },
    },
  },
  debug = {
    export_dir = nil,
  },
}

local enums = {
  ['transport.tmux'] = { auto = true, on = true, off = true },
  ['transport.safe_reposition'] = { auto = true, on = true, off = true },
  ['placement.clip'] = { window = true, editor = true, none = true },
  ['placement.partial'] = { clip = true, hide = true, allow = true },
  ['placement.occlusion'] = { clip = true, hide = true, allow = true },
  ['render.rasterizer'] = {
    auto = true,
    resvg = true,
    inkscape = true,
    ['rsvg-convert'] = true,
    magick = true,
    convert = true,
  },
  ['integrations.codelens.position'] = { top = true, center = true, bottom = true },
  ['integrations.codelens.layout'] = { smart = true, overlay = true, blank_line = true },
  ['integrations.codelens.fallback'] = { virtual_text = true, none = true },
  ['integrations.codelens.right.anchor'] = { window = true, colorcolumn = true },
  ['integrations.codelens.right.side'] = { before = true, after = true },
}

local function at_path(tbl, path)
  local value = tbl
  for part in path:gmatch('[^.]+') do
    value = value[part]
  end
  return value
end

---@param opts? table
---@return ImageUI.Config
function M.normalize(opts)
  vim.validate('opts', opts, 'table', true)
  opts = opts or {}

  local known = {}
  for key in pairs(M.defaults) do
    known[key] = true
  end
  for key in pairs(opts) do
    if not known[key] then
      vim.notify(('imageui.nvim: unknown top-level option %q'):format(key), vim.log.levels.WARN)
    end
  end

  local config = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts)
  for path, allowed in pairs(enums) do
    local value = at_path(config, path)
    if not allowed[value] then
      error(('imageui.nvim: invalid %s=%q'):format(path, tostring(value)))
    end
  end

  vim.validate({
    ['enabled'] = { config.enabled, 'boolean' },
    ['transport.tmux'] = { config.transport.tmux, 'string' },
    ['transport.safe_reposition'] = { config.transport.safe_reposition, 'string' },
    ['placement.debounce'] = { config.placement.debounce, 'number' },
    ['placement.scroll_debounce'] = { config.placement.scroll_debounce, 'number' },
    ['placement.max_fragments'] = { config.placement.max_fragments, 'number' },
    ['placement.zindex'] = { config.placement.zindex, 'number' },
    ['render.timeout'] = { config.render.timeout, 'number' },
    ['render.max_jobs'] = { config.render.max_jobs, 'number' },
    ['render.max_queue'] = { config.render.max_queue, 'number' },
    ['render.scale'] = { config.render.scale, 'number' },
    ['render.cache.directory'] = { config.render.cache.directory, 'string' },
    ['render.cache.max_entries'] = { config.render.cache.max_entries, 'number' },
    ['render.cache.max_bytes'] = { config.render.cache.max_bytes, 'number' },
    ['style.font_family'] = { config.style.font_family, 'string' },
    ['style.font_file'] = { config.style.font_file, 'string', true },
    ['style.cell_width'] = { config.style.cell_width, 'number' },
    ['style.cell_height'] = { config.style.cell_height, 'number' },
    ['style.fallback_fg'] = { config.style.fallback_fg, 'string', true },
    ['interactions.mouse'] = { config.interactions.mouse, 'boolean' },
    ['interactions.hover'] = { config.interactions.hover, 'boolean' },
    ['integrations.codelens.enabled'] = { config.integrations.codelens.enabled, 'boolean' },
    ['integrations.codelens.debounce'] = { config.integrations.codelens.debounce, 'number' },
    ['integrations.codelens.relayout_debounce'] = {
      config.integrations.codelens.relayout_debounce,
      'number',
    },
    ['integrations.codelens.font_scale'] = { config.integrations.codelens.font_scale, 'number' },
    ['integrations.codelens.offset_row'] = { config.integrations.codelens.offset_row, 'number' },
    ['integrations.codelens.offset_col'] = { config.integrations.codelens.offset_col, 'number' },
    ['integrations.codelens.refresh'] = { config.integrations.codelens.refresh, 'table' },
    ['integrations.codelens.placement_order'] = {
      config.integrations.codelens.placement_order,
      'table',
      true,
    },
    ['integrations.codelens.right.always'] = {
      config.integrations.codelens.right.always,
      'boolean',
    },
    ['integrations.codelens.right.distance'] = {
      config.integrations.codelens.right.distance,
      'number',
    },
  })

  local placement_modes = {
    above_blank = true,
    above_clear = true,
    overlay = true,
    right = true,
    native = true,
    hide = true,
  }
  if config.integrations.codelens.placement_order then
    assert(
      #config.integrations.codelens.placement_order > 0,
      'imageui.nvim: placement_order cannot be empty'
    )
    for index, mode in ipairs(config.integrations.codelens.placement_order) do
      assert(
        placement_modes[mode],
        ('imageui.nvim: invalid placement_order[%d]=%q'):format(index, tostring(mode))
      )
    end
  end

  assert(config.placement.debounce >= 0, 'imageui.nvim: placement.debounce cannot be negative')
  assert(
    config.placement.scroll_debounce >= 0,
    'imageui.nvim: placement.scroll_debounce cannot be negative'
  )
  assert(config.placement.max_fragments >= 1, 'imageui.nvim: max_fragments must be positive')
  assert(config.render.timeout > 0, 'imageui.nvim: render.timeout must be positive')
  assert(
    config.render.max_jobs >= 1 and config.render.max_jobs % 1 == 0,
    'imageui.nvim: render.max_jobs must be a positive integer'
  )
  assert(
    config.render.max_queue >= 1 and config.render.max_queue % 1 == 0,
    'imageui.nvim: render.max_queue must be a positive integer'
  )
  assert(config.style.cell_width > 0, 'imageui.nvim: style.cell_width must be positive')
  assert(config.style.cell_height > 0, 'imageui.nvim: style.cell_height must be positive')
  assert(config.render.scale >= 1, 'imageui.nvim: render.scale must be at least 1')
  assert(config.render.cache.max_entries > 0, 'imageui.nvim: cache.max_entries must be positive')
  assert(config.render.cache.max_bytes > 0, 'imageui.nvim: cache.max_bytes must be positive')
  assert(
    config.integrations.codelens.debounce >= 0,
    'imageui.nvim: codelens.debounce cannot be negative'
  )
  assert(
    config.integrations.codelens.relayout_debounce >= 0,
    'imageui.nvim: codelens.relayout_debounce cannot be negative'
  )
  assert(
    config.integrations.codelens.font_scale > 0,
    'imageui.nvim: codelens.font_scale must be positive'
  )
  assert(
    config.integrations.codelens.right.distance >= 0
      and config.integrations.codelens.right.distance % 1 == 0,
    'imageui.nvim: codelens.right.distance must be a non-negative integer'
  )

  return config
end

return M
