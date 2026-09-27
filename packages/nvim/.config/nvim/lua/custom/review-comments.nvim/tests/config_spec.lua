local h = require('tests.helpers')
local config = require('review_comments.config')
local review = require('review_comments')

h.run('config_spec', function()
  local invalid = {
    { storage = { directory = '/outside' } },
    { storage = { directory = 'C:/outside' } },
    { storage = { directory = [[C:\outside]] } },
    { storage = { directory = [[\\server\share]] } },
    { storage = { directory = [[safe\..\escape]] } },
    { storage = { current_file = '.' } },
    { storage = { archive_directory = 'current.json' } },
    { storage = { recovery_directory = 'current.json' } },
    { storage = { archive_directory = 'current.json.lock' } },
    { storage = { recovery_directory = 'current.json.lock' } },
    { storage = { archive_directory = 'recovery' } },
    { storage = { archive_directory = 'current.json/archive' } },
    { storage = { recovery_directory = 'archive/recovery' } },
    { storage = { archive_directory = '.' } },
    { context_lines = -1 },
    { relocation = { search_window = 20 } },
    { relocation = { global_search = false } },
    { relocation = { max_candidate_lines = 0 } },
    { relocation = { git_renames = 'yes' } },
    { relocation = { file_search = 'yes' } },
    { relocation = { max_candidate_files = 0 } },
    { relocation = { max_file_bytes = 0 } },
    { display = { sign_text = 'wide' } },
    { display = { candidate_sign_text = 'wide' } },
    { display = { orphaned_sign_text = 'wide' } },
    { list = { height = 0 } },
    { list = { difftool_fallback = 'quickfix' } },
    { resolve_target = true },
    { editor = { start_insert = 'yes' } },
    { session = { open_diff = true } },
  }
  for _, opts in ipairs(invalid) do
    local ok = pcall(config.setup, opts)
    h.equal(ok, false, 'invalid configuration should fail early: ' .. vim.inspect(opts))
  end

  review.setup({ notify = false, clipboard = { register = '"' } })
  for _, command in ipairs({
    'ReviewComment',
    'ReviewEdit',
    'ReviewDelete',
    'ReviewResolve',
    'ReviewReopen',
    'ReviewRelocate',
    'ReviewCopy',
    'ReviewList',
    'ReviewStatus',
    'ReviewReload',
    'ReviewStart',
    'ReviewDiff',
    'ReviewJump',
    'ReviewNext',
    'ReviewPrevious',
    'ReviewListClose',
    'ReviewClear',
  }) do
    h.equal(vim.fn.exists(':' .. command), 2, command .. ' should be registered')
  end
  h.truthy(require('review_comments.health').check, 'the standard checkhealth module should load')
end)
