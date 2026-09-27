local h = require('tests.helpers')
local review = require('review_comments')
local marks = require('review_comments.marks')

h.run('relocation_spec', function()
  local repo = h.repo()
  local setup_opts = { notify = false, clipboard = { register = '"' }, list = { open = false } }
  local function stored_comment(id)
    for _, item in ipairs(review.get_comments(repo)) do
      if item.id == id then
        return item
      end
    end
  end

  local source = repo .. '/sample.lua'
  h.write_file(source, {
    'local before = true',
    'local target = 41',
    'local after = true',
    'return target',
  })
  vim.cmd('cd ' .. vim.fn.fnameescape(repo))
  vim.cmd('edit ' .. vim.fn.fnameescape(source))
  review.setup(setup_opts)
  local comment = assert(review.add_comment({ line1 = 2, line2 = 2, text = 'Fix this value.' }))

  review._reset_for_tests()
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { '-- inserted while the plugin was closed' })
  vim.cmd('write')
  review.setup(setup_opts)
  local relocated = stored_comment(comment.id)
  h.equal(relocated.anchor.start_line, 3, 'unique exact text should relocate after restart')
  h.equal(relocated.anchor.stale, false, 'exact relocation should remain trusted')
  h.truthy(marks.get(comment.id, repo), 'exactly relocated comments should regain extmarks')

  review._reset_for_tests()
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'local before = false' })
  vim.cmd('write')
  review.setup(setup_opts)
  relocated = stored_comment(comment.id)
  h.equal(
    relocated.anchor.current_context_before,
    { '-- inserted while the plugin was closed', 'local before = false' },
    'restoration should refresh context even when target text and line are unchanged'
  )
  h.equal(
    require('review_comments.state').is_dirty(repo),
    true,
    'a context-only restoration change should mark the session dirty'
  )
  assert(review.copy())
  local current_path = require('review_comments.storage').paths(
    repo,
    require('review_comments.config').options
  ).current
  local persisted = h.read_json(current_path)
  h.equal(
    persisted.comments[1].anchor.current_context_before,
    relocated.anchor.current_context_before,
    'context-only restoration changes should be persisted'
  )

  review._reset_for_tests()
  vim.api.nvim_buf_set_lines(0, 2, 3, false, { 'local target = configured_value' })
  vim.cmd('write')
  review.setup(setup_opts)
  relocated = stored_comment(comment.id)
  h.equal(relocated.anchor.start_line, 3, 'unique surrounding context should retain a candidate')
  h.equal(relocated.anchor.stale, true, 'changed target text should require explicit confirmation')
  h.equal(
    relocated.anchor.valid,
    true,
    'a high-confidence context candidate should remain navigable'
  )
  h.equal(
    relocated.anchor.current_text,
    'local target = 41',
    'context relocation must not accept changed text as trusted'
  )

  assert(review.relocate_comment({ root = repo, id = comment.id, bufnr = 0, line1 = 3, line2 = 3 }))
  local trusted_text = stored_comment(comment.id).anchor.current_text
  vim.api.nvim_buf_set_lines(0, 2, 3, false, {})
  vim.cmd('write')
  local deleted = stored_comment(comment.id)
  h.equal(deleted.anchor.valid, false, 'deleting a reviewed range should orphan its anchor')
  h.equal(deleted.anchor.stale, true, 'deleting a reviewed range should make it stale')
  vim.api.nvim_buf_set_lines(0, 2, 2, false, { trusted_text })
  vim.cmd('write')
  local recovered = stored_comment(comment.id)
  h.equal(recovered.anchor.valid, true, 'exactly reinserted trusted text should recover the anchor')
  h.equal(recovered.anchor.stale, false, 'exactly reinserted trusted text should clear stale state')

  local left_cross_path = repo .. '/left-cross.lua'
  h.write_file(left_cross_path, {
    'outside',
    'before',
    'target a',
    'target b',
    'after',
  })
  vim.cmd('edit ' .. vim.fn.fnameescape(left_cross_path))
  local left_cross =
    assert(review.add_comment({ line1 = 3, line2 = 4, text = 'Do not absorb the leading edit.' }))
  vim.api.nvim_buf_set_lines(0, 1, 3, false, { 'before changed', 'target a changed' })
  vim.cmd('write')
  local left_cross_stored = stored_comment(left_cross.id)
  h.equal(left_cross_stored.anchor.valid, false, 'a left-edge crossing edit is ambiguous')
  h.equal(
    left_cross_stored.anchor.start_line,
    3,
    'a left-edge crossing edit must not widen the review into unrelated leading lines'
  )

  local right_cross_path = repo .. '/right-cross.lua'
  h.write_file(right_cross_path, {
    'before',
    'target a',
    'target b',
    'after',
    'outside',
  })
  vim.cmd('edit ' .. vim.fn.fnameescape(right_cross_path))
  local right_cross =
    assert(review.add_comment({ line1 = 2, line2 = 3, text = 'Do not absorb the trailing edit.' }))
  vim.api.nvim_buf_set_lines(0, 2, 4, false, { 'target b changed', 'after changed' })
  vim.cmd('write')
  local right_cross_stored = stored_comment(right_cross.id)
  h.equal(right_cross_stored.anchor.valid, false, 'a right-edge crossing edit is ambiguous')
  h.equal(
    right_cross_stored.anchor.end_line,
    3,
    'a right-edge crossing edit must not widen the review into unrelated trailing lines'
  )

  local reset_one_path = repo .. '/reset-one.lua'
  local reset_two_path = repo .. '/reset-two.lua'
  h.write_file(reset_one_path, { 'first tracked buffer' })
  h.write_file(reset_two_path, { 'second tracked buffer' })
  vim.cmd('edit ' .. vim.fn.fnameescape(reset_one_path))
  local reset_one_buf = vim.api.nvim_get_current_buf()
  local reset_one = assert(review.add_comment({ line1 = 1, line2 = 1, text = 'Track one.' }))
  vim.cmd('edit ' .. vim.fn.fnameescape(reset_two_path))
  local reset_two_buf = vim.api.nvim_get_current_buf()
  local reset_two = assert(review.add_comment({ line1 = 1, line2 = 1, text = 'Track two.' }))
  review.setup(setup_opts)
  review.setup(setup_opts)
  h.truthy(marks.get(reset_one.id, repo), 'repeated reset should restore the first buffer mark')
  h.truthy(marks.get(reset_two.id, repo), 'repeated reset should restore the second buffer mark')
  vim.api.nvim_set_current_buf(reset_one_buf)
  vim.api.nvim_buf_set_lines(reset_one_buf, 0, 0, false, { 'inserted above one' })
  vim.cmd('write')
  vim.api.nvim_set_current_buf(reset_two_buf)
  vim.api.nvim_buf_set_lines(reset_two_buf, 0, 0, false, { 'inserted above two' })
  vim.cmd('write')
  h.equal(
    stored_comment(reset_one.id).anchor.start_line,
    2,
    'first reset buffer should track edits'
  )
  h.equal(
    stored_comment(reset_two.id).anchor.start_line,
    2,
    'second reset buffer should track edits'
  )

  local snapshot = require('review_comments.model').create_comment({
    file = 'sample.lua',
    view = 'left',
    comment = 'Historical-side note.',
    start_line = 1,
    end_line = 1,
    selected_lines = { '-- inserted while the plugin was closed' },
    context_before = {},
    context_after = {},
  })
  local mark, source_err = marks.attach(
    repo,
    snapshot,
    vim.api.nvim_get_current_buf(),
    { root = repo, file = 'sample.lua', difftool = false },
    require('review_comments.config').options
  )
  h.equal(mark, nil, 'snapshot comments must not attach to the working tree')
  h.truthy(source_err:find('Historical', 1, true), 'source mismatch should be explicit')

  local mismatched_snapshot = require('review_comments.model').create_comment({
    file = 'sample.lua',
    source = {
      kind = 'snapshot',
      side = 'left',
      content_sha256 = vim.fn.sha256('snapshot a'),
    },
    comment = 'Snapshot-specific note.',
    start_line = 1,
    end_line = 1,
    selected_lines = { 'second tracked buffer' },
    context_before = {},
    context_after = {},
  })
  local mismatched_mark, mismatch_err =
    marks.attach(repo, mismatched_snapshot, vim.api.nvim_get_current_buf(), {
      root = repo,
      file = 'sample.lua',
      difftool = true,
      view = 'left',
      source = {
        kind = 'snapshot',
        side = 'left',
        content_sha256 = vim.fn.sha256('snapshot b'),
      },
    }, require('review_comments.config').options)
  h.equal(mismatched_mark, nil, 'same-side snapshots with different identities must not attach')
  h.truthy(mismatch_err:find('content', 1, true), 'snapshot identity mismatch should be explicit')

  local right_snapshot = vim.fn.tempname() .. '-right.lua'
  h.write_file(right_snapshot, { 'local historical = true' })
  vim.fn.setqflist({}, ' ', {
    title = 'DiffTool',
    items = {
      {
        filename = right_snapshot,
        user_data = {
          diff = true,
          rel = 'sample.lua',
          left = vim.fn.tempname() .. '-left.lua',
          right = right_snapshot,
        },
      },
    },
  })
  vim.cmd('edit ' .. vim.fn.fnameescape(right_snapshot))
  local snapshot_target = assert(
    require('review_comments.util').resolve_target(0, require('review_comments.config').options)
  )
  h.equal(snapshot_target.source.kind, 'snapshot', 'external DiffTool right should be a snapshot')
  h.equal(snapshot_target.source.side, 'right', 'external DiffTool snapshot should retain its side')

  vim.fn.delete(right_snapshot)
  vim.fn.delete(repo, 'rf')
end)
