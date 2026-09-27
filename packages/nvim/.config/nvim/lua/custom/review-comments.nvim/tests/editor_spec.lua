local h = require('tests.helpers')
local editor = require('review_comments.editor')

local function set_text(bufnr, lines)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

local function write(bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd('write')
  end)
end

h.run('editor_spec', function()
  local submitted = {}
  local first = assert(editor.open({
    title = 'Edit review comment',
    initial_text = 'first line\nsecond line',
    close_on_submit = false,
    start_insert = false,
    notify = false,
    on_submit = function(text)
      submitted[#submitted + 1] = text
      return true
    end,
  }))
  h.equal(vim.bo[first.bufnr].buftype, 'acwrite', 'the draft should use an acwrite buffer')
  h.equal(vim.bo[first.bufnr].filetype, 'markdown', 'review drafts should use Markdown')
  h.equal(
    vim.api.nvim_buf_get_lines(first.bufnr, 0, -1, false),
    { 'first line', 'second line' },
    'initial multiline text should be preserved'
  )
  h.equal(vim.bo[first.bufnr].modified, false, 'loading initial text should not dirty the draft')

  set_text(first.bufnr, { 'updated', '', 'with details' })
  write(first.bufnr)
  h.equal(submitted, { 'updated\n\nwith details' }, ':write should submit the complete draft')
  h.equal(vim.bo[first.bufnr].modified, false, 'a successful write should mark the draft clean')
  h.equal(first:status().last_committed_text, submitted[1], 'status should expose the saved draft')
  assert(first:cancel())

  local successful_cancelled = false
  local successful = assert(editor.open({
    initial_text = 'close after save',
    start_insert = false,
    notify = false,
    on_submit = function()
      return true
    end,
    on_cancel = function()
      successful_cancelled = true
    end,
  }))
  write(successful.bufnr)
  h.truthy(
    vim.wait(100, function()
      return not vim.api.nvim_buf_is_valid(successful.bufnr)
    end),
    'a successful submission should close an unchanged editor'
  )
  h.equal(successful_cancelled, false, 'successful closure must not be reported as cancellation')

  local failures = 0
  local failed = assert(editor.open({
    initial_text = 'keep this text',
    close_on_submit = false,
    start_insert = false,
    notify = false,
    on_submit = function()
      failures = failures + 1
      return false, 'backend rejected the draft'
    end,
  }))
  write(failed.bufnr)
  h.equal(failures, 1, 'a failed submission should run once')
  h.equal(vim.bo[failed.bufnr].modified, true, 'a failed submission must remain modified')
  h.equal(
    vim.api.nvim_buf_get_lines(failed.bufnr, 0, -1, false),
    { 'keep this text' },
    'a failed submission must preserve its text'
  )
  h.equal(failed:status().last_error, 'backend rejected the draft', 'failure should be inspectable')
  assert(failed:cancel())

  local finish_first
  local async_calls = 0
  local async = assert(editor.open({
    initial_text = 'draft one',
    close_on_submit = true,
    start_insert = false,
    notify = false,
    on_submit = function(_, finish)
      async_calls = async_calls + 1
      finish_first = finish
    end,
  }))
  write(async.bufnr)
  write(async.bufnr)
  h.equal(async_calls, 1, 'a pending write should suppress duplicate submissions')
  h.equal(async:status().pending, true, 'an unfinished callback should remain pending')

  set_text(async.bufnr, { 'draft two' })
  finish_first(true)
  h.truthy(vim.api.nvim_buf_is_valid(async.bufnr), 'saving an old draft must not close newer edits')
  h.equal(vim.bo[async.bufnr].modified, true, 'newer edits must remain visibly unsaved')
  h.equal(
    async:status().last_committed_text,
    'draft one',
    'the completed attempt should retain the exact committed text'
  )
  finish_first(false, 'stale duplicate completion')
  h.equal(async:status().last_error, nil, 'a duplicate completion must not alter editor state')

  local finish_second
  local second_context
  async = assert(editor.open({
    initial_text = 'pending cancellation',
    start_insert = false,
    notify = false,
    on_submit = function(_, finish, context)
      finish_second = finish
      second_context = context
    end,
  }))
  write(async.bufnr)
  h.equal(second_context.is_current(), true, 'a pending callback context should be current')
  local cancelled, cancel_err = async:cancel()
  h.equal(cancelled, false, 'ordinary cancellation should refuse while a save is pending')
  h.truthy(
    cancel_err:find('save is in progress', 1, true),
    'pending cancellation should explain itself'
  )
  local stale_context = async:status()
  h.equal(stale_context.pending, true, 'refused cancellation should retain the editor')
  assert(async:cancel({ force = true }))
  h.equal(
    second_context.is_current(),
    false,
    'forced cancellation should stale its callback context'
  )
  h.equal(finish_second(true), true, 'the async owner may still finish after forced cancellation')
  h.equal(editor.status(async.bufnr), nil, 'stale completion must not resurrect a cancelled editor')

  local cancel_context
  local cancellable = assert(editor.open({
    initial_text = 'discard me',
    start_insert = false,
    notify = false,
    on_submit = function()
      return true
    end,
    on_cancel = function(context)
      cancel_context = context
    end,
  }))
  set_text(cancellable.bufnr, { 'discard this changed draft' })
  assert(cancellable:cancel())
  h.equal(cancel_context.reason, 'cancelled', 'explicit cancellation should identify its reason')
  h.equal(
    cancel_context.text,
    'discard this changed draft',
    'cancellation should expose the discarded draft to the caller'
  )

  local empty_calls = 0
  local empty = assert(editor.open({
    initial_text = '',
    close_on_submit = false,
    start_insert = false,
    notify = false,
    on_submit = function()
      empty_calls = empty_calls + 1
      return true
    end,
  }))
  write(empty.bufnr)
  h.equal(empty_calls, 0, 'blank comments should fail validation before submission')
  h.equal(vim.bo[empty.bufnr].modified, true, 'a rejected blank draft should remain open')
  assert(empty:cancel())

  local quit_context
  local quit = assert(editor.open({
    initial_text = 'close normally',
    start_insert = false,
    notify = false,
    on_submit = function()
      return true
    end,
    on_cancel = function(context)
      quit_context = context
    end,
  }))
  vim.api.nvim_win_call(vim.fn.bufwinid(quit.bufnr), function()
    vim.cmd('quit')
  end)
  h.equal(
    vim.api.nvim_buf_is_valid(quit.bufnr),
    false,
    ':q should wipe an unmodified review editor'
  )
  h.equal(editor.status(quit.bufnr), nil, ':q must not leave an active unloaded editor')
  h.equal(quit_context.reason, 'buffer_wiped', ':q should report a cancelled draft')

  local forced_context
  local forced = assert(editor.open({
    initial_text = 'discard with quit',
    start_insert = false,
    notify = false,
    on_submit = function()
      return true
    end,
    on_cancel = function(context)
      forced_context = context
    end,
  }))
  set_text(forced.bufnr, { 'discarded by quit bang' })
  vim.api.nvim_win_call(vim.fn.bufwinid(forced.bufnr), function()
    vim.cmd('quit!')
  end)
  h.equal(
    vim.api.nvim_buf_is_valid(forced.bufnr),
    false,
    ':q! should wipe a modified review editor'
  )
  h.equal(editor.status(forced.bufnr), nil, ':q! must not leave an active unloaded editor')
  h.equal(forced_context.text, 'discarded by quit bang', ':q! should expose the discarded draft')

  editor.reset()
  h.equal(editor.active(), {}, 'reset should remove every editor buffer')
end)
