local h = require('tests.helpers')
local config = require('review_comments.config')
local model = require('review_comments.model')
local storage = require('review_comments.storage')
local util = require('review_comments.util')

h.run('storage_spec', function()
  config.setup({ notify = false, clipboard = { register = '"' } })
  local cfg = config.options
  local repo = h.repo()
  local source = repo .. '/sample.lua'
  h.write_file(source, { 'local value = 1', 'return value' })
  h.git(repo, { 'add', 'sample.lua' })
  h.git(repo, { 'commit', '--quiet', '-m', 'initial' })

  local loaded = assert(storage.load(repo, cfg))
  h.equal(loaded.document.schema_version, 3, 'new sessions should use schema v3')
  h.equal(loaded.document.revision, 0, 'new sessions should start at revision zero')
  h.truthy(loaded.document.session.started_from.commit, 'new sessions should capture HEAD')

  local comment = model.create_comment({
    file = 'sample.lua',
    comment = 'Keep this value configurable.',
    start_line = 1,
    end_line = 1,
    selected_lines = { 'local value = 1' },
    context_before = {},
    context_after = { 'return value' },
  })
  local unsafe_document = model.new_session()
  local unsafe_comment = vim.deepcopy(comment)
  unsafe_comment.file = 'bad\0path'
  unsafe_comment.anchor.file_anchor.created_path = unsafe_comment.file
  unsafe_comment.anchor.file_anchor.tracking.path = unsafe_comment.file
  unsafe_document.comments = { unsafe_comment }
  local unsafe_valid = model.validate(unsafe_document)
  h.equal(unsafe_valid, false, 'durable paths containing NUL bytes must be rejected')
  table.insert(loaded.document.comments, comment)
  local ok, err, token = storage.save(repo, loaded.document, cfg, loaded.token)
  h.truthy(ok, err)
  h.equal(loaded.document.revision, 1, 'first save should increment the revision')
  local current = storage.paths(repo, cfg).current
  local stable_bytes = h.read_file(current)
  local stable_updated = loaded.document.session.updated_at
  ok, err, token = storage.save(repo, loaded.document, cfg, token)
  h.truthy(ok, err)
  h.equal(h.read_file(current), stable_bytes, 'a no-op save should not rewrite current.json')
  h.equal(loaded.document.revision, 1, 'a no-op save should not increment revision')
  h.equal(
    loaded.document.session.updated_at,
    stable_updated,
    'a no-op save should preserve updated_at'
  )
  local matches, check_err, actual_token = storage.check_token(repo, cfg, token)
  h.equal(matches, true, check_err or 'the current token should match')
  h.equal(actual_token.digest, token.digest, 'token checks should return the current digest')

  local collision = storage.paths(repo, cfg).recovery .. '/collision.json'
  h.write_file(collision, { '{}' })
  h.equal(
    util.unique_path(collision),
    storage.paths(repo, cfg).recovery .. '/collision-2.json',
    'unique recovery names should retain their JSON extension'
  )

  local paths = storage.paths(repo, cfg)
  h.write_file(paths.lock, { 'test lock' })
  local busy_result, busy_err = storage.load(repo, cfg)
  h.equal(busy_result, nil, 'load must refuse while a writer lock exists')
  h.truthy(busy_err:find('busy', 1, true), 'busy load errors should be explicit')
  local busy_match, busy_check_err = storage.check_token(repo, cfg, token)
  h.equal(busy_match, nil, 'token checks must refuse while a writer lock exists')
  h.truthy(busy_check_err:find('busy', 1, true), 'busy token checks should be explicit')
  vim.fn.delete(paths.lock)

  local original_read_file = util.read_file
  util.read_file = function(path)
    local content, read_err = original_read_file(path)
    if path == paths.current then
      h.write_file(paths.lock, { 'lock created during read' })
    end
    return content, read_err
  end
  local raced_result, raced_err = storage.load(repo, cfg)
  util.read_file = original_read_file
  h.equal(raced_result, nil, 'load must detect a lock created while current.json is read')
  h.truthy(raced_err:find('busy', 1, true), 'post-read lock errors should be explicit')
  vim.fn.delete(paths.lock)

  local writer_a = assert(storage.load(repo, cfg))
  local writer_b = assert(storage.load(repo, cfg))
  model.set_comment_text(writer_a.document.comments[1], 'Writer A wins.')
  local a_ok, a_err = storage.save(repo, writer_a.document, cfg, writer_a.token)
  h.truthy(a_ok, a_err)
  local stale_match = storage.check_token(repo, cfg, writer_b.token)
  h.equal(stale_match, false, 'token checks should detect another writer')
  model.set_comment_text(writer_b.document.comments[1], 'Writer B is preserved separately.')
  local b_ok, b_err = storage.save(repo, writer_b.document, cfg, writer_b.token)
  h.equal(b_ok, false, 'a stale writer must not overwrite newer state')
  h.truthy(b_err:find('preserved', 1, true), 'conflict error should identify preservation')
  h.equal(h.read_json(current).comments[1].comment, 'Writer A wins.', 'newer state must survive')
  h.truthy(
    #vim.fn.glob(storage.paths(repo, cfg).recovery .. '/conflict-*.json', false, true) == 1,
    'a conflict snapshot should be written'
  )

  local migration_repo = h.repo()
  local migration_paths = storage.paths(migration_repo, cfg)
  vim.fn.mkdir(migration_paths.base, 'p')
  local v1 = {
    schema_version = 1,
    session = { id = 'session_old', created_at = 'old', updated_at = 'old' },
    comments = {
      {
        id = 'comment_old',
        file = 'sample.lua',
        comment = 'Historical note',
        created_at = 'old',
        anchor = {
          kind = 'line_range',
          start_line = 1,
          end_line = 1,
          start_column = 0,
          end_column = 0,
          original_text = 'old',
          original_text_sha256 = vim.fn.sha256('old'),
          current_text = 'old',
          original_context_before = {},
          original_context_after = {},
          current_context_before = {},
          current_context_after = {},
          valid = true,
          stale = false,
          view = 'left',
        },
      },
    },
  }
  h.write_file(migration_paths.current, { vim.json.encode(v1) })
  local v1_bytes = h.read_file(migration_paths.current)
  local migrated = assert(storage.load(migration_repo, cfg))
  h.equal(migrated.migration, { from = 1, to = 3 }, 'v1 should migrate in memory')
  h.equal(
    migrated.document.comments[1].anchor.source,
    { kind = 'snapshot', side = 'left' },
    'migration should retain historical-side identity'
  )
  local migrated_ok, migrated_err =
    storage.save(migration_repo, migrated.document, cfg, migrated.token)
  h.truthy(migrated_ok, migrated_err)
  local backups = vim.fn.glob(migration_paths.recovery .. '/pre-migration-v1-*.json', false, true)
  h.equal(#backups, 1, 'migration should preserve the old file')
  h.equal(h.read_file(backups[1]), v1_bytes, 'migration backup should preserve exact bytes')

  local v2_repo = h.repo()
  local v2_paths = storage.paths(v2_repo, cfg)
  local v2_comment = model.create_comment({
    file = 'sample.lua',
    comment = 'Migrate the line anchor.',
    start_line = 1,
    end_line = 1,
    selected_lines = { 'old' },
  })
  for _, key in ipairs({
    'mode',
    'current_text_sha256',
    'original_prefix',
    'original_suffix',
    'current_prefix',
    'current_suffix',
    'current_file_sha256',
    'resolution_method',
    'file_anchor',
  }) do
    v2_comment.anchor[key] = nil
  end
  local v2 = {
    schema_version = 2,
    revision = 4,
    session = {
      id = 'session_v2',
      created_at = 'old',
      updated_at = 'old',
      started_from = vim.empty_dict(),
    },
    comments = { v2_comment },
  }
  h.write_file(v2_paths.current, { vim.json.encode(v2) })
  local v2_loaded = assert(storage.load(v2_repo, cfg))
  h.equal(v2_loaded.migration, { from = 2, to = 3 }, 'v2 should migrate in memory')
  h.equal(v2_loaded.document.session.scope, { kind = 'unscoped' }, 'v2 gains explicit scope')
  h.equal(v2_loaded.document.comments[1].anchor.mode, 'line', 'v2 zero columns stay linewise')
  h.equal(
    v2_loaded.document.comments[1].anchor.file_anchor.tracking.path,
    'sample.lua',
    'v2 worktree comments gain durable path identity'
  )

  local corrupt_repo = h.repo()
  local corrupt_paths = storage.paths(corrupt_repo, cfg)
  h.write_file(corrupt_paths.current, { '{ definitely not JSON' })
  local recovered = assert(storage.load(corrupt_repo, cfg))
  h.truthy(recovered.recovered_from, 'corrupt state should be quarantined')
  h.equal(
    h.read_file(recovered.recovered_from),
    '{ definitely not JSON\n',
    'corruption recovery should preserve exact bytes'
  )
  h.equal(vim.uv.fs_stat(corrupt_paths.current), nil, 'corrupt current state should be moved')

  local future_repo = h.repo()
  local future_paths = storage.paths(future_repo, cfg)
  local future = '{"schema_version":999}\n'
  h.write_file(future_paths.current, { '{"schema_version":999}' })
  local future_result, future_err = storage.load(future_repo, cfg)
  h.equal(future_result, nil, 'future schemas should be refused')
  h.truthy(future_err:find('future', 1, true), 'future-schema error should be explicit')
  h.equal(h.read_file(future_paths.current), future, 'future schemas must remain untouched')

  local failure_repo = h.repo()
  local failure_cfg = vim.deepcopy(cfg)
  failure_cfg.storage.add_to_git_exclude = false
  local failure_paths = storage.paths(failure_repo, failure_cfg)
  local failure = assert(storage.load(failure_repo, failure_cfg))
  table.insert(
    failure.document.comments,
    model.create_comment({
      file = 'sample.lua',
      comment = 'Must remain in memory after an injected failure.',
      start_line = 1,
      end_line = 1,
      selected_lines = { 'return true' },
    })
  )

  local before_encode_failure = vim.deepcopy(failure.document)
  local original_encode_json = util.encode_json
  util.encode_json = function()
    error('injected encode failure')
  end
  local encoded_ok, encoded_err =
    storage.save(failure_repo, failure.document, failure_cfg, failure.token)
  util.encode_json = original_encode_json
  h.equal(encoded_ok, false, 'a thrown encoder must fail the save')
  h.truthy(encoded_err:find('injected encode failure', 1, true), 'encoder error should survive')
  h.equal(
    failure.document,
    before_encode_failure,
    'an encoder exception must not mutate the live document'
  )
  h.equal(vim.uv.fs_stat(failure_paths.lock), nil, 'encoder exceptions must release the lock')

  local before_write_failure = vim.deepcopy(failure.document)
  local original_write_atomic = util.write_atomic
  util.write_atomic = function()
    error('injected write failure')
  end
  local written_ok, written_err =
    storage.save(failure_repo, failure.document, failure_cfg, failure.token)
  util.write_atomic = original_write_atomic
  h.equal(written_ok, false, 'a thrown writer must fail the save')
  h.truthy(written_err:find('injected write failure', 1, true), 'writer error should survive')
  h.equal(
    failure.document,
    before_write_failure,
    'a writer exception must not mutate the live document'
  )
  h.equal(vim.uv.fs_stat(failure_paths.lock), nil, 'writer exceptions must release the lock')
  local recovery_ok, recovery_err =
    storage.save(failure_repo, failure.document, failure_cfg, failure.token)
  h.truthy(recovery_ok, recovery_err)

  vim.fn.delete(repo, 'rf')
  vim.fn.delete(migration_repo, 'rf')
  vim.fn.delete(v2_repo, 'rf')
  vim.fn.delete(corrupt_repo, 'rf')
  vim.fn.delete(future_repo, 'rf')
  vim.fn.delete(failure_repo, 'rf')
end)
