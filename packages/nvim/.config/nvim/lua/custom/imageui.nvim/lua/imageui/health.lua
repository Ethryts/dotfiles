local M = {}

function M.check()
  vim.health.start('imageui.nvim')

  local defaults = require('imageui.config').defaults
  local ok, plugin = pcall(require, 'imageui')
  local cfg = (ok and plugin.config) or defaults
  local backend = require('imageui.backend.nvim_img')
  local available, reason = backend.available()
  if available then
    local version = vim.version()
    vim.health.ok(
      ('vim.ui.img API is available in Neovim %d.%d.%d'):format(
        version.major,
        version.minor,
        version.patch
      )
    )
    local tmux_transport = require('imageui.transport.tmux')
    local in_tmux = tmux_transport.detected()
    if in_tmux then
      local state = tmux_transport.status()
      local geometry = tmux_transport.geometry()
      if type(cfg.backend) == 'table' then
        vim.health.info(
          'A custom backend is configured; it is responsible for tmux passthrough and transport recovery'
        )
        if state.enabled then
          vim.health.ok(
            ('tmux allows passthrough in this pane (allow-passthrough=%s)'):format(state.value)
          )
        else
          vim.health.warn(
            'tmux passthrough is unavailable to the custom backend'
              .. (state.error and (' (' .. state.error .. ')') or '')
          )
        end
      elseif cfg.backend == 'nvim_img' then
        vim.health.error(
          'The nvim_img compatibility backend does not wrap Kitty commands for tmux; use backend="auto"'
        )
      elseif cfg.backend == 'auto' and cfg.transport.tmux == 'off' then
        vim.health.error('tmux transport wrapping is disabled by transport.tmux="off"')
      elseif state.enabled then
        vim.health.ok(
          ('tmux Kitty passthrough is enabled (allow-passthrough=%s)'):format(state.value)
        )
        vim.health.info('Outer-terminal capability probing is skipped through tmux')
        if state.focus_events then
          vim.health.ok('tmux focus events are enabled for pane re-synchronization')
        else
          vim.health.warn(
            'tmux focus events are disabled; run `tmux set -g focus-events on`, then detach and reattach the client'
          )
        end
      elseif cfg.transport.tmux == 'on' then
        vim.health.warn(
          'tmux passthrough was forced but could not be verified: '
            .. (state.error or ('allow-passthrough=' .. tostring(state.value)))
        )
      else
        vim.health.error(
          'tmux blocks Kitty graphics passthrough; run `tmux set -g allow-passthrough on`'
            .. (state.error and (' (' .. state.error .. ')') or '')
        )
      end
      if cfg.backend == 'auto' and cfg.transport.tmux ~= 'off' then
        if geometry.valid then
          vim.health.ok(
            ('tmux maps pane cell 1,1 to outer-terminal cell %d,%d'):format(
              geometry.row + 1,
              geometry.col + 1
            )
          )
          if geometry.attached_clients and geometry.attached_clients > 1 then
            vim.health.warn(
              ('The session has %d attached clients; Kitty placements can only target one tmux client geometry reliably'):format(
                geometry.attached_clients
              )
            )
          end
          if
            geometry.client_termname
            and not (',' .. (geometry.client_termfeatures or '') .. ','):find(',sync,', 1, true)
          then
            vim.health.info(
              ('tmux client %s does not advertise synchronized updates; for WezTerm, add `set -as terminal-features ",%s:sync"`'):format(
                geometry.client_termname,
                geometry.client_termname
              )
            )
          end
        else
          vim.health.error(
            'tmux pane coordinates could not be resolved: '
              .. (geometry.error or 'unknown geometry error')
          )
        end
      end
    else
      local supported, message = backend.supported({ timeout = 500 })
      if supported then
        vim.health.ok('Terminal accepted the Kitty graphics protocol probe')
        if message then
          vim.health.info(message)
        end
      else
        vim.health.warn('Terminal image support was not confirmed: ' .. (message or 'no response'))
      end
    end
  else
    vim.health.error(reason)
  end

  local renderer = require('imageui.renderer.rasterizer')
  if cfg.backend == 'auto' then
    vim.health.ok(
      ('Pooled Kitty transport enabled (up to %d warm assets / %.0f MiB decoded)'):format(
        cfg.render.cache.max_entries,
        cfg.render.cache.max_bytes / 1024 / 1024
      )
    )
    local in_wezterm = vim.env.TERM_PROGRAM == 'WezTerm'
      or (type(vim.env.WEZTERM_EXECUTABLE) == 'string' and vim.env.WEZTERM_EXECUTABLE ~= '')
    if in_wezterm and cfg.transport.safe_reposition == 'off' then
      vim.health.warn(
        'WezTerm-safe placement replacement is disabled; use transport.safe_reposition="auto" while the upstream scrolling crash remains open'
      )
    elseif in_wezterm then
      vim.health.ok('WezTerm-safe delete-before-replace placement updates are enabled')
    end
  elseif cfg.backend == 'nvim_img' then
    vim.health.warn(
      'Using the unpooled vim.ui.img compatibility backend; rapid offscreen/re-entry can retransmit PNG data'
    )
  else
    vim.health.info('Using a custom image backend')
  end
  vim.health.info(('Renderer subprocess limit: %d'):format(cfg.render.max_jobs))

  if ok and plugin.is_configured() then
    local executable = renderer.executable()
    if executable then
      vim.health.ok(('SVG rasterizer: %s'):format(executable))
    else
      vim.health.error('No SVG rasterizer found; install resvg, Inkscape, librsvg, or ImageMagick')
    end
  else
    vim.health.info('Plugin has not been configured; rasterizer selection is deferred')
  end

  if vim.fn.executable('magick') == 1 or vim.fn.executable('convert') == 1 then
    vim.health.ok('ImageMagick is available for partial clipping')
  elseif cfg.placement.partial == 'clip' or cfg.placement.occlusion == 'clip' then
    vim.health.warn('ImageMagick is missing; partial images use their fallback or remain hidden')
  end

  local uis = vim.api.nvim_list_uis()
  if #uis == 0 then
    vim.health.warn('No attached UI; terminal image support cannot be exercised headlessly')
  elseif #uis > 1 then
    vim.health.warn(
      'Multiple attached UIs are not supported because image positions use one global grid'
    )
  else
    vim.health.ok('Single attached UI')
  end

  if cfg.style.font_family == 'monospace' then
    vim.health.info(
      'Using generic monospace; configure style.font_family for closer terminal-font matching'
    )
  else
    vim.health.ok(('Configured font family: %s'):format(cfg.style.font_family))
  end
  if cfg.style.font_file then
    if vim.uv.fs_stat(vim.fs.abspath(cfg.style.font_file)) then
      vim.health.ok(('Configured font file: %s'):format(cfg.style.font_file))
    else
      vim.health.error(('Configured font file does not exist: %s'):format(cfg.style.font_file))
    end
  end
  vim.health.info(('Cell metrics: %sx%s px'):format(cfg.style.cell_width, cfg.style.cell_height))
end

return M
