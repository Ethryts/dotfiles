local h = require('tests.helpers')
local review = require('review_comments')
local marks = require('review_comments.marks')
local storage = require('review_comments.storage')

local function qf(id)
  return vim.fn.getqflist({ id = id or 0, idx = 0, items = 1, context = 1, title = 1 })
end

h.run('workflow_spec', function()
  local repo = h.repo()
  local source = repo .. '/sample.lua'
  h.write_file(source, {
    'local first = 1',
    'local second = 2',
    'return first + second',
  })
  vim.cmd('cd ' .. vim.fn.fnameescape(repo))
  vim.cmd('edit ' .. vim.fn.fnameescape(source))
  review.setup({ notify = false, clipboard = { register = '"' }, list = { open = false } })

  vim.fn.setqflist({}, ' ', {
    title = 'Foreign diagnostics',
    items = { { filename = source, lnum = 1, text = 'foreign' } },
    context = { owner = 'foreign' },
  })
  local foreign = qf()
  local first =
    assert(review.add_comment({ line1 = 1, line2 = 1, text = 'Change the first value.' }))
  h.equal(qf().id, foreign.id, 'adding the first note must not create or steal quickfix')

  h.equal(review.list(), 'quickfix', 'ReviewList should establish the projection explicitly')
  local projection = qf()
  h.equal(#projection.items, 1, 'projection should contain the first note')

  local second =
    assert(review.add_comment({ line1 = 2, line2 = 2, text = 'Change the second value.' }))
  h.equal(qf().id, projection.id, 'adding a note should refresh the existing projection')
  h.equal(#qf().items, 2, 'the new note should appear without another ReviewList command')

  vim.fn.setqflist({}, ' ', {
    title = 'Later diagnostics',
    items = { { filename = source, lnum = 3, text = 'later foreign' } },
    context = { owner = 'later-foreign' },
  })
  local later = qf()
  assert(
    review.edit_comment({ root = repo, id = first.id, text = 'Use the configured first value.' })
  )
  h.equal(qf().id, later.id, 'editing must not activate a hidden review projection')
  h.equal(qf().items, later.items, 'editing must not mutate a foreign current list')
  local hidden = qf(projection.id)
  h.truthy(
    hidden.items[1].text:find('configured first', 1, true),
    'the hidden projection should refresh by list ID'
  )

  assert(review.resolve_review({ root = repo, id = first.id }))
  hidden = qf(projection.id)
  h.equal(#hidden.items, 1, 'resolved comments should leave the active projection')
  h.equal(hidden.items[1].user_data.review_comment_id, second.id, 'the active note should remain')
  h.equal(
    review.copy():find('configured first', 1, true),
    nil,
    'normal export should omit resolved comments'
  )
  h.truthy(
    review.copy({ include_resolved = true }):find('configured first', 1, true),
    'bang-style export should include resolved comments'
  )
  local resolved_mark = assert(marks.get(first.id, repo))
  local resolved_position = vim.api.nvim_buf_get_extmark_by_id(
    resolved_mark.bufnr,
    marks.namespace,
    resolved_mark.extmark_id,
    { details = true }
  )
  h.equal(
    resolved_position[3].hl_group,
    'ReviewCommentResolved',
    'resolved comments should retain subdued extmarks'
  )

  assert(review.reopen_review({ root = repo, id = first.id }))
  h.equal(#qf(projection.id).items, 2, 'reopening should restore the active projected row')
  assert(review.delete_comment({ root = repo, id = second.id, force = true }))
  h.equal(#qf(projection.id).items, 1, 'deletion should refresh the hidden projection')
  h.equal(marks.get(second.id, repo), nil, 'deletion should remove the extmark')

  local original_text = first.anchor.original_text
  assert(review.relocate_comment({ root = repo, id = first.id, bufnr = 0, line1 = 3, line2 = 3 }))
  local relocated = review.get_comments(repo)[1]
  h.equal(relocated.id, first.id, 'relocation must preserve the persistent ID')
  h.equal(relocated.anchor.original_text, original_text, 'relocation must preserve original text')
  h.equal(relocated.anchor.start_line, 3, 'relocation should update the current location')
  h.equal(
    relocated.anchor.current_text,
    'return first + second',
    'relocation should capture new text'
  )

  local persisted =
    h.read_json(storage.paths(repo, require('review_comments.config').options).current)
  h.equal(#persisted.comments, 1, 'comment lifecycle mutations should persist transactionally')
  local counts = review.status(repo)
  h.equal(
    counts,
    { total = 1, active = 1, resolved = 0, stale = 0, orphaned = 0 },
    'status counts should be exact'
  )

  local original_save = storage.save
  storage.save = function()
    return false, 'injected failure'
  end
  local failed = review.edit_comment({ root = repo, id = first.id, text = 'Must not commit.' })
  storage.save = original_save
  h.equal(failed, nil, 'a failed durable save should fail the mutation')
  h.equal(
    review.get_comments(repo)[1].comment,
    'Use the configured first value.',
    'memory should roll back'
  )
  h.truthy(
    qf(projection.id).items[1].text:find('configured first', 1, true),
    'projection should roll back with the model'
  )

  local external = assert(storage.load(repo, require('review_comments.config').options))
  require('review_comments.model').set_comment_text(
    external.document.comments[1],
    'Changed by another Neovim process.'
  )
  local external_ok, external_err =
    storage.save(repo, external.document, require('review_comments.config').options, external.token)
  h.truthy(external_ok, external_err)
  h.truthy(
    review.copy():find('Changed by another Neovim process.', 1, true),
    'command-boundary reads should reload clean state changed by another writer'
  )

  review.setup(vim.tbl_deep_extend('force', {
    notify = false,
    clipboard = { register = '"' },
    list = { open = false },
  }, { storage = { directory = '.local/other-review' } }))
  local new_storage_comment = assert(
    review.add_comment({ line1 = 1, line2 = 1, text = 'Stored under the new configuration.' })
  )
  h.truthy(new_storage_comment, 'changed storage configuration should start isolated state')
  h.truthy(
    vim.uv.fs_stat(repo .. '/.local/other-review/current.json'),
    'changed storage configuration should write to the new location'
  )

  vim.fn.delete(repo, 'rf')
end)
