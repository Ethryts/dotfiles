local review = require('review_comments')
local marks = require('review_comments.marks')
local state = require('review_comments.state')
local storage = require('review_comments.storage')
local util = require('review_comments.util')

local repo

local function fail(message)
  error(message, 2)
end

local function equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    fail(
      string.format(
        '%s\nexpected: %s\nactual:   %s',
        message,
        vim.inspect(expected),
        vim.inspect(actual)
      )
    )
  end
end

local function truthy(value, message)
  if not value then
    fail(message)
  end
end

local function write_file(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  local ok = vim.fn.writefile(lines, path)
  equal(ok, 0, 'could not create test file')
end

local function git(args)
  local command = { 'git', '-C', repo }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    fail('git failed: ' .. (result.stderr or ''))
  end
  return vim.trim(result.stdout or '')
end

local function read_document()
  local path = storage.paths(repo, require('review_comments.config').options).current
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return vim.json.decode(content)
end

local function qf_info()
  return vim.fn.getqflist({
    id = 0,
    nr = 0,
    idx = 0,
    title = 1,
    items = 1,
    context = 1,
  })
end

local function loc_info()
  return vim.fn.getloclist(0, {
    id = 0,
    nr = 0,
    idx = 0,
    title = 1,
    items = 1,
    context = 1,
  })
end

local function run()
  repo = vim.fn.tempname()
  vim.fn.mkdir(repo, 'p')
  git({ 'init', '--quiet' })

  local source = repo .. '/src/example.lua'
  write_file(source, {
    'local M = {}',
    'function M.answer()',
    '  return 41',
    'end',
    'return M',
  })

  vim.cmd('cd ' .. vim.fn.fnameescape(repo))
  vim.cmd('edit ' .. vim.fn.fnameescape(source))
  review.setup({
    notify = false,
    clipboard = { register = '"' },
    list = { open = false },
  })

  equal(vim.fn.exists(':ReviewComment'), 2, 'plugin commands should be registered')

  local current_path = repo .. '/.local/review/current.json'
  vim.cmd('write')
  equal(
    vim.uv.fs_stat(current_path),
    nil,
    'opening or writing a repo must not create empty review state'
  )

  local comment = review.add_comment({
    line1 = 2,
    line2 = 3,
    text = 'Return the configured value instead of a magic number.',
  })
  truthy(comment, 'ReviewComment should create a comment')
  truthy(comment.id:match('^comment_'), 'comment should have a stable plugin ID')

  local live_mark = marks.get(comment.id, repo)
  truthy(live_mark and type(live_mark.extmark_id) == 'number', 'comment should have a live extmark')
  truthy(comment.id ~= tostring(live_mark.extmark_id), 'persistent ID must not be the extmark ID')

  local document = read_document()
  equal(#document.comments, 1, 'comment should be persisted')
  equal(document.comments[1].file, 'src/example.lua', 'path should be repository-relative')
  equal(
    document.comments[1].anchor.original_text,
    'function M.answer()\n  return 41',
    'original selection should be stored'
  )
  truthy(
    document.comments[1].created_at:match('Z$'),
    'creation timestamp should be UTC ISO-like text'
  )
  local original_before = vim.deepcopy(document.comments[1].anchor.original_context_before)
  local original_after = vim.deepcopy(document.comments[1].anchor.original_context_after)

  local exclude = table.concat(vim.fn.readfile(repo .. '/.git/info/exclude'), '\n')
  equal(
    select(2, exclude:gsub('/%.local/review/', '')),
    1,
    'Git exclude should be added exactly once'
  )

  vim.api.nvim_buf_set_lines(0, 0, 0, false, { '-- inserted one', '-- inserted two' })
  vim.cmd('write')
  document = read_document()
  equal(document.comments[1].anchor.start_line, 4, 'extmark start should follow edits above it')
  equal(document.comments[1].anchor.end_line, 5, 'extmark end should follow edits above it')

  vim.api.nvim_buf_set_lines(0, 3, 3, false, { '-- inserted at the start boundary' })
  vim.api.nvim_buf_set_lines(0, 6, 6, false, { '-- inserted at the end boundary' })
  local whole_buffer = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, whole_buffer)
  vim.cmd('write')
  document = read_document()
  equal(
    document.comments[1].anchor.start_line,
    5,
    'insertion at the start boundary should stay above the review'
  )
  equal(
    document.comments[1].anchor.end_line,
    6,
    'insertion at the end boundary should stay below the review'
  )
  equal(
    document.comments[1].anchor.valid,
    true,
    'an unchanged whole-buffer rewrite should relocate exactly'
  )

  vim.api.nvim_buf_set_lines(0, 4, 5, false, {
    'function M.answer(default)',
    '  default = default or 41',
  })
  vim.cmd('write')
  document = read_document()
  equal(
    document.comments[1].anchor.start_line,
    5,
    'partial replacement should retain the range start'
  )
  equal(document.comments[1].anchor.end_line, 7, 'partial replacement should adjust the range end')

  local exported = review.copy()
  truthy(exported:find('src/example.lua:5%-7'), 'export should contain the current range')
  truthy(exported:find('magic number', 1, true), 'export should contain review text')
  equal(vim.fn.getreg('"'), exported, 'ReviewCopy should write the configured register')

  vim.api.nvim_buf_set_lines(0, 4, 7, false, {
    'function M.answer(config)',
    '  return config.answer',
    '  -- exact-range replacement remains anchored',
    'end',
  })
  vim.cmd('write')
  document = read_document()
  equal(
    document.comments[1].anchor.start_line,
    5,
    'whole-line replacement should retain the range start'
  )
  equal(
    document.comments[1].anchor.end_line,
    8,
    'whole-line replacement should expand to the replacement text'
  )
  equal(
    document.comments[1].anchor.valid,
    true,
    'formatter-style replacement should not invalidate the anchor'
  )
  equal(
    document.comments[1].anchor.original_context_before,
    original_before,
    'original leading context must be immutable'
  )
  equal(
    document.comments[1].anchor.original_context_after,
    original_after,
    'original trailing context must be immutable'
  )

  local trusted_current_text = document.comments[1].anchor.current_text

  review._reset_for_tests()
  vim.api.nvim_buf_set_lines(0, 4, 8, false, {
    'local unrelated = true',
    'unrelated = not unrelated',
    'print(unrelated)',
    'return unrelated',
  })
  vim.cmd('write')
  review.setup({
    notify = false,
    clipboard = { register = '"' },
    list = { open = false },
  })
  local restored = review.get_comments(repo)
  equal(#restored, 1, 'persisted comments should load in a new plugin session')
  truthy(marks.get(restored[1].id, repo), 'a loaded buffer should regain its extmark')
  equal(restored[1].anchor.stale, true, 'external changes at a stored range should remain stale')
  local stale_export = review.copy()
  truthy(
    stale_export:find('[candidate location', 1, true),
    'copied feedback should disclose a candidate anchor'
  )
  document = read_document()
  equal(document.comments[1].anchor.stale, true, 'copying must not silently accept a stale anchor')
  equal(
    document.comments[1].anchor.current_text,
    trusted_current_text,
    'stale synchronization must preserve the last trusted text'
  )
  equal(
    document.comments[1].anchor.original_context_before,
    original_before,
    'stale synchronization must preserve original context'
  )
  equal(
    document.comments[1].anchor.original_context_after,
    original_after,
    'stale synchronization must preserve original context'
  )

  vim.fn.setqflist({}, ' ', {
    title = 'Foreign diagnostics',
    items = { { filename = source, lnum = 1, text = 'foreign item' } },
    context = { owner = 'foreign-test' },
  })
  local foreign_qf = qf_info()
  equal(review.list(), 'quickfix', 'ReviewList should normally use quickfix')
  local review_qf = qf_info()
  truthy(
    review_qf.id ~= foreign_qf.id,
    'ReviewList should push rather than replace a foreign quickfix list'
  )
  equal(review_qf.title, 'Review Comments', 'review quickfix title should be identifiable')
  vim.cmd('colder')
  equal(qf_info().id, foreign_qf.id, ':colder should restore the prior quickfix list')
  vim.cmd('cnewer')
  equal(qf_info().id, review_qf.id, ':cnewer should return to the review list')
  review.list()
  equal(qf_info().id, review_qf.id, 'refreshing the active review list should replace only itself')

  vim.cmd('copen')
  state.activate(repo .. '-different-repository')
  local list_buffer_export = review.copy()
  truthy(
    list_buffer_export:find('src/example.lua', 1, true),
    'commands from a review-list buffer should use that list repository'
  )
  vim.cmd('cclose')

  vim.fn.setqflist({}, ' ', {
    title = 'Later foreign list',
    items = {
      { filename = source, lnum = 1, text = 'first foreign item' },
      { filename = source, lnum = 2, text = 'second foreign item' },
    },
  })
  local later_foreign_qf = qf_info()
  local navigated = review.next()
  equal(navigated, false, 'ReviewNext should refuse to navigate a foreign quickfix list')
  equal(
    qf_info().id,
    later_foreign_qf.id,
    'ReviewNext should leave a foreign quickfix list current'
  )
  equal(
    qf_info().idx,
    later_foreign_qf.idx,
    'ReviewNext should not advance a foreign quickfix list'
  )

  vim.fn.setqflist({}, ' ', {
    title = 'Newer list that must survive',
    items = { { filename = source, lnum = 3, text = 'newer item' } },
  })
  local newer_qf = qf_info()
  vim.cmd('colder')
  equal(qf_info().id, later_foreign_qf.id, 'test should be on older quickfix history')
  equal(review.list(), 'quickfix', 'ReviewList should reactivate its recorded quickfix entry')
  equal(
    qf_info().id,
    review_qf.id,
    'ReviewList should reuse its owned history entry instead of pushing another list'
  )
  vim.cmd({ cmd = 'cnewer', count = newer_qf.nr - review_qf.nr })
  equal(qf_info().id, newer_qf.id, 'newer quickfix history should remain recoverable')

  local left = vim.fn.tempname() .. '-left.lua'
  local right = vim.fn.tempname() .. '-right.lua'
  local left_b = vim.fn.tempname() .. '-left-b.lua'
  local source_b = repo .. '/src/other.lua'
  write_file(left, { 'local snapshot = 1', 'return snapshot' })
  write_file(right, { 'local snapshot = 2', 'return snapshot' })
  write_file(left_b, { 'local other = 1', 'return other' })
  write_file(source_b, { 'local other = 2', 'return other' })
  vim.cmd('edit ' .. vim.fn.fnameescape(left))

  vim.fn.setqflist({}, ' ', {
    title = 'DiffTool',
    items = {
      {
        filename = source,
        lnum = 1,
        text = 'src/example.lua',
        user_data = {
          diff = true,
          rel = 'src/example.lua',
          left = left,
          right = source,
        },
      },
      {
        filename = source_b,
        lnum = 1,
        text = 'src/other.lua',
        user_data = {
          diff = true,
          rel = 'src/other.lua',
          left = left_b,
          right = source_b,
        },
      },
    },
  })
  local difftool_qf = qf_info()
  local source_bufnr = vim.fn.bufnr(source)
  local right_target = util.resolve_target(source_bufnr, require('review_comments.config').options)
  equal(
    right_target.view,
    'right',
    'DiffTool metadata should take priority even for files inside the repo'
  )
  equal(
    right_target.file,
    'src/example.lua',
    'right DiffTool target should remain repository-relative'
  )
  equal(
    right_target.source,
    { kind = 'worktree' },
    'a right pane backed by the repository should retain worktree identity'
  )

  local snapshot_comment = review.add_comment({
    line1 = 1,
    line2 = 1,
    text = 'Keep the manual implementation from the working tree.',
  })
  truthy(snapshot_comment, 'comments should work in an external DiffTool snapshot')
  equal(
    snapshot_comment.file,
    'src/example.lua',
    'DiffTool metadata should recover the repository path'
  )
  equal(snapshot_comment.anchor.source, {
    kind = 'snapshot',
    side = 'left',
    content_sha256 = vim.fn.sha256(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')),
  }, 'DiffTool source identity should retain the historical side')

  local left_win = vim.api.nvim_get_current_win()
  vim.cmd('vsplit ' .. vim.fn.fnameescape(source))
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(left_win)

  vim.fn.setloclist(0, {}, ' ', {
    title = 'Foreign location list',
    items = {
      { filename = source, lnum = 1, text = 'first foreign location' },
      { filename = source, lnum = 2, text = 'second foreign location' },
    },
    context = { owner = 'foreign-location-test' },
  })
  local foreign_loc = loc_info()

  vim.fn.setloclist(0, {}, ' ', {
    title = 'Newer location list that must survive',
    items = { { filename = source, lnum = 3, text = 'newer location' } },
  })
  local newer_loc = loc_info()
  vim.cmd('lolder')
  equal(loc_info().id, foreign_loc.id, 'test should be on older location-list history')
  equal(review.list(), nil, 'ReviewList should refuse to truncate newer location-list history')
  equal(
    loc_info().id,
    foreign_loc.id,
    'a refused ReviewList should leave the current location list untouched'
  )
  vim.cmd('lnewer')
  equal(loc_info().id, newer_loc.id, 'newer location-list history should remain recoverable')
  foreign_loc = newer_loc

  equal(review.list(), 'loclist', 'DiffTool should force the location-list fallback')
  local review_loc = loc_info()
  equal(qf_info().id, difftool_qf.id, 'ReviewList must not replace the DiffTool quickfix list')
  equal(qf_info().items, difftool_qf.items, 'ReviewList must not mutate DiffTool entries')
  truthy(
    review_loc.id ~= foreign_loc.id,
    'DiffTool fallback should preserve a foreign location list in history'
  )
  equal(review_loc.title, 'Review Comments', 'fallback location list should be identifiable')
  local snapshot_item
  local unloaded_item
  for _, item in ipairs(review_loc.items) do
    if item.user_data.review_comment_id == snapshot_comment.id then
      snapshot_item = item
    elseif item.user_data.review_comment_id == comment.id then
      unloaded_item = item
    end
  end
  truthy(snapshot_item, 'DiffTool review should appear in the location list')
  equal(snapshot_item.valid, 0, 'even active DiffTool rows should remain targetless')
  equal(snapshot_item.bufnr, 0, 'active DiffTool rows should not retain a stale buffer target')
  truthy(unloaded_item, 'an opposite-pane review should remain visible during DiffTool')
  equal(unloaded_item.valid, 0, 'an opposite-pane review must not tear apart the paired panes')
  equal(review.next(), true, 'ReviewNext should validate and navigate the active DiffTool side')
  equal(vim.api.nvim_get_current_buf(), vim.fn.bufnr(left), 'ReviewNext should keep the owner pane')
  local before_invalid_jump = vim.api.nvim_get_current_buf()
  local invalid_jump = pcall(vim.cmd, 'll 1')
  equal(invalid_jump, true, 'a targetless DiffTool review row should remain inspectable')
  equal(
    vim.api.nvim_get_current_buf(),
    before_invalid_jump,
    'invalid DiffTool navigation should not replace the current pane'
  )
  vim.cmd('lolder')
  equal(loc_info().id, foreign_loc.id, ':lolder should restore the prior location list')
  local foreign_loc_idx = loc_info().idx
  navigated = review.next()
  equal(navigated, false, 'ReviewNext should refuse to navigate a foreign location list')
  equal(loc_info().id, foreign_loc.id, 'ReviewNext should leave a foreign location list current')
  equal(loc_info().idx, foreign_loc_idx, 'ReviewNext should not advance a foreign location list')
  vim.cmd('lnewer')
  equal(loc_info().id, review_loc.id, ':lnewer should return to the review location list')
  review.list()
  equal(
    loc_info().id,
    review_loc.id,
    'refreshing the review location list should replace only itself'
  )
  equal(qf_info().id, difftool_qf.id, 'refreshing reviews must leave DiffTool quickfix active')

  vim.api.nvim_set_current_win(right_win)
  equal(review.list(), 'loclist', 'ReviewList should follow the active DiffTool pane')
  local right_review_loc = loc_info()
  local opposite_item
  for _, item in ipairs(right_review_loc.items) do
    if item.user_data.review_comment_id == snapshot_comment.id then
      opposite_item = item
      break
    end
  end
  truthy(opposite_item, 'the opposite-pane review should remain visible')
  equal(opposite_item.valid, 0, 'the opposite-pane review should not be natively jumpable')
  equal(opposite_item.bufnr, 0, 'the opposite-pane review should carry no buffer target')
  equal(
    review.next(),
    true,
    'ReviewNext should navigate row one when it is the only active DiffTool review'
  )
  equal(
    vim.api.nvim_get_current_buf(),
    vim.fn.bufnr(source),
    'initial DiffTool navigation should keep the right owner pane'
  )
  review.list()
  equal(
    review.previous(),
    true,
    'ReviewPrevious should navigate row one when it is the only active DiffTool review'
  )
  local right_before_jump = vim.api.nvim_get_current_buf()
  pcall(vim.cmd, 'll 2')
  equal(
    vim.api.nvim_get_current_buf(),
    right_before_jump,
    'opening an opposite-pane review should not duplicate one DiffTool side'
  )
  equal(qf_info().id, difftool_qf.id, 'opposite-pane review listing must preserve DiffTool')

  vim.cmd('cnext')
  vim.api.nvim_set_current_win(left_win)
  vim.cmd('edit ' .. vim.fn.fnameescape(left_b))
  vim.api.nvim_set_current_win(right_win)
  equal(vim.api.nvim_get_current_buf(), vim.fn.bufnr(source_b), 'DiffTool should advance to file B')
  local before_stale_row = vim.api.nvim_get_current_buf()
  pcall(vim.cmd, 'll 1')
  equal(
    vim.api.nvim_get_current_buf(),
    before_stale_row,
    'an old review row must stay targetless after DiffTool advances'
  )
  equal(review.next(), false, 'ReviewNext should reject rows from the prior DiffTool file')
  equal(
    vim.api.nvim_win_get_buf(left_win),
    vim.fn.bufnr(left_b),
    'the left B pane should remain intact'
  )
  equal(
    vim.api.nvim_win_get_buf(right_win),
    vim.fn.bufnr(source_b),
    'the right B pane should remain intact'
  )

  local archive_path = review.clear()
  truthy(archive_path and vim.uv.fs_stat(archive_path), 'ReviewClear should create an archive')
  local archive_file = assert(io.open(archive_path, 'rb'))
  local archived = vim.json.decode(archive_file:read('*a'))
  archive_file:close()
  equal(#archived.comments, 2, 'the archive should retain every cleared comment')
  equal(#read_document().comments, 0, 'ReviewClear should create a new empty current session')
  equal(qf_info().id, difftool_qf.id, 'ReviewClear must not clear the DiffTool quickfix list')
  equal(marks.get(comment.id, repo), nil, 'ReviewClear should remove source extmarks')
  equal(marks.get(snapshot_comment.id, repo), nil, 'ReviewClear should remove snapshot extmarks')

  review._reset_for_tests()
  vim.fn.delete(left)
  vim.fn.delete(right)
  vim.fn.delete(left_b)
  vim.fn.delete(repo, 'rf')
  repo = nil
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  pcall(review._reset_for_tests)
  if repo then
    vim.fn.delete(repo, 'rf')
  end
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
else
  print('review-comments.nvim tests passed')
  vim.cmd('quitall!')
end
