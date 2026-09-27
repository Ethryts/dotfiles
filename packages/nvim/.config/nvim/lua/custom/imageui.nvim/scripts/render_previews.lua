local config = require('imageui.config').normalize({
  render = {
    rasterizer = 'auto',
    scale = 2,
    cache = {
      directory = vim.fs.joinpath(vim.fn.stdpath('cache'), 'imageui-previews'),
      max_entries = 32,
    },
  },
  style = {
    font_family = 'DejaVu Sans Mono',
    cell_width = 10,
    cell_height = 20,
  },
})

local fs = require('imageui.util.fs')
local renderer = require('imageui.renderer')
local rasterizer = require('imageui.renderer.rasterizer')

local output_dir = vim.fs.joinpath(vim.fn.getcwd(), 'examples', 'previews')
fs.ensure_dir(output_dir)

vim.api.nvim_set_hl(0, 'Normal', { fg = 0xcdd6f4, bg = 0x11111b })
vim.api.nvim_set_hl(0, 'LspCodeLens', { fg = 0x7f849c, italic = true })
vim.api.nvim_set_hl(0, 'LspCodeLensSeparator', { fg = 0x45475a })
vim.api.nvim_set_hl(0, 'NormalFloat', { fg = 0xcdd6f4, bg = 0x313244 })
vim.api.nvim_set_hl(0, 'FloatBorder', { fg = 0x89b4fa, bg = 0x313244 })
vim.api.nvim_set_hl(0, 'DiagnosticHint', { fg = 0x94e2d5, bg = 0x313244 })
vim.api.nvim_set_hl(0, 'Underlined', { fg = 0x89b4fa, underline = true })
vim.api.nvim_set_hl(0, 'Visual', { fg = 0x11111b, bg = 0x89b4fa })

renderer.setup(config)

local function copy(source, destination)
  local ok, err = vim.uv.fs_copyfile(source, destination)
  assert(ok, err)
end

local function render_content(content, filename)
  local done = false
  local result
  local failure
  renderer.render(content, vim.api.nvim_get_current_win(), function(asset, err)
    result = asset
    failure = err
    done = true
  end)
  assert(
    vim.wait(config.render.timeout + 1000, function()
      return done
    end, 10),
    'preview rendering timed out'
  )
  assert(result, failure)
  local destination = vim.fs.joinpath(output_dir, filename)
  copy(result.path, destination)
  return result, destination
end

local function code_lens(position, filename)
  return render_content({
    kind = 'text',
    highlight = 'LspCodeLens',
    font_scale = 0.52,
    height_cells = 1,
    min_width_cells = 32,
    position = position,
    spans = {
      { text = '3 references', highlight = 'LspCodeLens' },
      { text = '  ·  ', highlight = 'LspCodeLensSeparator' },
      { text = '1 implementation', highlight = 'LspCodeLens' },
    },
  }, filename)
end

local overlay_asset, overlay_path = code_lens('top', 'codelens-overlay.png')
local blank_asset, blank_path = code_lens('bottom', 'codelens-blank-line.png')

local scene = require('imageui.scene')
render_content({
  kind = 'scene',
  root = scene.box({
    role = 'inline',
    background = true,
    height = 1,
    padding = { left = 0.5, right = 0.5, top = 0.1, bottom = 0.1 },
    child = scene.row({
      gap = 0.5,
      children = {
        scene.text({ text = '↗ docs', role = 'link', font_scale = 0.68 }),
        scene.text({
          text = '✓ apply',
          role = 'selection',
          background = true,
          font_scale = 0.68,
        }),
        scene.text({ text = 'native actions', role = 'muted', font_scale = 0.58 }),
      },
    }),
  }),
}, 'native-surface.png')

