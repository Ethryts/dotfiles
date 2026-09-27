local h = require('tests.helpers')
local review = require('review_comments')
local util = require('review_comments.util')

h.run('clipboard_spec', function()
  local repo = h.repo()
  local source = repo .. '/sample.lua'
  h.write_file(source, { 'return 1' })
  vim.cmd('cd ' .. vim.fn.fnameescape(repo))
  vim.cmd('edit ' .. vim.fn.fnameescape(source))
  review.setup({ notify = false, clipboard = { register = '"' }, list = { open = false } })
  assert(review.add_comment({ line1 = 1, line2 = 1, text = 'Use the configured value.' }))

  local exported_events = 0
  vim.api.nvim_create_autocmd('User', {
    pattern = 'ReviewCommentsExported',
    callback = function()
      exported_events = exported_events + 1
    end,
  })

  vim.fn.setreg('"', 'sentinel')
  local original_available = util.clipboard_available
  util.clipboard_available = function()
    return false, 'No clipboard provider is available'
  end
  local unavailable = review.copy()
  util.clipboard_available = original_available
  h.equal(unavailable, nil, 'copy must fail when the configured clipboard is unavailable')
  h.equal(vim.fn.getreg('"'), 'sentinel', 'a failed copy must not report data in another register')
  h.equal(exported_events, 0, 'a failed clipboard write must not emit an exported event')

  local copied = assert(review.copy())
  h.equal(vim.fn.getreg('"'), copied, 'ordinary Neovim registers should remain supported')
  h.equal(exported_events, 1, 'a successful copy should emit exactly one exported event')

  local provider_ok, provider_err = original_available('+')
  local executable = vim.fn['provider#clipboard#Executable']()
  if executable == '' then
    h.equal(provider_ok, false, 'the + register requires a real clipboard provider')
    h.truthy(
      type(provider_err) == 'string' and provider_err ~= '',
      'provider failure should explain itself'
    )
  end

  local health = require('review-comments.health')
  h.truthy(type(health.check) == 'function', 'the documented checkhealth module should load')
  vim.cmd('checkhealth review-comments')
  local report = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  h.equal(
    report:find('No healthcheck found', 1, true),
    nil,
    ':checkhealth review-comments should resolve the plugin health module'
  )
  h.truthy(report:find('review-comments.nvim', 1, true), 'the plugin health report should run')

  local original_path = vim.env.PATH
  vim.env.PATH = '/definitely-missing-review-comments-path'
  local missing_git_ok, missing_git_err = pcall(health.check)
  vim.env.PATH = original_path
  h.truthy(
    missing_git_ok,
    'health should report a missing Git executable without crashing: ' .. tostring(missing_git_err)
  )

  vim.fn.delete(repo, 'rf')
end)
