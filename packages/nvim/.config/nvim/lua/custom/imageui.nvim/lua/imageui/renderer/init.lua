local rasterizer = require('imageui.renderer.rasterizer')
local scene = require('imageui.scene')
local scene_layout = require('imageui.scene.layout')
local scene_svg = require('imageui.scene.svg')
local svg = require('imageui.renderer.svg')
local theme = require('imageui.theme')

local M = {}

local config

---@param content table
---@return string[]
local function highlight_names(content)
  if content.kind == 'scene' then
    return scene.highlights(scene.normalize(assert(content.root, 'scene content requires root')))
  end
  local names = vim.deepcopy(content.highlights or { content.highlight or 'Normal' })
  if #names == 0 then
    names = { 'Normal' }
  end
  if content.highlight and not vim.tbl_contains(names, content.highlight) then
    names[#names + 1] = content.highlight
  end
  for _, span in ipairs(content.spans or {}) do
    if span.highlight and not vim.tbl_contains(names, span.highlight) then
      names[#names + 1] = span.highlight
    end
  end
  return names
end

---@param opts table
function M.setup(opts)
  config = opts
  rasterizer.setup(opts)
end

---@param content table
---@param win integer
---@param callback fun(asset?: table, err?: string)
---@return fun()? cancel
function M.render(content, win, callback)
  if content.kind == 'png' then
    assert(content.path or content.bytes, 'png content requires path or bytes')
    local key = content.key
    if not key and content.path then
      local absolute = vim.fs.abspath(content.path)
      local stat = vim.uv.fs_stat(absolute)
      local fingerprint = { absolute }
      if stat then
        vim.list_extend(fingerprint, {
          stat.size,
          stat.mtime and stat.mtime.sec or 0,
          stat.mtime and stat.mtime.nsec or 0,
        })
      end
      key = vim.fn.sha256(table.concat(fingerprint, '\0'))
    end
    callback({
      key = key or vim.fn.sha256(content.bytes),
      path = content.path,
      bytes = content.bytes,
      width_cells = assert(content.width_cells, 'png content requires width_cells'),
      height_cells = assert(content.height_cells, 'png content requires height_cells'),
      pixel_width = content.pixel_width,
      pixel_height = content.pixel_height,
      render_scale = content.render_scale or 1,
    })
    return nil
  end

  if content.kind == 'scene' then
    local root = scene.normalize(assert(content.root, 'scene content requires root'))
    local base_highlight = scene.highlight(root, 'Normal')
    local tabstop = vim.bo[vim.api.nvim_win_get_buf(win)].tabstop
    local compiled = scene_layout.compile(root, {
      tabstop = tabstop,
      resolve_border = function(border)
        return theme.resolve_border(win, border, config)
      end,
    })
    local names = scene.highlights(root)
    for _, item in ipairs(compiled.display) do
      if item.kind == 'border' then
        if not vim.tbl_contains(names, item.highlight) then
          names[#names + 1] = item.highlight
        end
        for _, highlight in pairs(item.highlights or {}) do
          if not vim.tbl_contains(names, highlight) then
            names[#names + 1] = highlight
          end
        end
      end
    end
    local styles = theme.snapshot(win, names, config, base_highlight)
    local source, metrics = scene_svg.render(compiled, {
      styles = styles,
      roles = scene.roles,
      cell_width = config.style.cell_width,
      cell_height = config.style.cell_height,
      render_scale = config.render.scale,
      tabstop = tabstop,
    })
    return rasterizer.render(source, metrics, function(asset, err)
      if not asset then
        callback(nil, err)
        return
      end
      callback(vim.tbl_extend('force', {}, asset, {
        manifest = {
          width_cells = compiled.width_cells,
          height_cells = compiled.height_cells,
          regions = compiled.regions,
        },
      }))
    end)
  end

  if content.kind == 'svg' then
    assert(
      type(content.source) == 'string' or type(content.source) == 'function',
      'svg content requires source'
    )
    local names = highlight_names(content)
    local styles = theme.snapshot(win, names, config)
    local context = {
      style = styles[content.highlight or names[1]],
      styles = styles,
      cell_width = config.style.cell_width,
      cell_height = config.style.cell_height,
      render_scale = config.render.scale,
    }
    local source = content.source
    if type(source) == 'function' then
      local ok, result = pcall(source, context)
      if not ok then
        callback(nil, 'custom SVG source failed: ' .. tostring(result))
        return nil
      end
      source = result
    end
    if type(source) ~= 'string' then
      callback(nil, 'custom SVG source must return a string')
      return nil
    end
    local width_cells = assert(content.width_cells, 'svg content requires width_cells')
    local height_cells = assert(content.height_cells, 'svg content requires height_cells')
    return rasterizer.render(source, {
      width_cells = width_cells,
      height_cells = height_cells,
      pixel_width = width_cells * config.style.cell_width * config.render.scale,
      pixel_height = height_cells * config.style.cell_height * config.render.scale,
      render_scale = config.render.scale,
    }, callback)
  end

  if content.kind ~= 'text' then
    callback(nil, ('unsupported content kind: %s'):format(tostring(content.kind)))
    return nil
  end

  local names = highlight_names(content)
  local styles = theme.snapshot(win, names, config)
  local scene = vim.tbl_deep_extend('force', vim.deepcopy(content), {
    style = styles[content.highlight or 'Normal'],
    styles = styles,
    render_scale = config.render.scale,
    tabstop = vim.bo[vim.api.nvim_win_get_buf(win)].tabstop,
  })
  local source, metrics = svg.text(scene)
  return rasterizer.render(source, metrics, callback)
end

---@param content table
---@param win integer
---@return string?
function M.style_key(content, win)
  if content.kind == 'png' then
    return nil
  end
  if content.kind == 'scene' then
    local root = scene.normalize(assert(content.root, 'scene content requires root'))
    local base_highlight = scene.highlight(root, 'Normal')
    local key = theme.material_fingerprint(win, scene.materials(root), config, base_highlight)
    local border_key = theme.border_fingerprint(win, scene.border_styles(root), config)
    local tabstop = vim.bo[vim.api.nvim_win_get_buf(win)].tabstop
    return vim.fn.sha256(table.concat({ key, border_key, tabstop }, '\0'))
  end
  local key = theme.fingerprint(win, highlight_names(content), config, content.kind == 'text')
  if content.kind == 'text' then
    key = vim.fn.sha256(key .. '\0' .. tostring(vim.bo[vim.api.nvim_win_get_buf(win)].tabstop))
  end
  return key
end

M.rasterizer = rasterizer
M.svg = svg

return M