local note_asset, note_path = render_content({
  kind = 'svg',
  width_cells = 38,
  height_cells = 5,
  highlights = { 'NormalFloat', 'FloatBorder', 'DiagnosticHint' },
  source = function(ctx)
    local normal = ctx.styles.NormalFloat
    local border = ctx.styles.FloatBorder
    local hint = ctx.styles.DiagnosticHint
    local width = 38 * ctx.cell_width * ctx.render_scale
    local height = 5 * ctx.cell_height * ctx.render_scale
    local font_size = ctx.cell_height * ctx.render_scale * 0.72
    return ([[
<svg xmlns="http://www.w3.org/2000/svg" xml:space="preserve" width="%d" height="%d" viewBox="0 0 %d %d">
  <path d="M 20 2 H %d Q %d 2 %d 22 V %d Q %d %d %d %d H 70 L 38 %d L 44 %d H 20 Q 2 %d 2 %d V 22 Q 2 2 20 2 Z"
        fill="%s" stroke="%s" stroke-width="2"/>
  <circle cx="30" cy="33" r="8" fill="%s"/>
  <text x="52" y="40" fill="%s" font-family="DejaVu Sans Mono" font-size="%f" font-weight="700">Review note</text>
  <text x="30" y="76" fill="%s" font-family="DejaVu Sans Mono" font-size="%f">This overlay is anchored to the extmark.</text>
  <text x="30" y="110" fill="%s" font-family="DejaVu Sans Mono" font-size="%f">Click to open the native editor action.</text>
</svg>]]):format(
      width,
      height,
      width,
      height,
      width - 20,
      width - 2,
      width - 2,
      height - 38,
      width - 2,
      height - 20,
      width - 20,
      height - 20,
      height - 2,
      height - 20,
      height - 20,
      height - 38,
      normal.bg,
      border.fg,
      hint.fg,
      normal.fg,
      font_size,
      normal.fg,
      font_size * 0.78,
      normal.fg,
      font_size * 0.78
    )
  end,
}, 'note-bubble.png')

local function image_uri(path)
  return vim.uri_from_fname(path)
end

local overlay_width = overlay_asset.pixel_width / overlay_asset.render_scale
local blank_width = blank_asset.pixel_width / blank_asset.render_scale
local note_width = note_asset.pixel_width / note_asset.render_scale
local note_height = note_asset.pixel_height / note_asset.render_scale

