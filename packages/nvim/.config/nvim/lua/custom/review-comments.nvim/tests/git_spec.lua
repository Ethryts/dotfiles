local h = require('tests.helpers')
local git = require('review_comments.git')

local function commit_file(repo, path, contents, message)
  h.write_file(repo .. '/' .. path, contents)
  h.git(repo, { 'add', '--', path })
  h.git(repo, { 'commit', '--quiet', '-m', message })
  return h.git(repo, { 'rev-parse', 'HEAD' })
end

h.run('git_spec', function()
  local repo = h.repo()
  local first = commit_file(repo, 'first.lua', { 'return 1' }, 'first')
  local second = commit_file(repo, 'second.lua', { 'return 2' }, 'second')

  h.equal(git.resolve_commit(repo, 'HEAD'), second, 'HEAD should resolve to a full commit ID')
  h.equal(git.resolve_commit(repo, 'HEAD~1'), first, 'revision expressions should be supported')
  local invalid, invalid_err = git.resolve_commit(repo, 'definitely-not-a-revision')
  h.equal(invalid, nil, 'invalid revisions should not resolve')
  h.truthy(
    type(invalid_err) == 'string' and invalid_err ~= '',
    'invalid revisions should explain failure'
  )

  local sentinel = repo .. '/injected'
  for _, ref in ipairs({
    '--help',
    '--output=' .. sentinel,
    'HEAD;touch injected',
    'HEAD\n--help',
  }) do
    local resolved = git.resolve_commit(repo, ref)
    h.equal(resolved, nil, 'option- and shell-like refs must fail safely: ' .. ref)
  end
  h.equal(vim.uv.fs_stat(sentinel), nil, 'revision text must never be evaluated by a shell')

  h.git(repo, { 'checkout', '--quiet', '--detach', 'HEAD' })
  local scope = assert(git.session_scope(repo, 'HEAD~1'))
  h.equal(scope.kind, 'git_diff', 'scope should identify a Git diff')
  h.equal(scope.base.requested, 'HEAD~1', 'scope should retain the requested ref')
  h.equal(scope.base.commit, first, 'scope should freeze the resolved base')
  h.equal(scope.target.kind, 'worktree', 'scope target should be the worktree')
  h.equal(scope.target.head_commit_at_start, second, 'scope should freeze the current HEAD')
  h.equal(scope.target.branch_at_start, nil, 'detached HEAD should not invent a branch')

  local rename_repo = h.repo()
  local old = 'src/old name\tpart.lua'
  local staged = 'src/staged name\tpart.lua'
  local unstaged = 'src/unstaged name\tpart.lua'
  local committed = 'src/committed name\tpart.lua'
  local base = commit_file(rename_repo, old, { 'local value = 1', 'return value' }, 'rename base')

  h.git(rename_repo, { 'mv', '--', old, staged })
  local staged_map = assert(git.rename_map(rename_repo, base))
  h.equal(
    staged_map[old],
    { new = staged, score = 100 },
    'staged renames with spaces and tabs should parse losslessly'
  )
  h.equal(
    git.current_tracking(rename_repo, staged),
    { path = old, commit = base },
    'a staged rename destination should retain its unique HEAD identity'
  )

  h.git(rename_repo, { 'reset', '--quiet', 'HEAD', '--', old, staged })
  h.git(rename_repo, { 'add', '-N', '--', staged })
  local unstaged_map = assert(git.rename_map(rename_repo, base))
  h.equal(
    unstaged_map[old],
    { new = staged, score = 100 },
    'an intent-to-add unstaged rename should be discovered'
  )

  h.git(rename_repo, { 'add', '--', old, staged })
  h.git(rename_repo, { 'commit', '--quiet', '-m', 'staged rename' })
  h.git(rename_repo, { 'mv', '--', staged, unstaged })
  h.git(rename_repo, { 'commit', '--quiet', '-m', 'second rename' })
  h.git(rename_repo, { 'mv', '--', unstaged, committed })
  h.git(rename_repo, { 'commit', '--quiet', '-m', 'committed rename' })
  local committed_map = assert(git.rename_map(rename_repo, base))
  h.equal(
    committed_map[old],
    { new = committed, score = 100 },
    'rename detection should follow the net committed rename from the base'
  )

  local tracked = assert(git.current_tracking(rename_repo, committed))
  h.equal(tracked.path, committed, 'a path present at HEAD should track itself')
  h.equal(
    tracked.commit,
    h.git(rename_repo, { 'rev-parse', 'HEAD' }),
    'tracked paths should retain HEAD'
  )

  local untracked = 'scratch/untracked name\tpart.lua'
  local ignored = 'scratch/ignored.lua'
  h.write_file(rename_repo .. '/' .. untracked, { 'return 3' })
  h.write_file(rename_repo .. '/.gitignore', { 'scratch/ignored.lua' })
  h.write_file(rename_repo .. '/' .. ignored, { 'return 4' })
  local listed = assert(git.files(rename_repo))
  h.truthy(vim.tbl_contains(listed, committed), 'tracked files should be listed')
  h.truthy(vim.tbl_contains(listed, untracked), 'untracked files should be listed losslessly')
  h.equal(vim.tbl_contains(listed, ignored), false, 'ignored files should not be listed')
  h.equal(
    git.current_tracking(rename_repo, untracked),
    { path = untracked },
    'untracked files have no commit'
  )

  for _, unsafe in ipairs({ '../outside', '/absolute', [[C:\outside]], [[\outside]] }) do
    local tracking, tracking_err = git.current_tracking(rename_repo, unsafe)
    h.equal(tracking, nil, 'unsafe tracking paths should be rejected: ' .. unsafe)
    h.truthy(type(tracking_err) == 'string', 'unsafe tracking paths should return an error')
  end

  local no_repo = vim.fn.tempname()
  vim.fn.mkdir(no_repo, 'p')
  local no_files, no_files_err = git.files(no_repo)
  h.equal(no_files, nil, 'file listing should fail outside a repository')
  h.truthy(type(no_files_err) == 'string', 'repository errors should be reported')
end)
