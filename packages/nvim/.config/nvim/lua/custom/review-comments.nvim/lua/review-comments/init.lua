local config_module = require('review_comments.config')
local anchor_matcher = require('review_comments.anchor')
local editor = require('review_comments.editor')
local exporter = require('review_comments.exporter')
local review_git = require('review_comments.git')
local marks = require('review_comments.marks')
local model = require('review_comments.model')
local quickfix = require('review_comments.quickfix')
local state = require('review_comments.state')
local storage = require('review_comments.storage')
local util = require('review_comments.util')

local M = {}

local initialized = false
local augroup
local pending_restores = {}
local setup_generation = 0
local line_context

local function config()
  return config_module.options
end

local function emit(pattern, data)
  pcall(vim.api.nvim_exec_autocmds, 'User', {
    pattern = pattern,
    modeline = false,
    data = data,
  })
end

local function refresh_projection(root, document)
  local _, err = quickfix.refresh(root, document, config())
  if err then
    util.notify(config(), err, vim.log.levels.WARN)
  end
end

local function contexts_from_lines(lines, start_line, end_line)
  local count = config().context_lines
  local before = {}
  for line = math.max(1, start_line - count), start_line - 1 do
    before[#before + 1] = lines[line]
  end
  local after = {}
  for line = end_line + 1, math.min(#lines, end_line + count) do
    after[#after + 1] = lines[line]
  end
  return before, after
end

local function apply_anchor_result(comment, result, lines)
  local anchor = comment.anchor
  local changed = false
  for _, key in ipairs({
    'start_line',
    'end_line',
    'start_column',
    'end_column',
    'valid',
    'stale',
    'failure_reason',
    'resolution_method',
    'current_file_sha256',
  }) do
    local result_key = key == 'resolution_method' and 'method'
      or (key == 'current_file_sha256' and 'file_sha256' or key)
    if
      result_key ~= 'file_sha256'
      or (result.valid and not result.stale and result[result_key] ~= nil)
    then
      if anchor[key] ~= result[result_key] then
        anchor[key] = result[result_key]
        changed = true
      end
    end
  end
  if result.valid and not result.stale and type(result.current_text) == 'string' then
    local before, after = contexts_from_lines(lines, result.start_line, result.end_line)
    local updates = {
      current_text = result.current_text,
      current_text_sha256 = util.sha256(result.current_text),
      current_prefix = result.current_prefix or '',
      current_suffix = result.current_suffix or '',
    }
    for key, value in pairs(updates) do
      if anchor[key] ~= value then
        anchor[key] = value
        changed = true
      end
    end
    if not vim.deep_equal(anchor.current_context_before, before) then
      anchor.current_context_before = before
      changed = true
    end
    if not vim.deep_equal(anchor.current_context_after, after) then
      anchor.current_context_after = after
      changed = true
    end
  end
  return changed
end

local function loaded_buffer_for(path)
  local wanted = util.normalize(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(bufnr)
      and util.normalize(vim.api.nvim_buf_get_name(bufnr)) == wanted
    then
      return bufnr
    end
  end
  return nil
end

local function file_lines(root, file)
  if not util.is_safe_relative(file) then
    return nil, 'unsafe path'
  end
  local path = util.join(root, file)
  if not util.is_within(root, path) then
    return nil, 'path escaped repository'
  end
  local bufnr = loaded_buffer_for(path)
  if bufnr and vim.bo[bufnr].modified then
    -- A CLI may rename/delete the path while this buffer still contains
    -- unsaved manual work. Treat that buffer as authoritative until the user
    -- writes or discards it; otherwise reconciliation can move the durable
    -- comment to the on-disk destination and detach its live extmark.
    return nil, 'modified buffer', bufnr
  end
  local stat = (vim.uv or vim.loop).fs_stat(path)
  if not stat or stat.type ~= 'file' then
    return nil, 'missing'
  end
  if stat.size > config().relocation.max_file_bytes then
    return nil, 'file exceeds relocation.max_file_bytes'
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, tostring(lines)
  end
  if bufnr then
    local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if not vim.deep_equal(buffer_lines, lines) then
      -- Reconcile the durable disk bytes immediately, but leave Neovim's
      -- unmodified buffer alone. This preserves normal autoread/checktime UX
      -- and avoids throwing away cursor/undo state while still surfacing agent
      -- edits in note health at the next plugin boundary.
      return lines, nil, nil
    end
    return buffer_lines, nil, bufnr
  end
  return lines
end

local function record_path_change(comment, from, to, method, score)
  if from == to then
    return false
  end
  comment.file = to
  local file_anchor = comment.anchor.file_anchor
    or {
      created_path = from,
      tracking = { path = from },
    }
  comment.anchor.file_anchor = file_anchor
  file_anchor.history = file_anchor.history or {}
  file_anchor.history[#file_anchor.history + 1] = {
    from = from,
    to = to,
    method = method,
    score = score,
    at = util.timestamp(),
  }
  return true
end

local function orphan_result(comment, reason, method)
  local anchor = comment.anchor
  return {
    start_line = anchor.start_line,
    end_line = anchor.end_line,
    start_column = anchor.start_column,
    end_column = anchor.end_column,
    valid = false,
    stale = true,
    method = method or 'file_missing',
    failure_reason = reason,
  }
end

local function reconcile_document(root, document, opts)
  opts = opts or {}
  if config().relocation.enabled == false then
    return false, {}
  end
  local changed = false
  local changed_ids = {}
  local rename_maps = {}
  local candidates
  local content_cache = {}

  local function content(file)
    if content_cache[file] == nil then
      local lines, err, bufnr = file_lines(root, file)
      content_cache[file] = { lines = lines, err = err, bufnr = bufnr }
    end
    return content_cache[file]
  end

  local function apply(comment, result, lines)
    if apply_anchor_result(comment, result, lines or {}) then
      changed = true
      changed_ids[comment.id] = true
    end
  end

  local function rename_for(comment)
    if config().relocation.git_renames == false then
      return nil
    end
    local file_anchor = comment.anchor.file_anchor
    local tracking = file_anchor and file_anchor.tracking or nil
    if not tracking or not tracking.commit or not tracking.path then
      return nil
    end
    if rename_maps[tracking.commit] == nil then
      local map, err = review_git.rename_map(root, tracking.commit)
      rename_maps[tracking.commit] = { map = map or false, err = err }
    end
    local cached = rename_maps[tracking.commit]
    return cached.map and cached.map[tracking.path] or nil
  end

  local function search_files(comment, excluded)
    if config().relocation.file_search == false then
      return nil
    end
    if candidates == nil then
      local files = review_git.files(root)
      candidates = files or false
    end
    if not candidates or #candidates > config().relocation.max_candidate_files then
      return nil
    end
    local matches = {}
    for _, file in ipairs(candidates) do
      if file ~= excluded and file ~= comment.file then
        local candidate_content = content(file)
        if candidate_content.lines then
          local result = anchor_matcher.reconcile(candidate_content.lines, comment.anchor, config())
          if result.valid then
            matches[#matches + 1] =
              { file = file, result = result, lines = candidate_content.lines }
            if #matches > 1 then
              return nil, 'Several repository files plausibly match this review'
            end
          end
        end
      end
    end
    return matches[1]
  end

  for _, comment in ipairs(document.comments) do
    if
      comment.anchor.source
      and comment.anchor.source.kind == 'worktree'
      and (
        not opts.only_file
        or comment.file == opts.only_file
        or (
          opts.include_missing
          and not (vim.uv or vim.loop).fs_stat(util.join(root, comment.file))
        )
      )
    then
      local current = content(comment.file)
      if current.err == 'modified buffer' then
        goto continue
      end
      local direct_result = current.lines
          and anchor_matcher.reconcile(current.lines, comment.anchor, config())
        or nil
      if direct_result and direct_result.valid then
        apply(comment, direct_result, current.lines)
      else
        local recovered
        local rename = rename_for(comment)
        if rename and util.is_safe_relative(rename.new) then
          local renamed = content(rename.new)
          if renamed.err == 'modified buffer' then
            -- Git identifies the destination, but its loaded contents are not
            -- yet durable. Defer both path mutation and orphaning until the
            -- user writes or discards the destination buffer.
            goto continue
          end
          if renamed.lines then
            local result = anchor_matcher.reconcile(renamed.lines, comment.anchor, config())
            local old_file = comment.file
            if record_path_change(comment, old_file, rename.new, 'git_rename', rename.score) then
              changed = true
              changed_ids[comment.id] = true
            end
            if not result.valid then
              result.failure_reason = string.format(
                'Git renamed %s to %s, but %s',
                old_file,
                rename.new,
                (result.failure_reason or 'the reviewed text could not be located'):lower()
              )
            end
            apply(comment, result, renamed.lines)
            recovered = true
          end
        end
        if not recovered then
          local match, search_err
          if current.err == 'missing' then
            match, search_err = search_files(comment, comment.file)
          end
          if match then
            local old_file = comment.file
            if record_path_change(comment, old_file, match.file, 'content_search') then
              changed = true
              changed_ids[comment.id] = true
            end
            local tracking = review_git.current_tracking(root, match.file)
            if tracking then
              comment.anchor.file_anchor.tracking = tracking
            end
            apply(comment, match.result, match.lines)
          else
            local reason = search_err
              or (
                current.err == 'missing'
                  and 'Reviewed file is missing and no unique moved destination was found'
                or (direct_result and direct_result.failure_reason)
                or 'Could not inspect the reviewed file'
              )
            apply(comment, orphan_result(comment, reason), current.lines or {})
          end
        end
      end
    end
    ::continue::
  end
  return changed, changed_ids
end

local function restore_marks(root, document, skip_ids)
  marks.clear_root(root)
  local restorable = document
  if skip_ids and next(skip_ids) ~= nil then
    restorable = { comments = {} }
    for _, comment in ipairs(document.comments) do
      if not skip_ids[comment.id] then
        restorable.comments[#restorable.comments + 1] = comment
      end
    end
  end
  local changed = false
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_is_loaded(bufnr)
      and vim.api.nvim_buf_get_name(bufnr) ~= ''
      and vim.bo[bufnr].buftype ~= 'quickfix'
    then
      local target = util.resolve_target(bufnr, config())
      if target and target.root == root then
        changed = marks.restore_buffer(root, restorable, bufnr, target, config()) or changed
      end
    end
  end
  return changed
end

local function restore_loaded_document(root, document)
  -- Install live marks before disk reconciliation. This preserves an explicit
  -- manual relocation in the newly loaded document; reconciliation then only
  -- evaluates comments that do not already have a trusted live projection.
  local changed = restore_marks(root, document)
  local reconciled = reconcile_document(root, document, { skip_trusted_live = true })
  changed = reconciled or changed
  if changed then
    state.mark_dirty(root)
  end
  refresh_projection(root, document)
  return changed
end

local function install_loaded_document(root, result, action)
  local previous = state.get(root)
  local previous_session = previous and previous.session and previous.session.id or nil
  local next_session = result.document.session and result.document.session.id or nil
  if previous_session and previous_session ~= next_session then
    quickfix.clear(root)
  end
  state.set(root, result.document, result.token, { dirty = result.migration ~= nil })
  restore_loaded_document(root, result.document)
  if action then
    emit('ReviewCommentsChanged', { root = root, action = action })
  end
  return result.document
end

local function load_session(root, opts)
  opts = opts or {}
  local existing = state.get(root)
  if existing then
    if opts.check_disk ~= false then
      local matches, check_err = storage.check_token(root, config(), state.token(root))
      if matches == nil then
        util.notify(config(), check_err, vim.log.levels.ERROR)
        return nil, check_err
      end
      if not matches then
        if state.is_dirty(root) then
          local err =
            'Review state changed on disk while local anchor changes are pending; use :ReviewReload! to discard the pending local state'
          util.notify(config(), err, vim.log.levels.ERROR)
          return nil, err
        end
        local result, reload_err = storage.load(root, config())
        if not result then
          util.notify(config(), reload_err, vim.log.levels.ERROR)
          return nil, reload_err
        end
        local document = install_loaded_document(root, result, 'reloaded')
        util.notify(config(), 'Reloaded review state changed by another Neovim process')
        return document
      end
    end
    state.activate(root)
    return existing
  end

  local result, err = storage.load(root, config())
  if not result then
    util.notify(config(), err, vim.log.levels.ERROR)
    return nil, err
  end
  install_loaded_document(root, result)
  if result.recovered_from then
    util.notify(
      config(),
      string.format(
        'Invalid review state was preserved at %s; started a new session (%s)',
        util.relative_path(root, result.recovered_from) or result.recovered_from,
        result.recovery_reason or 'invalid data'
      ),
      vim.log.levels.WARN
    )
  elseif result.migration then
    util.notify(
      config(),
      string.format(
        'Loaded review schema v%d; it will be safely migrated to v%d on the next save',
        result.migration.from,
        result.migration.to
      )
    )
  end
  return result.document
end

local function target_for_buffer(bufnr, quiet)
  local target, err = util.resolve_target(bufnr, config())
  if not target and not quiet then
    util.notify(config(), err, vim.log.levels.ERROR)
  end
  if target then
    state.activate(target.root)
  end
  return target, err
end

local function tracking_for_target(target)
  if not target.source or target.source.kind ~= 'worktree' then
    return nil
  end
  local document = state.get(target.root)
  local scope = document and document.session and document.session.scope or nil
  if scope and scope.kind == 'git_diff' and scope.base and scope.base.commit then
    local renames = review_git.rename_map(target.root, scope.base.commit)
    if renames then
      local previous
      local matches = 0
      for old_path, rename in pairs(renames) do
        if rename.new == target.file then
          previous = old_path
          matches = matches + 1
        end
      end
      if matches == 1 then
        return { path = previous, commit = scope.base.commit }
      end
    end
  end
  local tracking, err = review_git.current_tracking(target.root, target.file)
  if not tracking then
    util.notify(
      config(),
      'Could not capture Git path identity; rename recovery will be limited: ' .. tostring(err),
      vim.log.levels.WARN
    )
    return { path = target.file }
  end
  return tracking
end

local function root_for_command()
  local list_root = quickfix.current_review_root()
  if list_root then
    state.activate(list_root)
    return list_root
  end
  local target = target_for_buffer(0, true)
  if target then
    return target.root
  end
  if state.active_root then
    return state.active_root
  end
  return util.git_root(vim.fn.getcwd())
end

local function public_root(root)
  if root == nil then
    return root_for_command()
  end
  if type(root) ~= 'string' or root == '' then
    return nil
  end
  -- Public callers may spell the same worktree with a trailing slash or a
  -- symlink. Resolve through Git before using the path as an in-memory key so
  -- one repository cannot acquire multiple sessions, locks, or projections.
  return util.git_root(root)
end

local function save_session(root, document, opts)
  opts = opts or {}
  if opts.changed then
    state.mark_dirty(root)
  end
  if not state.is_dirty(root) and not opts.force then
    return true
  end

  local ok, err, token = storage.save(root, document, config(), state.token(root))
  if not ok then
    state.mark_dirty(root)
    util.notify(config(), 'Could not save review state: ' .. tostring(err), vim.log.levels.ERROR)
    return false, err
  end
  state.mark_clean(root, token)
  return true
end

local function sync_and_save(root, opts)
  opts = opts or {}
  local document = state.get(root)
  if not document then
    return true
  end
  local before = vim.deepcopy(document)
  local was_dirty = state.is_dirty(root)
  local disk_mismatches = {}
  local buffer_mismatches = {}
  for _, comment in ipairs(document.comments) do
    local entry = marks.get(comment.id, root)
    if
      entry
      and not vim.bo[entry.bufnr].modified
      and comment.anchor.source
      and comment.anchor.source.kind == 'worktree'
    then
      if buffer_mismatches[entry.bufnr] == nil then
        local path = util.join(root, comment.file)
        local ok, disk_lines = pcall(vim.fn.readfile, path)
        buffer_mismatches[entry.bufnr] = ok
          and not vim.deep_equal(disk_lines, vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false))
      end
      if buffer_mismatches[entry.bufnr] then
        disk_mismatches[comment.id] = true
      end
    end
  end
  local changed = marks.sync_root(root, document, config(), opts)
  for id in pairs(disk_mismatches) do
    marks.detach(root, id)
  end
  local reconciled = reconcile_document(root, document)
  if reconciled then
    -- Reconciliation changed only durable anchor metadata. Recreate marks
    -- without feeding a pre-reconciliation live mark back into that model.
    marks.clear_root(root)
    changed = restore_marks(root, document, disk_mismatches) or true
  elseif next(disk_mismatches) ~= nil then
    -- Even if the durable metadata happened to compare equal, do not restore a
    -- detached disk-mismatch mark from stale in-memory buffer contents.
    changed = true
  end
  local ok, err = save_session(root, document, { changed = changed })
  if not ok and changed and not was_dirty then
    -- Anchor synchronization is an internal preflight. If its persistence
    -- fails, roll it back completely so a later external writer can still be
    -- reloaded and the attempted user mutation cannot strand a false dirty
    -- session.
    state.set(root, before, state.token(root))
    restore_marks(root, before)
    refresh_projection(root, before)
  end
  if ok and changed then
    refresh_projection(root, document)
  end
  return ok, err, changed
end

local function file_sha256(bufnr)
  return util.sha256(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n'))
end

line_context = function(bufnr, start_line, end_line)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local context_count = config().context_lines
  local before = vim.api.nvim_buf_get_lines(
    bufnr,
    math.max(0, start_line - 1 - context_count),
    start_line - 1,
    false
  )
  local after = vim.api.nvim_buf_get_lines(
    bufnr,
    math.min(line_count, end_line),
    math.min(line_count, end_line + context_count),
    false
  )
  return before, after
end

local function normalized_visual_positions(bufnr)
  local first = vim.fn.getpos("'<")
  local last = vim.fn.getpos("'>")
  local first_buf = first[1] == 0 and bufnr or first[1]
  local last_buf = last[1] == 0 and bufnr or last[1]
  if first_buf ~= bufnr or last_buf ~= bufnr or first[2] < 1 or last[2] < 1 then
    return nil, nil, 'The visual selection no longer belongs to this buffer'
  end
  if first[2] > last[2] or (first[2] == last[2] and first[3] > last[3]) then
    first, last = last, first
  end
  return first, last
end

local function capture_range(bufnr, params)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_line = math.max(1, math.min(params.line1 or vim.fn.line('.'), line_count))
  local end_line = math.max(1, math.min(params.line2 or start_line, line_count))
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local mode = (params.mode == 'char' or params.selection_type == 'v') and 'char' or 'line'
  if params.selection_type == '\22' or params.mode == 'block' then
    return nil, 'Blockwise review ranges are not supported'
  end

  local start_column = 0
  local end_column = 0
  local selected
  local selected_text
  local prefix = ''
  local suffix = ''
  if mode == 'char' then
    if params.start_column ~= nil and params.end_column ~= nil then
      start_column = params.start_column
      end_column = params.end_column
      local ok, value = pcall(
        vim.api.nvim_buf_get_text,
        bufnr,
        start_line - 1,
        start_column,
        end_line - 1,
        end_column,
        {}
      )
      if not ok or #value == 0 then
        return nil, 'The exact review range is invalid'
      end
      selected = value
    else
      local first, last, position_err = normalized_visual_positions(bufnr)
      if not first then
        return nil, position_err
      end
      start_line = first[2]
      end_line = last[2]
      start_column = math.max(0, first[3] - 1)
      local ok, value = pcall(vim.fn.getregion, first, last, {
        type = 'v',
        exclusive = false,
      })
      if not ok or type(value) ~= 'table' or #value == 0 then
        return nil, 'Could not read the visual review range'
      end
      selected = value
      end_column = start_line == end_line and start_column + #selected[1] or #selected[#selected]
    end
    if start_line == end_line and end_column <= start_column then
      return nil, 'The exact review range is empty'
    end
    local first_line = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, start_line, false)[1] or ''
    local last_line = vim.api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)[1] or ''
    prefix = first_line:sub(1, start_column)
    suffix = last_line:sub(end_column + 1)
    selected_text = table.concat(selected, '\n')
  else
    selected = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
    selected_text = table.concat(selected, '\n')
  end

  local before, after = line_context(bufnr, start_line, end_line)
  return {
    mode = mode,
    start_line = start_line,
    end_line = end_line,
    start_column = start_column,
    end_column = end_column,
    selected = selected,
    selected_text = selected_text,
    prefix = prefix,
    suffix = suffix,
    before = before,
    after = after,
    file_sha256 = file_sha256(bufnr),
  }
end

local function finish_change(root, candidate, action, comment_id)
  refresh_projection(root, candidate)
  emit('ReviewCommentsChanged', { root = root, action = action, comment_id = comment_id })
end

local function commit_candidate(root, candidate)
  local ok, err, token = storage.save(root, candidate, config(), state.token(root))
  if not ok then
    util.notify(config(), 'Could not save review state: ' .. tostring(err), vim.log.levels.ERROR)
    return nil, err
  end
  state.set(root, candidate, token)
  return candidate
end

local function create_comment(captured, text, opts)
  opts = opts or {}
  local function fail(message, level)
    if opts.notify_errors ~= false then
      util.notify(config(), message, level or vim.log.levels.ERROR)
    end
    return nil, message
  end
  text = vim.trim(text or '')
  if text == '' then
    return fail('Review comment text cannot be empty', vim.log.levels.WARN)
  end
  if not vim.api.nvim_buf_is_valid(captured.bufnr) then
    return fail('The reviewed buffer was closed before the comment was saved')
  end
  if vim.api.nvim_buf_get_changedtick(captured.bufnr) ~= captured.changedtick then
    return fail(
      'The reviewed buffer changed while the comment editor was open; select the range again',
      vim.log.levels.WARN
    )
  end

  local document, load_err = load_session(captured.target.root)
  if not document then
    return nil, load_err
  end
  if captured.session_id and document.session.id ~= captured.session_id then
    return fail(
      'The review session changed while the comment editor was open; select the range again',
      vim.log.levels.WARN
    )
  end
  if not sync_and_save(captured.target.root) then
    return nil, 'Could not synchronize review state before adding the comment'
  end
  document = state.get(captured.target.root)
  local candidate = vim.deepcopy(document)
  local comment = model.create_comment({
    file = captured.target.file,
    view = captured.target.view,
    source = captured.target.source,
    comment = text,
    mode = captured.mode,
    start_line = captured.start_line,
    end_line = captured.end_line,
    start_column = captured.start_column,
    end_column = captured.end_column,
    selected_lines = captured.selected,
    selected_text = captured.selected_text,
    prefix = captured.prefix,
    suffix = captured.suffix,
    file_sha256 = captured.file_sha256,
    tracking = tracking_for_target(captured.target) or captured.tracking,
    context_before = captured.before,
    context_after = captured.after,
  })
  table.insert(candidate.comments, comment)
  if not commit_candidate(captured.target.root, candidate) then
    return nil, 'Could not persist the review comment'
  end

  local _, mark_err, anchor_changed =
    marks.attach(captured.target.root, comment, captured.bufnr, captured.target, config())
  if anchor_changed then
    save_session(captured.target.root, candidate, { changed = true })
  end
  if mark_err then
    util.notify(
      config(),
      'Comment saved, but its extmark could not be created: ' .. mark_err,
      vim.log.levels.WARN
    )
  end
  finish_change(captured.target.root, candidate, 'added', comment.id)
  util.notify(
    config(),
    string.format(
      'Review comment added at %s:%d-%d',
      comment.file,
      captured.start_line,
      captured.end_line
    )
  )
  return comment
end

--- Add a review comment.
--- @param params? {bufnr?: integer, line1?: integer, line2?: integer, mode?: 'line'|'char', start_column?: integer, end_column?: integer, selection_type?: string, text?: string}
function M.add_comment(params)
  M.ensure_setup()
  params = params or {}
  local bufnr = params.bufnr or vim.api.nvim_get_current_buf()
  local target, target_err = target_for_buffer(bufnr)
  if not target then
    return nil, target_err
  end

  local range, range_err = capture_range(bufnr, params)
  if not range then
    util.notify(config(), range_err, vim.log.levels.WARN)
    return nil, range_err
  end
  local captured = {
    bufnr = bufnr,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    target = target,
  }
  for key, value in pairs(range) do
    captured[key] = value
  end
  if params.text ~= nil then
    captured.tracking = tracking_for_target(target)
    return create_comment(captured, params.text)
  end
  local document, load_err = load_session(target.root)
  if not document then
    return nil, load_err
  end
  captured.session_id = document.session.id
  captured.tracking = tracking_for_target(target)
  local handle, editor_err = editor.open({
    title = string.format('Review comment — %s:%d', target.file, captured.start_line),
    initial_text = '',
    start_insert = config().editor.start_insert,
    spell = config().editor.spell,
    window = config().editor.window,
    notify = function(message, level)
      util.notify(config(), message, level)
    end,
    on_submit = function(input)
      local comment, err = create_comment(captured, input, { notify_errors = false })
      return comment ~= nil, err
    end,
  })
  if not handle then
    util.notify(config(), editor_err, vim.log.levels.ERROR)
    return nil, editor_err
  end
  return handle
end

local function selected_reference(params)
  params = params or {}
  if params.root ~= nil and params.id then
    local root = public_root(params.root)
    if not root then
      return nil, nil, 'The explicit review root is not a Git repository'
    end
    return root, params.id
  end

  if not params.id then
    local selection = quickfix.selected_comment(params.bufnr)
    if selection then
      return selection.root, selection.id
    end
  end

  local bufnr = params.bufnr or vim.api.nvim_get_current_buf()
  local target = target_for_buffer(bufnr, true)
  local root
  if params.root ~= nil then
    root = public_root(params.root)
    if not root then
      return nil, nil, 'The explicit review root is not a Git repository'
    end
  else
    root = (target and target.root) or root_for_command()
  end
  if not root then
    return nil, nil, 'No active Git repository for review comments'
  end
  if params.id then
    return root, params.id
  end
  if target then
    local ids = marks.comments_at(root, bufnr, params.line or vim.api.nvim_win_get_cursor(0)[1])
    if #ids == 1 then
      return root, ids[1]
    end
    if #ids > 1 then
      return nil, nil, 'Several review comments overlap here; select one in :ReviewList'
    end
  end
  return nil, nil, 'No review comment is selected'
end

local function resolve_comment(params)
  local root, id, ref_err = selected_reference(params)
  if not root then
    return nil, nil, nil, ref_err
  end
  local document, load_err = load_session(root)
  if not document then
    return nil, nil, nil, load_err
  end
  local _, sync_err = sync_and_save(root)
  if sync_err then
    return nil, nil, nil, sync_err
  end
  document = state.get(root)
  local index, comment = model.find_index(document, id)
  if not index then
    return nil, nil, nil, 'The selected review comment no longer exists'
  end
  return root, document, comment
end

local function mutate_comment(params, action, mutator, side_effect)
  local root, document, current, err = resolve_comment(params)
  if not root then
    util.notify(config(), err, vim.log.levels.WARN)
    return nil, err
  end
  local candidate = vim.deepcopy(document)
  local index, comment = model.find_index(candidate, current.id)
  local changed, mutation_err = mutator(comment, candidate, index)
  if not changed then
    if mutation_err then
      util.notify(config(), mutation_err, vim.log.levels.WARN)
    end
    return comment, mutation_err
  end
  if not commit_candidate(root, candidate) then
    return nil, 'Could not persist the review change'
  end
  local updated = model.find(candidate, current.id)
  if side_effect then
    side_effect(root, current, updated, candidate)
  end
  finish_change(root, candidate, action, current.id)
  return updated or true
end

function M.edit_comment(params)
  M.ensure_setup()
  params = params or {}
  if params.text ~= nil then
    return mutate_comment(params, 'edited', function(comment)
      if
        params.expected_text ~= nil
        and (
          comment.comment ~= params.expected_text
          or comment.updated_at ~= params.expected_updated_at
        )
      then
        return false, 'The review comment changed while its editor was open'
      end
      return model.set_comment_text(comment, params.text)
    end)
  end

  local root, _, comment, err = resolve_comment(params)
  if not root then
    util.notify(config(), err, vim.log.levels.WARN)
    return nil, err
  end
  local captured = { text = comment.comment, updated_at = comment.updated_at }
  local handle, editor_err = editor.open({
    title = string.format('Edit review — %s:%d', comment.file, comment.anchor.start_line),
    initial_text = comment.comment,
    start_insert = config().editor.start_insert,
    spell = config().editor.spell,
    window = config().editor.window,
    notify = function(message, level)
      util.notify(config(), message, level)
    end,
    on_submit = function(input)
      -- M.edit_comment reloads/checks durable state before the mutator runs.
      -- Keep the optimistic check there rather than consulting possibly stale
      -- in-memory state captured when this editor was opened.
      local updated, update_err = M.edit_comment({
        root = root,
        id = comment.id,
        text = input,
        expected_text = captured.text,
        expected_updated_at = captured.updated_at,
      })
      return updated ~= nil and update_err == nil, update_err
    end,
  })
  if not handle then
    util.notify(config(), editor_err, vim.log.levels.ERROR)
    return nil, editor_err
  end
  return handle
end

local function delete_now(root, id)
  return mutate_comment({ root = root, id = id }, 'deleted', function(_, candidate, index)
    table.remove(candidate.comments, index)
    return true
  end, function(committed_root, old)
    marks.detach(committed_root, old.id)
  end)
end

function M.delete_comment(params)
  M.ensure_setup()
  params = params or {}
  local root, _, comment, err = resolve_comment(params)
  if not root then
    util.notify(config(), err, vim.log.levels.WARN)
    return nil, err
  end
  if params.force then
    return delete_now(root, comment.id)
  end
  vim.ui.select({ 'Delete', 'Cancel' }, {
    prompt = string.format(
      'Delete review comment at %s:%d?',
      comment.file,
      comment.anchor.start_line
    ),
  }, function(choice)
    if choice == 'Delete' then
      delete_now(root, comment.id)
    end
  end)
  return nil
end

function M.resolve_review(params)
  M.ensure_setup()
  return mutate_comment(params or {}, 'resolved', function(comment)
    return model.set_status(comment, 'resolved')
  end, function(root, _, updated)
    marks.restyle(root, updated)
  end)
end

function M.reopen_review(params)
  M.ensure_setup()
  return mutate_comment(params or {}, 'reopened', function(comment)
    return model.set_status(comment, 'active')
  end, function(root, _, updated)
    marks.restyle(root, updated)
  end)
end

local function relocation_id(root, params, document)
  if params.id and params.id ~= '' then
    return params.id
  end
  local candidates = {}
  for _, comment in ipairs(document.comments) do
    if comment.anchor.stale or comment.anchor.valid == false then
      table.insert(candidates, comment.id)
    end
  end
  if #candidates == 1 then
    return candidates[1]
  end
  return nil,
    #candidates == 0 and 'There are no stale comments to relocate'
      or 'Several comments need relocation; pass a comment ID from :ReviewList'
end

function M.relocate_comment(params)
  M.ensure_setup()
  params = params or {}
  local bufnr = params.bufnr or vim.api.nvim_get_current_buf()
  local target, target_err = target_for_buffer(bufnr)
  if not target then
    return nil, target_err
  end
  local document = load_session(target.root)
  if not document then
    return nil
  end
  local id, id_err = relocation_id(target.root, params, document)
  if not id then
    util.notify(config(), id_err, vim.log.levels.WARN)
    return nil, id_err
  end

  local range, range_err = capture_range(bufnr, params)
  if not range then
    util.notify(config(), range_err, vim.log.levels.WARN)
    return nil, range_err
  end
  range.tracking = tracking_for_target(target)
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  if not model.find(document, id) then
    return nil, 'The selected review comment no longer exists'
  end

  return mutate_comment({ root = target.root, id = id }, 'relocated', function(comment)
    if
      not vim.api.nvim_buf_is_valid(bufnr)
      or vim.api.nvim_buf_get_changedtick(bufnr) ~= changedtick
    then
      return false, 'The target buffer changed before relocation could be saved'
    end
    return model.relocate_comment(comment, {
      file = target.file,
      view = target.view,
      source = target.source,
      mode = range.mode,
      start_line = range.start_line,
      end_line = range.end_line,
      start_column = range.start_column,
      end_column = range.end_column,
      selected_lines = range.selected,
      selected_text = range.selected_text,
      prefix = range.prefix,
      suffix = range.suffix,
      file_sha256 = range.file_sha256,
      tracking = range.tracking,
      context_before = range.before,
      context_after = range.after,
    })
  end, function(root, old, updated)
    marks.detach(root, old.id)
    local _, mark_err = marks.attach(root, updated, bufnr, target, config())
    if mark_err then
      util.notify(
        config(),
        'Relocated comment saved, but extmark failed: ' .. mark_err,
        vim.log.levels.WARN
      )
    end
  end)
end

function M.copy(opts)
  M.ensure_setup()
  opts = opts or {}
  local root = root_for_command()
  if not root then
    util.notify(config(), 'No active Git repository for review comments', vim.log.levels.ERROR)
    return nil
  end
  local document = load_session(root)
  if not document then
    return nil
  end
  if not sync_and_save(root) then
    return nil
  end
  document = state.get(root)
  local text = exporter.render(document, config(), { include_resolved = opts.include_resolved })
  if text == '' then
    util.notify(config(), 'There are no matching review comments', vim.log.levels.INFO)
    return ''
  end
  local register = config().clipboard.register
  local available, availability_err = util.clipboard_available(register)
  if not available then
    util.notify(
      config(),
      string.format(
        'Could not copy review comments to register %q: %s',
        register,
        tostring(availability_err)
      ),
      vim.log.levels.ERROR
    )
    return nil
  end
  local ok, result = pcall(vim.fn.setreg, register, text)
  if not ok or result ~= 0 then
    local detail = ok and string.format('setreg() returned %s', tostring(result))
      or tostring(result)
    util.notify(config(), 'Could not copy review comments: ' .. detail, vim.log.levels.ERROR)
    return nil
  end
  local count = opts.include_resolved and #document.comments or model.counts(document).active
  util.notify(config(), string.format('Copied %d review comment(s)', count))
  emit('ReviewCommentsExported', { root = root, count = count })
  return text
end

function M.list(opts)
  M.ensure_setup()
  opts = opts or {}
  local root = root_for_command()
  if not root then
    util.notify(config(), 'No active Git repository for review comments', vim.log.levels.ERROR)
    return nil
  end
  local document = load_session(root)
  if not document then
    return nil
  end
  if not sync_and_save(root) then
    return nil
  end
  document = state.get(root)
  local counts = model.counts(document)
  local count = opts.include_resolved and counts.total or counts.active
  if count == 0 and not quickfix.has_projection(root) then
    util.notify(config(), 'There are no matching review comments', vim.log.levels.INFO)
    return nil
  end
  local kind, err = quickfix.open(root, document, config(), opts)
  if not kind then
    util.notify(config(), err, vim.log.levels.ERROR)
    return nil
  end
  if kind == 'loclist' then
    util.notify(config(), 'DiffTool owns quickfix; opened reviews in a location list')
  elseif count == 0 then
    util.notify(config(), 'The review list is now empty', vim.log.levels.INFO)
  end
  return kind
end

function M.status(root)
  M.ensure_setup()
  root = public_root(root)
  if not root then
    local err = 'No active Git repository for review comments'
    util.notify(config(), err, vim.log.levels.ERROR)
    return nil, err
  end
  local document = load_session(root)
  if not document then
    return nil
  end
  if not sync_and_save(root) then
    return nil
  end
  document = state.get(root)
  local counts = model.counts(document)
  local candidates = counts.stale - counts.orphaned
  local scope = document.session and document.session.scope or nil
  local scope_text = scope
      and scope.kind == 'git_diff'
      and string.format('reviewing %s (%s), ', scope.base.requested, scope.base.commit:sub(1, 12))
    or ''
  util.notify(
    config(),
    string.format(
      '%s%d active, %d resolved, %d candidate, %d orphaned',
      scope_text,
      counts.active,
      counts.resolved,
      candidates,
      counts.orphaned
    )
  )
  return counts
end

function M.reload(opts)
  M.ensure_setup()
  opts = opts or {}
  local root = public_root(opts.root)
  if not root then
    return nil, 'No active Git repository for review comments'
  end
  if state.is_dirty(root) and not opts.force then
    local err = 'Local review state has unsaved changes; use :ReviewReload! to discard them'
    util.notify(config(), err, vim.log.levels.WARN)
    return nil, err
  end
  local result, err = storage.load(root, config())
  if not result then
    util.notify(config(), err, vim.log.levels.ERROR)
    return nil, err
  end
  local document = install_loaded_document(root, result, 'reloaded')
  util.notify(config(), 'Reloaded review state from disk')
  return document
end

local function run_diff_opener(root, document)
  local scope = document.session and document.session.scope or nil
  if not scope or scope.kind ~= 'git_diff' then
    return false, 'The current review session has no Git base; use :ReviewStart [base-ref]'
  end
  emit('ReviewDiffRequested', { root = root, scope = vim.deepcopy(scope) })
  local opener = config().session.open_diff
  if not opener then
    return true
  end
  local ok, result, callback_err = pcall(opener, {
    root = root,
    scope = vim.deepcopy(scope),
    base_commit = scope.base.commit,
    head_commit = scope.target.head_commit_at_start,
  })
  if not ok then
    return false, 'session.open_diff failed: ' .. tostring(result)
  end
  if result == false then
    return false, tostring(callback_err or 'session.open_diff refused the request')
  end
  return true
end

--- Start a review session scoped to an immutable Git base commit.
--- @param opts? {root?: string, base_ref?: string, force?: boolean}
function M.start_session(opts)
  M.ensure_setup()
  opts = opts or {}
  local root = public_root(opts.root)
  if not root then
    return nil, 'No active Git repository for review comments'
  end
  local base_ref = vim.trim(opts.base_ref or '')
  if base_ref == '' then
    base_ref = 'HEAD'
  end
  local scope, scope_err = review_git.session_scope(root, base_ref)
  if not scope then
    util.notify(config(), scope_err, vim.log.levels.ERROR)
    return nil, scope_err
  end

  local document = load_session(root)
  if not document then
    return nil, 'Could not load the current review session'
  end
  local synced, sync_err = sync_and_save(root)
  if not synced then
    return nil, sync_err
  end
  document = state.get(root)
  if #document.comments > 0 and not opts.force then
    local err = 'The current review session has comments; use :ReviewStart! to archive it'
    util.notify(config(), err, vim.log.levels.WARN)
    return nil, err
  end

  local next_document = model.new_session({
    started_from = util.git_session_context(root),
    scope = scope,
  })
  local archive_path
  local next_token
  if #document.comments > 0 then
    local archive_err
    next_document, archive_path, archive_err, next_token = storage.archive(
      root,
      document,
      config(),
      state.token(root),
      { next_document = next_document }
    )
    if not next_document then
      util.notify(
        config(),
        'Could not start review session: ' .. tostring(archive_err),
        vim.log.levels.ERROR
      )
      return nil, archive_err
    end
  else
    local saved, save_err, token = storage.save(root, next_document, config(), state.token(root))
    if not saved then
      util.notify(
        config(),
        'Could not start review session: ' .. tostring(save_err),
        vim.log.levels.ERROR
      )
      return nil, save_err
    end
    next_token = token
  end

  marks.clear_root(root)
  local _, list_err = quickfix.clear(root)
  if list_err then
    util.notify(
      config(),
      'Session started, but its old review list could not be cleared: ' .. list_err,
      vim.log.levels.WARN
    )
  end
  state.set(root, next_document, next_token)
  emit('ReviewSessionStarted', {
    root = root,
    scope = vim.deepcopy(scope),
    archive_path = archive_path,
  })
  emit('ReviewCommentsChanged', { root = root, action = 'session_started' })
  util.notify(
    config(),
    string.format('Reviewing %s (%s) against the worktree', base_ref, scope.base.commit:sub(1, 12))
  )

  if config().session.open_on_start then
    local opened, open_err = run_diff_opener(root, next_document)
    if not opened then
      util.notify(config(), open_err, vim.log.levels.WARN)
    end
  end
  return vim.deepcopy(next_document.session), archive_path
end

function M.open_diff(opts)
  M.ensure_setup()
  opts = opts or {}
  local root = public_root(opts.root)
  if not root then
    return false, 'No active Git repository for review comments'
  end
  local document = load_session(root)
  if not document then
    return false, 'Could not load the current review session'
  end
  local ok, err = run_diff_opener(root, document)
  if not ok then
    util.notify(config(), err, vim.log.levels.WARN)
  end
  return ok, err
end

function M.get_session(root)
  M.ensure_setup()
  root = public_root(root)
  local document = root and load_session(root) or nil
  return document and vim.deepcopy(document.session) or nil
end

function M.clear()
  M.ensure_setup()
  local root = root_for_command()
  if not root then
    util.notify(config(), 'No active Git repository for review comments', vim.log.levels.ERROR)
    return nil
  end
  local document = load_session(root)
  if not document then
    return nil
  end
  if not sync_and_save(root) then
    return nil
  end
  document = state.get(root)
  local next_document, archive_path, err, next_token =
    storage.archive(root, document, config(), state.token(root))
  if not next_document then
    if next_token then
      state.mark_clean(root, next_token)
    end
    util.notify(config(), 'Could not clear review: ' .. tostring(err), vim.log.levels.ERROR)
    return nil
  end
  marks.clear_root(root)
  local _, list_err = quickfix.clear(root)
  if list_err then
    util.notify(
      config(),
      'Review archived, but its list could not be cleared: ' .. list_err,
      vim.log.levels.WARN
    )
  end
  state.set(root, next_document, next_token)
  emit('ReviewSessionCleared', { root = root, archive_path = archive_path })
  util.notify(
    config(),
    'Review archived to ' .. (util.relative_path(root, archive_path) or archive_path)
  )
  return archive_path
end

function M.next()
  M.ensure_setup()
  local root = root_for_command()
  if not root then
    return false
  end
  local ok, err = quickfix.next(root)
  if not ok then
    util.notify(config(), tostring(err), vim.log.levels.WARN)
  end
  return ok, err
end

function M.previous()
  M.ensure_setup()
  local root = root_for_command()
  if not root then
    return false
  end
  local ok, err = quickfix.previous(root)
  if not ok then
    util.notify(config(), tostring(err), vim.log.levels.WARN)
  end
  return ok, err
end

function M.jump()
  M.ensure_setup()
  local root = root_for_command()
  if not root then
    return false, 'No active Git repository for review comments'
  end
  local ok, err = quickfix.jump_selected(root)
  if not ok then
    util.notify(config(), tostring(err), vim.log.levels.WARN)
  end
  return ok, err
end

function M.close_list()
  M.ensure_setup()
  return quickfix.close_current()
end

function M._restore_buffer(bufnr)
  local target = target_for_buffer(bufnr, true)
  if not target then
    return
  end
  local document = load_session(target.root, { check_disk = false })
  if not document then
    return
  end
  local disk_mismatch = false
  if target.source and target.source.kind == 'worktree' and not vim.bo[bufnr].modified then
    local ok, disk_lines = pcall(vim.fn.readfile, util.join(target.root, target.file))
    disk_mismatch = ok
      and not vim.deep_equal(disk_lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end
  -- Passive BufRead/BufWinEnter restoration only inspects the opened file.
  -- Repository-wide missing-file recovery belongs at explicit command/reload
  -- boundaries; doing it here could read thousands of files on every window
  -- enter while an orphan remains unresolved.
  local reconciled, changed_ids =
    reconcile_document(target.root, document, { only_file = target.file })
  for id in pairs(changed_ids) do
    marks.detach(target.root, id)
  end
  if disk_mismatch then
    for _, comment in ipairs(document.comments) do
      if comment.file == target.file then
        marks.detach(target.root, comment.id)
      end
    end
  end
  local changed = (
    not disk_mismatch and marks.restore_buffer(target.root, document, bufnr, target, config())
  ) or reconciled
  -- A newly opened file may be a Git-proven destination for a missing stored
  -- path. Check only that destination against unresolved worktree anchors;
  -- do not enumerate every repository file on passive buffer events.
  if config().relocation.git_renames then
    local rename_maps = {}
    local renamed_ids = {}
    for _, comment in ipairs(document.comments) do
      local file_anchor = comment.anchor and comment.anchor.file_anchor or nil
      local tracking = file_anchor and file_anchor.tracking or nil
      if
        comment.file ~= target.file
        and comment.anchor.source
        and comment.anchor.source.kind == 'worktree'
        and tracking
        and tracking.commit
        and tracking.path
        and not (vim.uv or vim.loop).fs_stat(util.join(target.root, comment.file))
      then
        if rename_maps[tracking.commit] == nil then
          local map = review_git.rename_map(target.root, tracking.commit)
          rename_maps[tracking.commit] = map or false
        end
        local rename = rename_maps[tracking.commit] and rename_maps[tracking.commit][tracking.path]
        if rename and rename.new == target.file then
          local destination = file_lines(target.root, target.file)
          if destination then
            local result = anchor_matcher.reconcile(destination, comment.anchor, config())
            local old_file = comment.file
            if record_path_change(comment, old_file, target.file, 'git_rename', rename.score) then
              changed = true
            end
            if not result.valid then
              result.failure_reason = string.format(
                'Git renamed %s to %s, but %s',
                old_file,
                target.file,
                (result.failure_reason or 'the reviewed text could not be located'):lower()
              )
            end
            if apply_anchor_result(comment, result, destination) then
              changed = true
            end
            renamed_ids[comment.id] = true
          end
        end
      end
    end
    for id in pairs(renamed_ids) do
      marks.detach(target.root, id)
    end
    if next(renamed_ids) ~= nil and not disk_mismatch then
      changed = marks.restore_buffer(target.root, document, bufnr, target, config()) or changed
    end
  end
  if changed then
    save_session(target.root, document, { changed = true })
    refresh_projection(target.root, document)
  end
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, 'ReviewCommentRegion', { default = true, link = 'Visual' })
  vim.api.nvim_set_hl(0, 'ReviewCommentSign', { default = true, link = 'DiagnosticWarn' })
  vim.api.nvim_set_hl(0, 'ReviewCommentResolved', { default = true, link = 'CursorLine' })
  vim.api.nvim_set_hl(0, 'ReviewCommentResolvedSign', { default = true, link = 'Comment' })
  vim.api.nvim_set_hl(0, 'ReviewCommentCandidate', { default = true, link = 'DiagnosticWarn' })
  vim.api.nvim_set_hl(0, 'ReviewCommentCandidateSign', { default = true, link = 'DiagnosticWarn' })
  vim.api.nvim_set_hl(0, 'ReviewCommentOrphanedSign', { default = true, link = 'DiagnosticError' })
end

local function schedule_restore(bufnr)
  if pending_restores[bufnr] then
    return
  end
  pending_restores[bufnr] = true
  local generation = setup_generation
  vim.schedule(function()
    pending_restores[bufnr] = nil
    if
      initialized
      and generation == setup_generation
      and vim.api.nvim_buf_is_valid(bufnr)
      and vim.bo[bufnr].buftype ~= 'quickfix'
    then
      M._restore_buffer(bufnr)
    end
  end)
end

local function setup_autocommands()
  augroup = vim.api.nvim_create_augroup('ReviewCommentsNvim', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWinEnter', 'FileChangedShellPost' }, {
    group = augroup,
    callback = function(args)
      schedule_restore(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup,
    callback = function(args)
      local target = target_for_buffer(args.buf, true)
      local document = target and state.get(target.root) or nil
      if document then
        local changed = marks.sync_buffer(target.root, document, args.buf, config())
        local reconciled, changed_ids =
          reconcile_document(target.root, document, { only_file = target.file })
        for id in pairs(changed_ids) do
          marks.detach(target.root, id)
        end
        if reconciled then
          changed = marks.restore_buffer(target.root, document, args.buf, target, config()) or true
        end
        local ok = save_session(target.root, document, { changed = changed })
        if ok and changed then
          refresh_projection(target.root, document)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufUnload', 'BufWipeout' }, {
    group = augroup,
    callback = function(args)
      pending_restores[args.buf] = nil
      marks.drop_buffer(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = augroup,
    callback = function()
      state.each(function(root, document, metadata)
        local changed = marks.sync_root(root, document, config(), { only_unmodified = true })
        if changed then
          state.mark_dirty(root)
        end
        if metadata.dirty or changed then
          save_session(root, document)
        end
      end)
    end,
  })
end

function M.setup(opts)
  local next_config = vim.tbl_deep_extend('force', vim.deepcopy(config_module.defaults), opts or {})
  local valid, config_err = config_module.validate(next_config)
  if not valid then
    error('review-comments.nvim: ' .. config_err, 2)
  end
  local storage_changed = initialized and not vim.deep_equal(config().storage, next_config.storage)
  if initialized then
    local save_error
    state.each(function(root, document, metadata)
      if save_error then
        return
      end
      local changed = marks.sync_root(root, document, config())
      if changed or metadata.dirty then
        local ok, err, token = storage.save(root, document, config(), metadata.token)
        if not ok then
          save_error = err
        else
          state.mark_clean(root, token)
        end
      end
    end)
    if save_error then
      error('review-comments.nvim: could not preserve live review state: ' .. save_error, 2)
    end
  end
  if storage_changed then
    state.each(function(root)
      quickfix.clear(root)
    end)
    marks.reset()
    quickfix.reset()
    state.reset()
    editor.reset()
  end
  config_module.setup(opts)
  setup_generation = setup_generation + 1
  if initialized then
    marks.reset()
  end
  setup_highlights()
  setup_autocommands()
  initialized = true
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) ~= '' then
      M._restore_buffer(bufnr)
    end
  end
  return M
end

function M.ensure_setup()
  if not initialized then
    M.setup({})
  end
end

function M.get_comments(root)
  M.ensure_setup()
  root = public_root(root)
  local document = root and load_session(root) or nil
  return document and vim.deepcopy(document.comments) or {}
end

function M._reset_for_tests()
  setup_generation = setup_generation + 1
  marks.reset()
  editor.reset()
  state.reset()
  quickfix.reset()
  pending_restores = {}
  initialized = false
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
end

return M