local preview_svg = ([[
<svg xmlns="http://www.w3.org/2000/svg" xml:space="preserve" width="1440" height="900" viewBox="0 0 1440 900">
  <defs>
    <filter id="shadow" x="-20%%" y="-20%%" width="140%%" height="160%%">
      <feDropShadow dx="0" dy="12" stdDeviation="18" flood-color="#000000" flood-opacity="0.45"/>
    </filter>
    <linearGradient id="title" x1="0" x2="1">
      <stop offset="0" stop-color="#181825"/>
      <stop offset="1" stop-color="#1e1e2e"/>
    </linearGradient>
  </defs>
  <rect width="1440" height="900" fill="#09090f"/>
  <rect x="60" y="46" width="1320" height="808" rx="16" fill="#11111b" filter="url(#shadow)"/>
  <rect x="60" y="46" width="1320" height="54" rx="16" fill="url(#title)"/>
  <rect x="60" y="84" width="1320" height="16" fill="url(#title)"/>
  <circle cx="92" cy="73" r="7" fill="#f38ba8"/>
  <circle cx="117" cy="73" r="7" fill="#f9e2af"/>
  <circle cx="142" cy="73" r="7" fill="#a6e3a1"/>
  <text x="720" y="80" fill="#bac2de" font-family="DejaVu Sans Mono" font-size="15" text-anchor="middle">imageui.nvim  •  codelens.lua</text>

  <rect x="60" y="100" width="286" height="704" fill="#181825"/>
  <line x1="346" y1="100" x2="346" y2="804" stroke="#313244"/>
  <text x="86" y="138" fill="#89b4fa" font-family="DejaVu Sans Mono" font-size="14" font-weight="700">OIL  //  lua/imageui</text>
  <text x="88" y="183" fill="#f9e2af" font-family="DejaVu Sans Mono" font-size="24">▣</text>
  <text x="124" y="180" fill="#cdd6f4" font-family="DejaVu Sans Mono" font-size="16">renderer/</text>
  <text x="88" y="224" fill="#94e2d5" font-family="DejaVu Sans Mono" font-size="24">◆</text>
  <text x="124" y="221" fill="#cdd6f4" font-family="DejaVu Sans Mono" font-size="16">placement.lua</text>
  <text x="88" y="265" fill="#cba6f7" font-family="DejaVu Sans Mono" font-size="24">●</text>
  <text x="124" y="262" fill="#cdd6f4" font-family="DejaVu Sans Mono" font-size="16">codelens.lua</text>
  <text x="88" y="306" fill="#89dceb" font-family="DejaVu Sans Mono" font-size="24">◇</text>
  <text x="124" y="303" fill="#cdd6f4" font-family="DejaVu Sans Mono" font-size="16">theme.lua</text>
  <rect x="75" y="335" width="256" height="1" fill="#313244"/>
  <text x="86" y="372" fill="#6c7086" font-family="DejaVu Sans Mono" font-size="13">large icon accents are a later</text>
  <text x="86" y="393" fill="#6c7086" font-family="DejaVu Sans Mono" font-size="13">integration; the core already</text>
  <text x="86" y="414" fill="#6c7086" font-family="DejaVu Sans Mono" font-size="13">supports image-backed widgets.</text>

  <rect x="346" y="100" width="1034" height="42" fill="#1e1e2e"/>
  <text x="375" y="127" fill="#cba6f7" font-family="DejaVu Sans Mono" font-size="14">󰆍  lua/imageui/integrations/codelens.lua</text>
  <rect x="346" y="142" width="64" height="662" fill="#151521"/>

  <g font-family="DejaVu Sans Mono" font-size="17">
    <g fill="#585b70" text-anchor="end">
      <text x="394" y="184">42</text><text x="394" y="214">43</text><text x="394" y="244">44</text>
      <text x="394" y="274">45</text><text x="394" y="304">46</text><text x="394" y="334">47</text>
      <text x="394" y="364">48</text><text x="394" y="394">49</text><text x="394" y="424">50</text>
      <text x="394" y="454">51</text><text x="394" y="484">52</text><text x="394" y="514">53</text>
      <text x="394" y="544">54</text><text x="394" y="574">55</text><text x="394" y="604">56</text>
      <text x="394" y="634">57</text><text x="394" y="664">58</text><text x="394" y="694">59</text>
    </g>
    <text x="430" y="184"><tspan fill="#cba6f7">local function</tspan><tspan fill="#89b4fa"> reconcile</tspan><tspan fill="#cdd6f4">(state)</tspan></text>
    <text x="450" y="214"><tspan fill="#cba6f7">for</tspan><tspan fill="#cdd6f4"> _, widget </tspan><tspan fill="#cba6f7">in</tspan><tspan fill="#89dceb"> ipairs</tspan><tspan fill="#cdd6f4">(state.widgets) </tspan><tspan fill="#cba6f7">do</tspan></text>
    <text x="470" y="244"><tspan fill="#89dceb">place</tspan><tspan fill="#cdd6f4">(widget, </tspan><tspan fill="#f9e2af">{ clip = true }</tspan><tspan fill="#cdd6f4">)</tspan></text>
    <text x="450" y="274" fill="#cba6f7">end</text>
    <text x="430" y="304" fill="#cba6f7">end</text>

    <text x="430" y="394"><tspan fill="#cba6f7">local function</tspan><tspan fill="#89b4fa"> refresh_lenses</tspan><tspan fill="#cdd6f4">(buffer)</tspan></text>
    <text x="450" y="424"><tspan fill="#6c7086">-- no virtual line is inserted here</tspan></text>
    <text x="450" y="454"><tspan fill="#cba6f7">return</tspan><tspan fill="#89dceb"> request</tspan><tspan fill="#cdd6f4">(buffer)</tspan></text>
    <text x="430" y="484" fill="#cba6f7">end</text>

    <text x="430" y="574"><tspan fill="#cba6f7">local</tspan><tspan fill="#cdd6f4"> note = imageui.</tspan><tspan fill="#89dceb">create</tspan><tspan fill="#cdd6f4">({</tspan></text>
    <text x="450" y="604"><tspan fill="#89b4fa">anchor</tspan><tspan fill="#cdd6f4"> = extmark,</tspan></text>
    <text x="450" y="634"><tspan fill="#89b4fa">content</tspan><tspan fill="#cdd6f4"> = note_scene,</tspan></text>
    <text x="430" y="664" fill="#cdd6f4">})</text>
  </g>

  <image href="%s" x="430" y="158" width="%f" height="20"/>
  <rect x="420" y="151" width="560" height="42" rx="5" fill="none" stroke="#89b4fa" stroke-opacity="0.28" stroke-dasharray="5 5"/>
  <text x="1000" y="176" fill="#89b4fa" font-family="DejaVu Sans Mono" font-size="12">SMART OVERLAY · same grid row</text>

  <image href="%s" x="430" y="340" width="%f" height="20"/>
  <rect x="420" y="333" width="560" height="37" rx="5" fill="none" stroke="#a6e3a1" stroke-opacity="0.28" stroke-dasharray="5 5"/>
  <text x="1000" y="357" fill="#a6e3a1" font-family="DejaVu Sans Mono" font-size="12">SMART · existing blank row</text>

  <image href="%s" x="790" y="548" width="%f" height="%f"/>
  <text x="800" y="708" fill="#7f849c" font-family="DejaVu Sans Mono" font-size="12">CUSTOM SVG WIDGET · native action underneath</text>

  <rect x="60" y="804" width="1320" height="50" fill="#181825"/>
  <rect x="60" y="804" width="220" height="50" fill="#89b4fa"/>
  <text x="82" y="835" fill="#11111b" font-family="DejaVu Sans Mono" font-size="15" font-weight="700">NORMAL  imageui.nvim</text>
  <text x="1120" y="835" fill="#7f849c" font-family="DejaVu Sans Mono" font-size="13">extmark-bound • clipped • cached</text>
</svg>]]):format(
  image_uri(overlay_path),
  overlay_width,
  image_uri(blank_path),
  blank_width,
  image_uri(note_path),
  note_width,
  note_height
)

