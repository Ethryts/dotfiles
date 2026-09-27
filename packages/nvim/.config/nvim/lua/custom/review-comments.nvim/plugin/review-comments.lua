if vim.g.loaded_review_comments_nvim == 1 then
  return
end
vim.g.loaded_review_comments_nvim = 1

local function plugin()
  return require('review_comments')
end

local function visual_selection_type(opts)
  if opts.range ~= 2 then
    return nil
  end
  local selection_type = vim.fn.visualmode()
  if selection_type ~= 'v' and selection_type ~= 'V' and selection_type ~= '\22' then
    return nil
  end
  local first = vim.fn.getpos("'<")
  local last = vim.fn.getpos("'>")
  local bufnr = vim.api.nvim_get_current_buf()
  local first_buf = first[1] == 0 and bufnr or first[1]
  local last_buf = last[1] == 0 and bufnr or last[1]
  local first_line = math.min(first[2], last[2])
  local last_line = math.max(first[2], last[2])
  if
    first_buf == bufnr
    and last_buf == bufnr
    and first_line == opts.line1
    and last_line == opts.line2
  then
    return selection_type
  end
  return nil
end

vim.api.nvim_create_user_command('ReviewComment', function(opts)
  plugin().add_comment({
    bufnr = vim.api.nvim_get_current_buf(),
    line1 = opts.line1,
    line2 = opts.line2,
    selection_type = visual_selection_type(opts),
    text = opts.args ~= '' and opts.args or nil,
  })
end, {
  desc = 'Add a review comment to a line range',
  nargs = '*',
  range = true,
})

vim.api.nvim_create_user_command('ReviewCopy', function(opts)
  plugin().copy({ include_resolved = opts.bang })
end, { desc = 'Copy active review comments; use ! to include resolved', bang = true })

vim.api.nvim_create_user_command('ReviewList', function(opts)
  plugin().list({ include_resolved = opts.bang })
end, {
  desc = 'Open active review comments; use ! to include resolved',
  bang = true,
})

vim.api.nvim_create_user_command('ReviewEdit', function(opts)
  plugin().edit_comment({ text = opts.args ~= '' and opts.args or nil })
end, { desc = 'Edit the selected review comment', nargs = '*' })

vim.api.nvim_create_user_command('ReviewDelete', function(opts)
  plugin().delete_comment({ id = opts.args ~= '' and opts.args or nil, force = opts.bang })
end, { desc = 'Delete the selected review comment', nargs = '?', bang = true })

vim.api.nvim_create_user_command('ReviewResolve', function(opts)
  plugin().resolve_review({ id = opts.args ~= '' and opts.args or nil })
end, { desc = 'Resolve the selected review comment', nargs = '?' })

vim.api.nvim_create_user_command('ReviewReopen', function(opts)
  plugin().reopen_review({ id = opts.args ~= '' and opts.args or nil })
end, { desc = 'Reopen the selected resolved comment', nargs = '?' })

vim.api.nvim_create_user_command('ReviewRelocate', function(opts)
  plugin().relocate_comment({
    bufnr = vim.api.nvim_get_current_buf(),
    id = opts.args ~= '' and opts.args or nil,
    line1 = opts.line1,
    line2 = opts.line2,
    selection_type = visual_selection_type(opts),
  })
end, { desc = 'Relocate a stale review comment to a line range', nargs = '?', range = true })

vim.api.nvim_create_user_command('ReviewStatus', function()
  plugin().status()
end, { desc = 'Show review comment counts and anchor health' })

vim.api.nvim_create_user_command('ReviewReload', function(opts)
  plugin().reload({ force = opts.bang })
end, { desc = 'Reload review state from disk; use ! to discard pending local state', bang = true })

vim.api.nvim_create_user_command('ReviewStart', function(opts)
  plugin().start_session({
    base_ref = opts.args ~= '' and opts.args or 'HEAD',
    force = opts.bang,
  })
end, {
  desc = 'Start a Git-scoped review session; use ! to archive the current non-empty session',
  nargs = '?',
  bang = true,
})

vim.api.nvim_create_user_command('ReviewDiff', function()
  plugin().open_diff()
end, { desc = 'Open the configured diff UI for the current review scope' })

vim.api.nvim_create_user_command('ReviewClear', function()
  plugin().clear()
end, { desc = 'Archive and clear active review comments' })

vim.api.nvim_create_user_command('ReviewNext', function()
  plugin().next()
end, { desc = 'Go to the next review comment' })

vim.api.nvim_create_user_command('ReviewPrevious', function()
  plugin().previous()
end, { desc = 'Go to the previous review comment' })

vim.api.nvim_create_user_command('ReviewJump', function()
  plugin().jump()
end, { desc = 'Jump to the selected review comment when its source is available' })

vim.api.nvim_create_user_command('ReviewListClose', function()
  plugin().close_list()
end, { desc = 'Close the review list and restore the previous quickfix list' })
