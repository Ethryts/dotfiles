local h = require('tests.helpers')
local marks = require('review_comments.marks')
local review = require('review_comments')

local function setup()
  review.setup({
    notify = false,
    clipboard = { register = '"' },
    list = { open = false },
  })
end

local function stored(repo, id)
  for _, comment in ipairs(review.get_comments(repo)) do
    if comment.id == id then
      return comment
    end
  end
end

local function edit(path)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

h.run('reliability_spec', function()
  local repo = h.repo()
  local exact_path = repo .. '/exact.lua'
  h.write_file(exact_path, { 'local value = café + 1', 'return value' })
  h.git(repo, { 'add', 'exact.lua' })
  h.git(repo, { 'commit', '--quiet', '-m', 'exact range base' })
  vim.cmd('cd ' .. vim.fn.fnameescape(repo))
  edit(exact_path)
  setup()

  local prefix = 'local value = '
  local exact = assert(review.add_comment({
    line1 = 1,
    line2 = 1,
    mode = 'char',
    start_column = #prefix,
    end_column = #prefix + #'café',
    text = 'Keep this exact expression.',
  }))
  h.equal(exact.anchor.mode, 'char', 'exact comments should retain character range mode')
  h.equal(exact.anchor.original_text, 'café', 'exact comments should store only selected text')
  local exact_mark = assert(marks.get(exact.id, repo))
  local position = vim.api.nvim_buf_get_extmark_by_id(
    exact_mark.bufnr,
    marks.namespace,
    exact_mark.extmark_id,
    { details = true }
  )
  h.equal(position[1], 0, 'character extmarks should start on the selected row')
  h.equal(position[2], #prefix, 'character extmarks should start at the selected byte')
  h.equal(position[3].end_col, #prefix + #'café', 'character extmarks should end exclusively')
  h.truthy(
    review.copy():find('exact.lua:1:15-19', 1, true),
    'exports should identify exact ranges with 1-based human columns'
  )

  review._reset_for_tests()
  vim.cmd('bdelete!')
  h.write_file(
    exact_path,
    { '-- changed outside Neovim', 'local value = café + 1', 'return value' }
  )
  edit(exact_path)
  setup()
  local exact_recovered = assert(stored(repo, exact.id))
  h.equal(exact_recovered.anchor.start_line, 2, 'offline insertion should relocate an exact range')
  h.equal(
    exact_recovered.anchor.start_column,
    #prefix,
    'offline relocation should retain byte columns'
  )
  h.equal(exact_recovered.anchor.stale, false, 'a globally unique exact range should be trusted')
  vim.api.nvim_buf_set_text(0, 1, #prefix, 1, #prefix + #'café', { 'tea' })
  vim.cmd('write')
  local exact_edited = assert(stored(repo, exact.id))
  h.equal(
    exact_edited.anchor.current_text,
    'tea',
    'observed exact-range edits should remain tracked'
  )
  h.equal(
    exact_edited.anchor.end_column,
    #prefix + #'tea',
    'exact-range replacements should update their exclusive end byte'
  )
  h.equal(exact_edited.anchor.valid, true, 'an observed exact-range replacement remains valid')
  h.equal(
    exact_edited.anchor.stale,
    false,
    'an observed edit should not become an offline candidate'
  )
  assert(review.resolve_review({ root = repo, id = exact.id }))
  local resolved_exact_mark =
    assert(marks.get(exact.id, repo), 'resolving an exact-range comment must retain its extmark')
  position = vim.api.nvim_buf_get_extmark_by_id(
    resolved_exact_mark.bufnr,
    marks.namespace,
    resolved_exact_mark.extmark_id,
    { details = true }
  )
  h.equal(position[2], #prefix, 'restyling should retain the exact start byte')
  h.equal(position[3].end_col, #prefix + #'tea', 'restyling should retain the exact end byte')
  assert(review.reopen_review({ root = repo, id = exact.id }))
  h.truthy(marks.get(exact.id, repo), 'reopening an exact-range comment must retain its extmark')

  local sequential_path = repo .. '/sequential.lua'
  h.write_file(sequential_path, {
    'local before = true',
    'local first_target = 1',
    'local second_target = 2',
    'local after = true',
  })
  edit(sequential_path)
  local sequential = assert(review.add_comment({
    line1 = 2,
    line2 = 3,
    text = 'Keep this range through a sequence of edits.',
  }))
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { 'local inserted_inside = true' })
  vim.api.nvim_buf_set_lines(0, 2, 4, false, {
    'local rewritten_inside = true',
    'local rewritten_end = 3',
  })
  vim.cmd('write')
  local sequential_updated = assert(stored(repo, sequential.id))
  h.equal(sequential_updated.anchor.valid, true, 'sequential in-range edits should stay valid')
  h.equal(sequential_updated.anchor.stale, false, 'observed sequential edits should stay trusted')
  h.equal(
    sequential_updated.anchor.current_text,
    table.concat({
      'local first_target = 1',
      'local rewritten_inside = true',
      'local rewritten_end = 3',
    }, '\n'),
    'sequential edits should update the complete tracked range'
  )

  local shared_snapshot = assert(review.add_comment({
    line1 = 4,
    line2 = 4,
    text = 'Share the buffer snapshot while syncing.',
  }))
  local original_get_lines = vim.api.nvim_buf_get_lines
  local full_reads = 0
  vim.api.nvim_buf_get_lines = function(bufnr, start_row, end_row, strict)
    if bufnr == 0 then
      bufnr = vim.api.nvim_get_current_buf()
    end
    if bufnr == vim.api.nvim_get_current_buf() and start_row == 0 and end_row == -1 then
      full_reads = full_reads + 1
    end
    return original_get_lines(bufnr, start_row, end_row, strict)
  end
  local sync_ok, sync_err = pcall(function()
    local document = require('review_comments.state').get(repo)
    marks.sync_buffer(
      repo,
      document,
      vim.api.nvim_get_current_buf(),
      require('review_comments.config').options
    )
  end)
  vim.api.nvim_buf_get_lines = original_get_lines
  h.truthy(sync_ok, sync_err)
  h.equal(full_reads, 1, 'syncing several comments should snapshot a buffer only once')
  h.truthy(stored(repo, shared_snapshot.id), 'snapshot sharing must retain every synced comment')

  local setup_path = repo .. '/setup.lua'
  h.write_file(setup_path, { 'before setup', 'tracked setup text', 'after setup' })
  edit(setup_path)
  local setup_note =
    assert(review.add_comment({ line1 = 2, line2 = 2, text = 'Survive repeated setup.' }))
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'manually edited before setup' })
  setup()
  local setup_preserved = assert(stored(repo, setup_note.id))
  h.equal(
    setup_preserved.anchor.current_text,
    'manually edited before setup',
    'repeated setup should sync live extmark text before resetting marks'
  )
  h.equal(setup_preserved.anchor.stale, false, 'repeated setup must preserve live provenance')
  h.truthy(marks.get(setup_note.id, repo), 'repeated setup should restore the trusted mark')

  local external_path = repo .. '/external.lua'
  h.write_file(external_path, { 'one', 'two', 'old external target', 'four', 'five' })
  edit(external_path)
  local external =
    assert(review.add_comment({ line1 = 3, line2 = 3, text = 'Notice external changes.' }))
  h.write_file(external_path, { 'one', 'two', 'new external target', 'four', 'five' })
  review.status(repo)
  h.equal(
    vim.api.nvim_buf_get_lines(0, 2, 3, false)[1],
    'old external target',
    'anchor checks should not unexpectedly reload the user buffer or discard its undo state'
  )
  local external_reconciled = assert(stored(repo, external.id))
  h.equal(external_reconciled.anchor.valid, true, 'unique external context should stay navigable')
  h.equal(external_reconciled.anchor.stale, true, 'changed external text should need confirmation')
  h.equal(
    external_reconciled.anchor.current_text,
    'old external target',
    'external candidates must retain their last trusted text'
  )

  local ambiguous_path = repo .. '/ambiguous.lua'
  h.write_file(ambiguous_path, { 'target()', 'same context' })
  edit(ambiguous_path)
  local ambiguous =
    assert(review.add_comment({ line1 = 1, line2 = 1, text = 'This must not drift.' }))
  review._reset_for_tests()
  vim.cmd('bdelete!')
  h.write_file(ambiguous_path, { 'target()', 'same context', 'target()', 'same context' })
  edit(ambiguous_path)
  setup()
  local broken = assert(stored(repo, ambiguous.id))
  h.equal(broken.anchor.valid, false, 'globally ambiguous text should become orphaned')
  h.equal(broken.anchor.stale, true, 'an orphan should remain explicitly stale')
  h.truthy(broken.anchor.failure_reason, 'an orphan should explain why recovery failed')
  local broken_mark = assert(marks.get(ambiguous.id, repo))
  position = vim.api.nvim_buf_get_extmark_by_id(
    broken_mark.bufnr,
    marks.namespace,
    broken_mark.extmark_id,
    { details = true }
  )
  h.equal(
    vim.trim(position[3].sign_text),
    '!',
    'an orphan in an existing file should get an error sign'
  )
  h.equal(review.list(), 'quickfix', 'broken comments should remain inspectable in quickfix')
  local qf = vim.fn.getqflist({ items = 1 })
  local broken_item
  for _, item in ipairs(qf.items) do
    if item.user_data.review_comment_id == ambiguous.id then
      broken_item = item
    end
  end
  h.truthy(broken_item, 'the orphan should remain visible in the review list')
  h.equal(broken_item.valid, 0, 'an orphan must never have a native quickfix target')
  h.equal(broken_item.bufnr, 0, 'an orphan must not retain a stale buffer target')
  h.truthy(review.copy():find('[orphaned location', 1, true), 'exports should disclose orphans')

  local old_path = repo .. '/old-name.lua'
  local new_path = repo .. '/new-name.lua'
  h.write_file(old_path, {
    'local before = true',
    'local renamed_target = 1',
    'local after = true',
    'return renamed_target',
  })
  h.git(repo, { 'add', 'old-name.lua' })
  h.git(repo, { 'commit', '--quiet', '-m', 'rename base' })
  edit(old_path)
  local renamed = assert(review.add_comment({ line1 = 2, line2 = 2, text = 'Follow this rename.' }))
  review._reset_for_tests()
  vim.cmd('bdelete!')
  h.git(repo, { 'mv', 'old-name.lua', 'new-name.lua' })
  edit(new_path)
  setup()
  local renamed_recovered = assert(stored(repo, renamed.id))
  h.equal(renamed_recovered.file, 'new-name.lua', 'Git should recover a renamed review file')
  h.equal(renamed_recovered.anchor.valid, true, 'a renamed exact range should remain valid')
  h.equal(renamed_recovered.anchor.stale, false, 'an exact range after a Git rename is trusted')
  h.equal(
    renamed_recovered.anchor.file_anchor.history[#renamed_recovered.anchor.file_anchor.history].method,
    'git_rename',
    'path recovery should retain an audit trail'
  )

  local old_candidate = repo .. '/old-candidate.lua'
  local new_candidate = repo .. '/new-candidate.lua'
  h.write_file(old_candidate, {
    'local unique_before = true',
    'local candidate_target = 1',
    'local unique_after = true',
    'local padding = true',
    'return candidate_target',
  })
  h.git(repo, { 'add', '--all' })
  h.git(repo, { 'commit', '--quiet', '-m', 'candidate rename base' })
  edit(old_candidate)
  local candidate = assert(review.add_comment({
    line1 = 2,
    line2 = 2,
    text = 'Track this, but require confirmation if its text changes.',
  }))
  review._reset_for_tests()
  vim.cmd('bdelete!')
  h.git(repo, { 'mv', 'old-candidate.lua', 'new-candidate.lua' })
  h.write_file(new_candidate, {
    'local unique_before = true',
    'local candidate_target = configured',
    'local unique_after = true',
    'local padding = true',
    'return candidate_target',
  })
  edit(new_candidate)
  setup()
  local candidate_recovered = assert(stored(repo, candidate.id))
  h.equal(candidate_recovered.file, 'new-candidate.lua', 'Git should recover rename-plus-edit')
  h.equal(candidate_recovered.anchor.valid, true, 'unique context should retain a candidate')
  h.equal(candidate_recovered.anchor.stale, true, 'changed text must remain untrusted')
  local candidate_mark = assert(marks.get(candidate.id, repo))
  position = vim.api.nvim_buf_get_extmark_by_id(
    candidate_mark.bufnr,
    marks.namespace,
    candidate_mark.extmark_id,
    { details = true }
  )
  h.equal(vim.trim(position[3].sign_text), '?', 'a context candidate should get a warning sign')
  h.equal(
    candidate_recovered.anchor.current_text,
    'local candidate_target = 1',
    'candidate recovery must preserve the last trusted text'
  )

  local manual_old_path = repo .. '/manual-old.lua'
  local manual_new_path = repo .. '/manual-new.lua'
  h.write_file(manual_old_path, {
    'local before_manual = true',
    'local manual_target = 1',
    'local after_manual = true',
  })
  h.git(repo, { 'add', '--all' })
  h.git(repo, { 'commit', '--quiet', '-m', 'manual rename base' })
  edit(manual_old_path)
  local manual_bufnr = vim.api.nvim_get_current_buf()
  local manual =
    assert(review.add_comment({ line1 = 2, line2 = 2, text = 'Preserve unsaved manual work.' }))
  vim.api.nvim_buf_set_lines(manual_bufnr, 0, 0, false, { '-- unsaved manual change' })
  h.git(repo, { 'mv', 'manual-old.lua', 'manual-new.lua' })

  review._restore_buffer(manual_bufnr)
  local deferred = assert(stored(repo, manual.id))
  h.equal(
    deferred.file,
    'manual-old.lua',
    'an external rename must wait while the old buffer has unsaved work'
  )
  h.truthy(
    marks.get(manual.id, repo),
    'deferring an external rename must retain the extmark in the modified buffer'
  )

  vim.cmd('bdelete!')
  edit(manual_new_path)
  review._restore_buffer(vim.api.nvim_get_current_buf())
  local resumed = assert(stored(repo, manual.id))
  h.equal(
    resumed.file,
    'manual-new.lua',
    'rename recovery should resume after discarding the buffer'
  )
  h.truthy(marks.get(manual.id, repo), 'the recovered destination should regain the extmark')

  local destination_old_path = repo .. '/destination-old.lua'
  local destination_new_path = repo .. '/destination-new.lua'
  h.write_file(destination_old_path, {
    'local before_destination = true',
    'local destination_target = 1',
    'local after_destination = true',
  })
  h.git(repo, { 'add', '--all' })
  h.git(repo, { 'commit', '--quiet', '-m', 'destination rename base' })
  edit(destination_old_path)
  local destination =
    assert(review.add_comment({ line1 = 2, line2 = 2, text = 'Wait for destination edits.' }))
  review._reset_for_tests()
  vim.cmd('bdelete!')
  h.git(repo, { 'mv', 'destination-old.lua', 'destination-new.lua' })
  edit(destination_new_path)
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { '-- unsaved destination change' })
  setup()

  local destination_deferred = assert(stored(repo, destination.id))
  h.equal(
    destination_deferred.file,
    'destination-old.lua',
    'rename recovery must wait while the destination buffer has unsaved work'
  )
  h.equal(
    destination_deferred.anchor.valid,
    true,
    'a modified rename destination must not turn a trusted note into an orphan'
  )
  h.equal(
    #destination_deferred.anchor.file_anchor.history,
    0,
    'a deferred destination must not record a path change'
  )

  vim.cmd('bdelete!')
  edit(destination_new_path)
  review._restore_buffer(vim.api.nvim_get_current_buf())
  local destination_resumed = assert(stored(repo, destination.id))
  h.equal(
    destination_resumed.file,
    'destination-new.lua',
    'rename recovery should resume after destination edits are discarded'
  )
  h.truthy(
    marks.get(destination.id, repo),
    'the stable rename destination should receive the recovered extmark'
  )

  local git_module = require('review_comments.git')
  local original_files = git_module.files
  local passive_scans = 0
  git_module.files = function(...)
    passive_scans = passive_scans + 1
    return original_files(...)
  end
  review._restore_buffer(vim.api.nvim_get_current_buf())
  review._restore_buffer(vim.api.nvim_get_current_buf())
  git_module.files = original_files
  h.equal(
    passive_scans,
    0,
    'passive buffer restoration must not run repository-wide missing-file searches'
  )

  review._reset_for_tests()
  local session_repo = h.repo()
  local session_path = session_repo .. '/session.lua'
  h.write_file(session_path, { 'return 1' })
  h.git(session_repo, { 'add', 'session.lua' })
  h.git(session_repo, { 'commit', '--quiet', '-m', 'first' })
  local base = h.git(session_repo, { 'rev-parse', 'HEAD' })
  h.write_file(session_path, { 'return 2' })
  h.git(session_repo, { 'add', 'session.lua' })
  h.git(session_repo, { 'commit', '--quiet', '-m', 'second' })
  vim.cmd('cd ' .. vim.fn.fnameescape(session_repo))
  edit(session_path)
  setup()
  local old_note = assert(review.add_comment({ line1 = 1, line2 = 1, text = 'Existing session.' }))
  local old_session = assert(review.get_session(session_repo))
  local invalid = review.start_session({ root = session_repo, base_ref = '--help', force = true })
  h.equal(invalid, nil, 'an invalid base ref should not replace the current session')
  h.equal(review.get_session(session_repo).id, old_session.id, 'invalid refs must be atomic')
  local refused = review.start_session({ root = session_repo, base_ref = 'HEAD~1' })
  h.equal(refused, nil, 'a non-empty session should require an explicit archive')
  h.truthy(stored(session_repo, old_note.id), 'a refused session start must retain comments')
  local started, archive = review.start_session({
    root = session_repo,
    base_ref = 'HEAD~1',
    force = true,
  })
  h.truthy(started and archive, 'forced session start should archive and replace atomically')
  h.equal(started.scope.base.commit, base, 'the requested base should be frozen to a commit ID')
  h.equal(started.scope.base.requested, 'HEAD~1', 'the human ref should remain visible')
  h.equal(#review.get_comments(session_repo), 0, 'a new scoped session should start empty')
  h.truthy((vim.uv or vim.loop).fs_stat(archive), 'the prior session should be archived')

  local opened
  review.setup({
    notify = false,
    clipboard = { register = '"' },
    list = { open = false },
    session = {
      open_on_start = false,
      open_diff = function(ctx)
        opened = ctx
        return true
      end,
    },
  })
  h.equal(
    review.open_diff({ root = session_repo }),
    true,
    'ReviewDiff should use the configured adapter'
  )
  h.equal(opened.base_commit, base, 'the adapter should receive the immutable base')

  local crossed_session = assert(review.add_comment({ line1 = 1, line2 = 1 }))
  local crossed_from = review.get_session(session_repo).id
  local replacement = assert(review.start_session({ root = session_repo, base_ref = 'HEAD' }))
  h.truthy(replacement.id ~= crossed_from, 'the test should replace the empty review session')
  vim.api.nvim_buf_set_lines(crossed_session.bufnr, 0, -1, false, { 'Belongs to old session.' })
  assert(crossed_session:submit())
  h.truthy(
    vim.wait(100, function()
      local editor_status = crossed_session:status()
      return editor_status and editor_status.last_error ~= nil
    end),
    'a draft opened before a session transition should be refused'
  )
  h.truthy(
    crossed_session:status().last_error:find('session changed', 1, true),
    'the stale add editor should explain the session boundary'
  )
  h.equal(
    #review.get_comments(session_repo),
    0,
    'an old-session draft must not enter the new session'
  )
  assert(crossed_session:cancel())
  edit(session_path)

  local draft = assert(review.add_comment({ line1 = 1, line2 = 1 }))
  vim.api.nvim_buf_set_lines(draft.bufnr, 0, -1, false, {
    'Use the configured value.',
    '',
    'Also preserve the fallback behavior.',
  })
  assert(draft:submit())
  h.truthy(
    vim.wait(100, function()
      return not vim.api.nvim_buf_is_valid(draft.bufnr)
    end),
    'a saved multiline draft should close'
  )
  local comments = review.get_comments(session_repo)
  h.equal(
    comments[1].comment,
    'Use the configured value.\n\nAlso preserve the fallback behavior.',
    'ReviewComment should persist multiline text'
  )
  local edit_draft = assert(review.edit_comment({ root = session_repo, id = comments[1].id }))
  vim.api.nvim_buf_set_lines(
    edit_draft.bufnr,
    0,
    -1,
    false,
    { 'Short first line.', 'More detail.' }
  )
  assert(edit_draft:submit())
  h.truthy(
    vim.wait(100, function()
      return not vim.api.nvim_buf_is_valid(edit_draft.bufnr)
    end),
    'a saved multiline edit should close'
  )
  h.equal(
    stored(session_repo, comments[1].id).comment,
    'Short first line.\nMore detail.',
    'ReviewEdit should persist multiline text'
  )

  local concurrent = assert(review.edit_comment({ root = session_repo, id = comments[1].id }))
  vim.api.nvim_buf_set_lines(
    concurrent.bufnr,
    0,
    -1,
    false,
    { 'This stale draft must not overwrite external work.' }
  )
  local config = require('review_comments.config').options
  local review_storage = require('review_comments.storage')
  local external = assert(review_storage.load(session_repo, config))
  external.document.comments[1].comment = 'Changed by another Neovim process.'
  external.document.comments[1].updated_at = '2099-01-01T00:00:00Z'
  assert(review_storage.save(session_repo, external.document, config, external.token))

  assert(concurrent:submit())
  h.truthy(
    vim.wait(100, function()
      local status = concurrent:status()
      return status and status.pending == false and status.last_error ~= nil
    end),
    'a stale multiline edit should remain open with an error'
  )
  h.truthy(
    concurrent:status().last_error:find('changed while its editor was open', 1, true),
    'the stale editor should explain the optimistic concurrency conflict'
  )
  h.equal(
    assert(review_storage.load(session_repo, config)).document.comments[1].comment,
    'Changed by another Neovim process.',
    'a stale multiline draft must not overwrite a newer durable comment'
  )
  assert(concurrent:cancel())

  vim.fn.delete(repo, 'rf')
  vim.fn.delete(session_repo, 'rf')
end)
