local h = require('tests.helpers')
local quickfix = require('review_comments.quickfix')

local function config(open)
  return {
    list = {
      difftool_fallback = 'loclist',
      height = 6,
      open = open == true,
    },
  }
end

local function document(comments)
  return {
    version = 2,
    session = { id = 'session_quickfix_spec' },
    comments = comments,
  }
end

local function comment(id, file, line, text, source, status)
  return {
    id = id,
    file = file,
    comment = text,
    status = status or 'active',
    anchor = {
      start_line = line,
      end_line = line,
      valid = true,
      source = source,
    },
  }
end

local function qf(id)
  return vim.fn.getqflist({
    id = id or 0,
    nr = 0,
    idx = 0,
    title = 1,
    items = 1,
    context = 1,
    qfbufnr = 1,
  })
end

local function loc(winid, id)
  local result
  vim.api.nvim_win_call(winid, function()
    result = vim.fn.getloclist(0, {
      id = id or 0,
      nr = 0,
      idx = 0,
      title = 1,
      items = 1,
      context = 1,
      qfbufnr = 1,
      filewinid = 1,
    })
  end)
  return result
end

local function row_for(info, id)
  for row, item in ipairs(info.items or {}) do
    if item.user_data and item.user_data.review_comment_id == id then
      return row, item
    end
  end
end

