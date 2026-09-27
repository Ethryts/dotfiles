local M = {}

local demo_surface

local function imageui()
  return require('imageui')
end

local function codelens()
  return require('imageui.integrations.codelens')
end

local function export(args)
  local configured = imageui().config and imageui().config.debug.export_dir
  local default = configured
    or vim.fs.joinpath(vim.fn.stdpath('cache'), 'imageui', 'exports', os.date('%Y%m%d-%H%M%S'))
  local directory = args[2] and vim.fs.abspath(args[2]) or default
  local files = imageui().export(directory)
  vim.notify(('Exported %d files to %s'):format(#files, directory), vim.log.levels.INFO, {
    title = 'imageui.nvim',
  })
end

local function demo()
  if demo_surface then
    demo_surface:close()
    demo_surface = nil
  end
  local scene = imageui().scene
  demo_surface = imageui().surface({
    tag = 'demo',
    anchor = { kind = 'cursor', row = 1, col = 0 },
    appearance = 'inline',
    scene = scene.row({
      gap = 0.5,
      children = {
        scene.text({ text = 'ImageUI', highlight = 'Title', font_scale = 0.72 }),
        scene.text({ text = 'subcell enhancement', role = 'muted', font_scale = 0.58 }),
      },
    }),
    clip = 'window',
    partial = 'clip',
    occlusion = 'clip',
  })
end

local function execute(opts)
  local args = opts.fargs or vim.split(vim.trim(opts.args or ''), '%s+', { trimempty = true })
  local command = args[1] or 'inspect'
  if command == 'refresh' then
    imageui().refresh()
  elseif command == 'clear' then
    imageui().clear()
  elseif command == 'inspect' then
    vim.print(imageui().inspect())
  elseif command == 'export' then
    export(args)
  elseif command == 'demo' then
    demo()
  elseif command == 'reset' then
    imageui().reset_transport()
  elseif command == 'benchmark' then
    local benchmark = require('imageui.benchmark')
    local action = args[2] or 'report'
    if action == 'start' then
      local count = args[3] and tonumber(args[3]) or 12
      benchmark.start(count)
    elseif action == 'report' then
      benchmark.report()
    elseif action == 'stop' then
      benchmark.stop()
    else
      error(('unknown benchmark action: %s'):format(action))
    end
  elseif command == 'enable' then
    imageui().enable()
  elseif command == 'disable' then
    imageui().disable()
  elseif command == 'codelens' then
    local action = args[2] or 'toggle'
    if action == 'enable' then
      codelens().enable()
      vim.lsp.codelens.enable(true, { bufnr = 0 })
    elseif action == 'disable' then
      vim.lsp.codelens.enable(false, { bufnr = 0 })
    elseif action == 'toggle' then
      codelens().enable()
      local visible = vim.lsp.codelens.is_enabled({ bufnr = 0 })
      vim.lsp.codelens.enable(not visible, { bufnr = 0 })
    elseif action == 'refresh' then
      vim.lsp.codelens.refresh({ bufnr = 0 })
    elseif action == 'run' then
      vim.lsp.codelens.run({ bufnr = 0 })
    elseif action == 'inspect' then
      vim.print(codelens().inspect())
    else
      error(('unknown codelens action: %s'):format(action))
    end
  elseif command == 'health' then
    vim.cmd.checkhealth('imageui')
  else
    error(('unknown ImageUI command: %s'):format(command))
  end
end

local top = {
  'inspect',
  'refresh',
  'clear',
  'export',
  'demo',
  'reset',
  'benchmark',
  'enable',
  'disable',
  'codelens',
  'health',
}
local codelens_actions = { 'enable', 'disable', 'toggle', 'refresh', 'run', 'inspect' }
local benchmark_actions = { 'start', 'report', 'stop' }

local function complete(_, line)
  local parts = vim.split(line, '%s+', { trimempty = true })
  if #parts <= 2 then
    return top
  end
  if parts[2] == 'codelens' then
    return codelens_actions
  elseif parts[2] == 'benchmark' then
    return benchmark_actions
  end
  return {}
end

function M.setup()
  vim.api.nvim_create_user_command('ImageUI', execute, {
    nargs = '*',
    complete = complete,
    desc = 'Manage imageui.nvim overlays',
    force = true,
  })
end

M.execute = execute

return M
