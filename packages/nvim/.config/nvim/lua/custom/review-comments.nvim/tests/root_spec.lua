local h = require('tests.helpers')
local review = require('review_comments')
local state = require('review_comments.state')

local function edit(path)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

h.run('root_spec', function()
  local first_repo = h.repo()
  local second_repo = h.repo()
  local first_path = first_repo .. '/first.lua'
  local second_path = second_repo .. '/second.lua'
  h.write_file(first_path, { 'return "first"' })
  h.write_file(second_path, { 'return "second"' })
  h.git(first_repo, { 'add', 'first.lua' })
  h.git(first_repo, { 'commit', '--quiet', '-m', 'first root' })
  h.git(second_repo, { 'add', 'second.lua' })
  h.git(second_repo, { 'commit', '--quiet', '-m', 'second root' })

  review.setup({ notify = false, clipboard = { register = '"' }, list = { open = false } })
  edit(first_path)
  local first = assert(review.add_comment({ line1 = 1, line2 = 1, text = 'First root.' }))
  edit(second_path)
  local second = assert(review.add_comment({ line1 = 1, line2 = 1, text = 'Second root.' }))

  local alias = vim.fn.tempname()
  local linked, link_err = (vim.uv or vim.loop).fs_symlink(first_repo, alias, { dir = true })
  h.truthy(linked, 'could not create repository symlink: ' .. tostring(link_err))

  h.equal(
    review.get_comments(first_repo .. '/')[1].id,
    first.id,
    'a trailing slash should resolve to the canonical repository session'
  )
  h.equal(
    review.get_comments(alias)[1].id,
    first.id,
    'a symlink alias should resolve to the canonical repository session'
  )
  h.equal(
    review.get_session(alias).id,
    review.get_session(first_repo).id,
    'session lookup through an alias should retain one session identity'
  )

  review.setup({
    notify = false,
    clipboard = { register = '"' },
    list = { open = false },
    resolve_target = function(ctx)
      if ctx.buffer_path == first_path then
        return { root = alias, file = 'first.lua', source = { kind = 'worktree' } }
      end
    end,
  })
  edit(first_path)
  assert(review.add_comment({ line1 = 1, line2 = 1, text = 'Custom resolver alias.' }))
  h.equal(
    state.sessions[alias],
    nil,
    'a custom resolver root must be canonicalized before state/storage access'
  )

  assert(review.edit_comment({ root = alias, id = first.id, text = 'Edited through alias.' }))
  h.equal(
    review.get_comments(first_repo)[1].comment,
    'Edited through alias.',
    'a mutation through an alias should update canonical state'
  )
  h.equal(
    review.get_comments(second_repo)[1].id,
    second.id,
    'an aliased mutation must not select another loaded repository'
  )
  h.equal(
    review.get_comments(second_repo)[1].comment,
    'Second root.',
    'an aliased mutation must not modify another repository'
  )

  h.equal(state.sessions[alias], nil, 'a symlink spelling must not create a duplicate state key')
  h.equal(
    state.sessions[first_repo .. '/'],
    nil,
    'a trailing-slash spelling must not create a duplicate state key'
  )
  h.truthy(state.sessions[first_repo], 'the canonical first repository should remain loaded')
  h.truthy(state.sessions[second_repo], 'the canonical second repository should remain loaded')

  local uv = vim.uv or vim.loop
  uv.fs_unlink(alias)
  vim.fn.delete(first_repo, 'rf')
  vim.fn.delete(second_repo, 'rf')
end)