h.run('quickfix_spec', function()
  local repo = h.repo()
  local source = repo .. '/sample.lua'
  h.write_file(source, {
    'local first = 1',
    'local second = 2',
    'return first + second',
  })
  vim.cmd('cd ' .. vim.fn.fnameescape(repo))
  vim.cmd('edit ' .. vim.fn.fnameescape(source))

  vim.fn.setqflist({}, ' ', {
    title = 'Foreign diagnostics',
    items = { { filename = source, lnum = 1, text = 'foreign' } },
    context = { owner = 'foreign' },
  })
  local foreign = qf()
  local comments = {
    comment('resolved', 'sample.lua', 1, 'old note', { kind = 'worktree' }, 'resolved'),
    comment('worktree', 'sample.lua', 2, 'live note', { kind = 'worktree' }),
    comment('snapshot', 'sample.lua', 3, 'historical note', {
      kind = 'snapshot',
      side = 'left',
    }),
  }
  local active_document = document(comments)

  h.equal(
    quickfix.open(repo, active_document, config(false)),
    'quickfix',
    'normal review comments should use quickfix'
  )
  local review = qf()
  local review_id = review.id
  local newest_nr = vim.fn.getqflist({ nr = '$' }).nr
  h.equal(#review.items, 2, 'the active projection should omit resolved comments')
  local live_row, live_item = row_for(review, 'worktree')
  local snapshot_row, snapshot_item = row_for(review, 'snapshot')
  h.equal(live_item.valid, 1, 'a worktree row should retain a native quickfix target')
  h.equal(snapshot_item.valid, 0, 'a normal quickfix snapshot must be targetless')
  h.equal(snapshot_item.bufnr, 0, 'a snapshot must not alias the worktree buffer')
  h.truthy(
    snapshot_item.text:find('historical left side unavailable', 1, true),
    'a snapshot row should explain why it is unavailable'
  )

  vim.cmd('copen')
  vim.api.nvim_win_set_cursor(0, { snapshot_row, 0 })
  local qf_bufnr = vim.api.nvim_get_current_buf()
  local jumped, jump_err = quickfix.jump_selected(repo)
  h.equal(jumped, false, 'a normal quickfix snapshot must refuse ReviewJump')
  h.truthy(jump_err:find('Historical', 1, true), 'the refusal should identify historical data')
  h.equal(vim.api.nvim_get_current_buf(), qf_bufnr, 'a refused jump must not leave the list')
  vim.api.nvim_win_set_cursor(0, { live_row, 0 })
  local live_jumped, live_jump_err = quickfix.jump_selected(repo)
  h.equal(live_jumped, true, 'a worktree row should jump safely: ' .. tostring(live_jump_err))
  h.equal(
    vim.api.nvim_get_current_buf(),
    vim.fn.bufnr(source),
    'the worktree jump should open source'
  )
  h.equal(vim.api.nvim_win_get_cursor(0)[1], 2, 'the worktree jump should use the review line')

  vim.fn.setqflist({}, 'a', { id = review_id, idx = snapshot_row })
  vim.cmd('colder')
  h.equal(qf().id, foreign.id, 'the test should hide the review projection')
  local foreign_before = vim.deepcopy(qf(foreign.id))
  h.equal(
    quickfix.open(repo, active_document, config(false), { include_resolved = true }),
    'quickfix',
    'rerunning ReviewList should reactivate an existing hidden projection'
  )
  review = qf()
  h.equal(review.id, review_id, 'rerunning must reuse the exact quickfix list ID')
  h.equal(
    vim.fn.getqflist({ nr = '$' }).nr,
    newest_nr,
    'rerunning must not push another quickfix history entry'
  )
  h.equal(qf(foreign.id).items, foreign_before.items, 'rerunning must not mutate a foreign list')
  h.equal(#review.items, 3, 'bang mode should include resolved comments')
  h.equal(
    review.items[review.idx].user_data.review_comment_id,
    'snapshot',
    'filter changes should preserve selection by persistent comment ID'
  )

  for _, item in ipairs(comments) do
    item.status = 'resolved'
  end
  h.equal(
    quickfix.open(repo, active_document, config(false)),
    'quickfix',
    'an existing projection should remain usable with zero matching rows'
  )
  review = qf()
  h.equal(review.id, review_id, 'emptying a projection should retain its quickfix ID')
  h.equal(#review.items, 0, 'the active-only projection should be empty')

  quickfix.reset()
  vim.fn.setqflist({}, 'f')
  vim.cmd('edit ' .. vim.fn.fnameescape(source))
  local navigation_document = document({
    comment('one', 'sample.lua', 1, 'one', { kind = 'worktree' }),
    comment('two', 'sample.lua', 2, 'two', { kind = 'worktree' }),
    comment('three', 'sample.lua', 3, 'three', { kind = 'worktree' }),
  })
  h.equal(quickfix.open(repo, navigation_document, config(true)), 'quickfix')
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  h.equal(quickfix.next(repo), true, 'ReviewNext should navigate from the visible row')
  h.equal(qf().idx, 3, 'ReviewNext should advance after the visible row, not stale qf idx')
  h.equal(vim.api.nvim_win_get_cursor(0)[1], 3, 'ReviewNext should land on the third line')
  vim.cmd('copen')
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  h.equal(quickfix.previous(repo), true, 'ReviewPrevious should navigate from the visible row')
  h.equal(qf().idx, 1, 'ReviewPrevious should move before the visible row')

  quickfix.reset()
  pcall(vim.cmd, 'cclose')
  vim.cmd('only')
  vim.fn.setqflist({}, ' ', {
    title = 'Foreign diff-like metadata',
    items = {
      {
        filename = source,
        lnum = 1,
        text = 'not built-in DiffTool',
        user_data = { diff = true, rel = 'sample.lua', left = source, right = source },
      },
    },
  })
  h.equal(
    quickfix.current_is_difftool(),
    false,
    'foreign user_data.diff metadata must not be mistaken for built-in DiffTool'
  )
  local left = vim.fn.tempname() .. '-left.lua'
  h.write_file(left, { 'local first = 0', 'local second = 0', 'return first + second' })
  vim.cmd('edit ' .. vim.fn.fnameescape(left))
  local left_win = vim.api.nvim_get_current_win()
  vim.cmd('vsplit ' .. vim.fn.fnameescape(source))
  local right_win = vim.api.nvim_get_current_win()
  vim.fn.setqflist({}, ' ', {
    title = 'DiffTool',
    items = {
      {
        filename = source,
        lnum = 1,
        text = 'sample.lua',
        user_data = {
          diff = true,
          rel = 'sample.lua',
          left = left,
          right = source,
        },
      },
    },
  })
  local difftool = qf()
  vim.api.nvim_set_current_win(left_win)
  local difftool_document = document({
    comment('left', 'sample.lua', 1, 'left note', { kind = 'snapshot', side = 'left' }),
    comment('right', 'sample.lua', 2, 'right note', { kind = 'worktree' }),
  })
  h.equal(quickfix.open(repo, difftool_document, config(true)), 'loclist')
  local projection = loc(left_win)
  local projection_id = projection.id
  local projection_newest = vim.api.nvim_win_call(left_win, function()
    return vim.fn.getloclist(0, { nr = '$' }).nr
  end)
  h.equal(
    quickfix.last_lists[repo].owner,
    left_win,
    'the location list should belong to the left pane'
  )
  for _, item in ipairs(projection.items) do
    h.equal(item.valid, 0, 'every DiffTool projection row must remain targetless')
    h.equal(item.bufnr, 0, 'DiffTool rows must not carry native buffer targets')
  end

  local left_row = assert(row_for(projection, 'left'))
  local right_row = assert(row_for(projection, 'right'))
  vim.api.nvim_win_set_cursor(0, { right_row, 0 })
  local loc_qfbufnr = vim.api.nvim_get_current_buf()
  h.equal(
    quickfix.open(repo, difftool_document, config(true)),
    'loclist',
    'ReviewList from its location-list buffer should reuse that owner'
  )
  loc_qfbufnr = loc(left_win).qfbufnr
  h.equal(quickfix.last_lists[repo].owner, left_win, 'the qf buffer must preserve true filewinid')
  h.equal(loc(left_win).id, projection_id, 'the exact location-list ID should be reused')
  h.equal(
    vim.api.nvim_win_call(left_win, function()
      return vim.fn.getloclist(0, { nr = '$' }).nr
    end),
    projection_newest,
    'rerunning from the list buffer must not push a new location list'
  )
  h.truthy(
    vim.fn.bufwinid(loc_qfbufnr) ~= -1,
    'rerunning should keep the owned location-list window visible'
  )

  projection = loc(left_win)
  left_row = assert(row_for(projection, 'left'))
  right_row = assert(row_for(projection, 'right'))
  vim.api.nvim_win_set_cursor(0, { right_row, 0 })
  local before_rejected = vim.api.nvim_get_current_buf()
  local rejected = quickfix.jump_selected(repo)
  h.equal(rejected, false, 'ReviewJump must reject the opposite DiffTool side')
  h.equal(
    before_rejected,
    vim.api.nvim_get_current_buf(),
    'a rejected DiffTool jump must preserve panes'
  )
  loc_qfbufnr = projection.qfbufnr
  local list_win = vim.fn.bufwinid(loc_qfbufnr)
  h.truthy(list_win ~= -1, 'the review location list should remain visible')
  vim.api.nvim_set_current_win(list_win)
  local review_buffer = quickfix.is_review_buffer(vim.api.nvim_get_current_buf())
  h.truthy(review_buffer, 'the visible location list should be tracked: ' .. vim.inspect({
    current = vim.api.nvim_get_current_buf(),
    expected = loc_qfbufnr,
    left = loc(left_win),
    last = quickfix.last_lists[repo],
  }))
  vim.api.nvim_win_set_cursor(0, { left_row, 0 })
  local left_jumped, left_jump_err = quickfix.jump_selected(repo)
  h.equal(
    left_jumped,
    true,
    'ReviewJump should accept the exact active side: ' .. tostring(left_jump_err)
  )
  h.equal(
    vim.api.nvim_get_current_win(),
    left_win,
    'a DiffTool jump should return to its owner pane'
  )
  h.equal(vim.api.nvim_win_get_buf(left_win), vim.fn.bufnr(left), 'the left pane must stay intact')
  h.equal(
    vim.api.nvim_win_get_buf(right_win),
    vim.fn.bufnr(source),
    'the right pane must stay intact'
  )
  h.equal(qf().id, difftool.id, 'location-list operations must preserve DiffTool quickfix')
  h.equal(qf().items, difftool.items, 'location-list operations must not mutate DiffTool rows')

  vim.fn.delete(left)
  vim.fn.delete(repo, 'rf')
end)