local finished = false
local preview_asset
local preview_error
rasterizer.render(preview_svg, {
  width_cells = 144,
  height_cells = 45,
  pixel_width = 1440,
  pixel_height = 900,
  render_scale = 1,
}, function(asset, err)
  preview_asset = asset
  preview_error = err
  finished = true
end)
assert(
  vim.wait(config.render.timeout + 1000, function()
    return finished
  end, 10),
  'composite preview rendering timed out'
)
assert(preview_asset, preview_error)
local preview_path = vim.fs.joinpath(output_dir, 'imageui-preview.png')
local compositor = vim.fn.executable('magick') == 1 and 'magick'
  or vim.fn.executable('convert') == 1 and 'convert'
if compositor then
  local command = {
    compositor,
    preview_asset.path,
    '(',
    overlay_path,
    '-resize',
    ('%dx20!'):format(overlay_width),
    ')',
    '-geometry',
    '+430+158',
    '-composite',
    '(',
    blank_path,
    '-resize',
    ('%dx20!'):format(blank_width),
    ')',
    '-geometry',
    '+430+340',
    '-composite',
    '(',
    note_path,
    '-resize',
    ('%dx%d!'):format(note_width, note_height),
    ')',
    '-geometry',
    '+790+548',
    '-composite',
    preview_path,
  }
  local result = vim.system(command, { text = true }):wait()
  assert(result.code == 0, result.stderr)
else
  copy(preview_asset.path, preview_path)
end

print('generated previews in ' .. output_dir)
