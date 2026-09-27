local anchor_matcher = require('review_comments.anchor')

local M = {
  namespace = vim.api.nvim_create_namespace('review-comments.nvim'),
  entries = {},
  buffers = {},
}

local function root_entries(root)
  M.entries[root] = M.entries[root] or {}
  return M.entries[root]
end

local function buffer_entries(bufnr)
  M.buffers[bufnr] = M.buffers[bufnr] or {}
  return M.buffers[bufnr]
end

local function mark_position(entry)
  if not entry or not vim.api.nvim_buf_is_valid(entry.bufnr) then
    return nil
  end
  local ok, position = pcall(
    vim.api.nvim_buf_get_extmark_by_id,
    entry.bufnr,
    M.namespace,
    entry.extmark_id,
    { details = true }
  )
  if not ok or #position == 0 then
    return nil
  end
  return position
end

local function entry_live(entry)
  if not entry or entry.needs_relocation then
    return false
  end
  local position = mark_position(entry)
  if not position then
    return false
  end
  local details = position[3] or {}
  if entry.orphan then
    return details.invalid ~= true
  end
  if details.invalid == true or details.end_row == nil then
    return false
  end
  return details.end_row > position[1]
    or (details.end_row == position[1] and (details.end_col or 0) > (position[2] or 0))
end

local style_for
local extmark_options

local function set_point(entry, row)
  if entry.extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, M.namespace, entry.extmark_id)
  end
  local style = style_for(entry.comment, entry.config)
  local options = {
    strict = false,
    sign_text = style.sign_text,
    sign_hl_group = style.sign_highlight,
    right_gravity = true,
    undo_restore = true,
  }
  local ok, extmark_id =
    pcall(vim.api.nvim_buf_set_extmark, entry.bufnr, M.namespace, row, 0, options)
  if not ok then
    return nil, tostring(extmark_id)
  end
  entry.extmark_id = extmark_id
  entry.start_row = row
  entry.end_row = row + 1
  entry.needs_relocation = false
  return extmark_id
end

local function line_context(bufnr, start_line, end_line, count)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local before_start = math.max(0, start_line - 1 - count)
  local before_end = math.max(0, start_line - 1)
  local after_start = math.min(line_count, end_line)
  local after_end = math.min(line_count, end_line + count)
  return vim.api.nvim_buf_get_lines(bufnr, before_start, before_end, false),
    vim.api.nvim_buf_get_lines(bufnr, after_start, after_end, false)
end

style_for = function(comment, config)
  if comment.anchor and comment.anchor.valid == false then
    return {
      highlight = nil,
      sign_highlight = config.display.orphaned_sign_highlight,
      sign_text = config.display.orphaned_sign_text,
      point = true,
    }
  end
  if comment.anchor and comment.anchor.stale == true then
    return {
      highlight = config.display.candidate_highlight,
      sign_highlight = config.display.candidate_sign_highlight,
      sign_text = config.display.candidate_sign_text,
    }
  end
  if comment.status == 'resolved' then
    return {
      highlight = config.display.resolved_highlight,
      sign_highlight = config.display.resolved_sign_highlight,
      sign_text = config.display.resolved_sign_text,
    }
  end
  return {
    highlight = config.display.highlight,
    sign_highlight = config.display.sign_highlight,
    sign_text = config.display.sign_text,
  }
end

extmark_options = function(entry)
  local style = style_for(entry.comment, entry.config)
  return {
    strict = false,
    hl_group = style.highlight,
    hl_eol = entry.comment.anchor.mode ~= 'char',
    sign_text = style.sign_text,
    sign_hl_group = style.sign_highlight,
    -- Inward gravity leaves text inserted exactly at either boundary outside
    -- the review. The edit callback repairs replacements that touch the range.
    right_gravity = true,
    end_right_gravity = false,
    undo_restore = true,
    invalidate = true,
  }
end

local function set_range(entry, start_row, end_row)
  if entry.extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, M.namespace, entry.extmark_id)
  end

  local options = extmark_options(entry)
  local anchor = entry.comment.anchor
  local start_col = anchor.mode == 'char' and (entry.start_col or anchor.start_column or 0) or 0
  options.end_row = anchor.mode == 'char' and (end_row - 1) or end_row
  options.end_col = anchor.mode == 'char' and (entry.end_col or anchor.end_column or 0) or 0
  local ok, extmark_id =
    pcall(vim.api.nvim_buf_set_extmark, entry.bufnr, M.namespace, start_row, start_col, options)
  if not ok then
    entry.needs_relocation = true
    return nil, tostring(extmark_id)
  end

  entry.extmark_id = extmark_id
  entry.start_row = start_row
  entry.end_row = end_row
  entry.tracked_lines = vim.api.nvim_buf_get_lines(entry.bufnr, start_row, end_row, false)
  entry.needs_relocation = false
  return extmark_id
end

local function remove_entry(entry)
  if not entry then
    return
  end
  if vim.api.nvim_buf_is_valid(entry.bufnr) and entry.extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, M.namespace, entry.extmark_id)
  end
  local roots = M.entries[entry.root]
  if roots then
    roots[entry.comment_id] = nil
    if vim.tbl_isempty(roots) then
      M.entries[entry.root] = nil
    end
  end
  local buffers = M.buffers[entry.bufnr]
  if buffers then
    buffers[entry.comment_id] = nil
  end
end

local function index_entry(entry)
  root_entries(entry.root)[entry.comment_id] = entry
  buffer_entries(entry.bufnr)[entry.comment_id] = entry
end

local function exact_matches(lines, needle, first, last)
  if not needle or #needle == 0 or #needle > #lines then
    return {}
  end
  first = math.max(1, first or 1)
  last = math.min(last or (#lines - #needle + 1), #lines - #needle + 1)
  local matches = {}
  for start = first, last do
    local matches_here = true
    for offset = 1, #needle do
      if lines[start + offset - 1] ~= needle[offset] then
        matches_here = false
        break
      end
    end
    if matches_here then
      table.insert(matches, start - 1)
    end
  end
  return matches
end

local function expected_lines(anchor)
  return vim.split(anchor.current_text or '', '\n', { plain = true })
end

local function context_score(lines, start_row, length, before, after)
  local score = 0
  local before_matches = 0
  local after_matches = 0
  for offset = 1, #before do
    local line_index = start_row - offset
    local expected = before[#before - offset + 1]
    if line_index >= 0 and lines[line_index + 1] == expected then
      score = score + 1
      before_matches = before_matches + 1
    else
      break
    end
  end
  for offset = 1, #after do
    local line_index = start_row + length + offset - 1
    if line_index < #lines and lines[line_index + 1] == after[offset] then
      score = score + 1
      after_matches = after_matches + 1
    else
      break
    end
  end
  return score, before_matches, after_matches
end

local function context_candidate(lines, anchor, config)
  local length = math.max(1, anchor.end_line - anchor.start_line + 1)
  if length > #lines then
    return nil
  end
  local before = anchor.current_context_before or anchor.original_context_before or {}
  local after = anchor.current_context_after or anchor.original_context_after or {}
  local minimum = config.relocation.min_context_lines
  if #before + #after < minimum then
    return nil
  end

  local best
  local second_score = -1
  for start_row = 0, #lines - length do
    local score, before_matches, after_matches =
      context_score(lines, start_row, length, before, after)
    local both_sides = #before == 0 or #after == 0 or (before_matches > 0 and after_matches > 0)
    if both_sides and score >= minimum then
      local distance = math.abs(start_row - (anchor.start_line - 1))
      if not best or score > best.score or (score == best.score and distance < best.distance) then
        if best then
          second_score = math.max(second_score, best.score)
        end
        best = { start_row = start_row, score = score, distance = distance }
      else
        second_score = math.max(second_score, score)
      end
    end
  end
  if best and best.score - second_score >= config.relocation.context_score_margin then
    return best.start_row, best.start_row + length
  end
  return nil
end

local function source_compatible(comment, target)
  local source = comment.anchor and comment.anchor.source or nil
  if type(source) ~= 'table' then
    return false, 'Review comment has no source identity'
  end
  local target_source = target.source
  if type(target_source) ~= 'table' then
    target_source = target.difftool == true
        and target.view == 'left'
        and { kind = 'snapshot', side = 'left' }
      or { kind = 'worktree' }
  end
  if source.kind == 'snapshot' then
    if target_source.kind ~= 'snapshot' or target_source.side ~= source.side then
      return false, 'Historical-side review comments only attach to the matching DiffTool side'
    end
    if
      type(source.content_sha256) == 'string'
      and source.content_sha256 ~= ''
      and type(target_source.content_sha256) == 'string'
      and target_source.content_sha256 ~= ''
      and source.content_sha256 ~= target_source.content_sha256
    then
      return false, 'Historical snapshot content does not match the stored review source'
    end
    return true
  end
  if source.kind == 'worktree' then
    if target_source.kind ~= 'worktree' then
      return false, 'Working-tree review comments do not attach to snapshot buffers'
    end
    return true
  end
  return false, 'Review comment has an unsupported source identity'
end

local function relocate_on_restore(comment, bufnr, config)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local result = anchor_matcher.reconcile(lines, comment.anchor, config)
  if not result.valid then
    return nil, nil, false, result
  end
  return result.start_line - 1, result.end_line, not result.stale, result
end

local function update_restored_anchor(comment, bufnr, start_row, end_row, trusted, config, result)
  local anchor = comment.anchor
  local old_start = anchor.start_line
  local old_end = anchor.end_line
  local old_valid = anchor.valid
  local old_stale = anchor.stale
  local old_current_text = anchor.current_text
  local old_context_before = vim.deepcopy(anchor.current_context_before)
  local old_context_after = vim.deepcopy(anchor.current_context_after)
  local old_start_column = anchor.start_column
  local old_end_column = anchor.end_column
  local old_failure_reason = anchor.failure_reason
  local old_resolution_method = anchor.resolution_method
  local old_file_sha256 = anchor.current_file_sha256
  anchor.start_line = start_row + 1
  anchor.end_line = end_row
  anchor.start_column = result and result.start_column or anchor.start_column
  anchor.end_column = result and result.end_column or anchor.end_column
  anchor.valid = true
  anchor.stale = not trusted
  anchor.failure_reason = result and result.failure_reason or nil
  anchor.resolution_method = result and result.method or anchor.resolution_method
  if trusted and result and result.file_sha256 then
    anchor.current_file_sha256 = result.file_sha256
  end
  if trusted then
    local lines = anchor.mode == 'char'
        and vim.api.nvim_buf_get_text(
          bufnr,
          start_row,
          anchor.start_column,
          end_row - 1,
          anchor.end_column,
          {}
        )
      or vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
    local before, after = line_context(bufnr, start_row + 1, end_row, config.context_lines)
    anchor.current_text = table.concat(lines, '\n')
    anchor.current_text_sha256 = vim.fn.sha256(anchor.current_text)
    anchor.current_prefix = result and result.current_prefix or anchor.current_prefix
    anchor.current_suffix = result and result.current_suffix or anchor.current_suffix
    anchor.current_context_before = before
    anchor.current_context_after = after
  end
  return old_start ~= anchor.start_line
    or old_end ~= anchor.end_line
    or old_valid ~= anchor.valid
    or old_stale ~= anchor.stale
    or old_start_column ~= anchor.start_column
    or old_end_column ~= anchor.end_column
    or old_failure_reason ~= anchor.failure_reason
    or old_resolution_method ~= anchor.resolution_method
    or old_file_sha256 ~= anchor.current_file_sha256
    or old_current_text ~= anchor.current_text
    or not vim.deep_equal(old_context_before, anchor.current_context_before)
    or not vim.deep_equal(old_context_after, anchor.current_context_after)
end

local function repair_entry(entry, first_line, last_line, new_last_line)
  local target_start
  local target_end
  local start_row = entry.start_row
  local end_row = entry.end_row

  if first_line == start_row and last_line == end_row then
    if new_last_line > first_line then
      target_start = first_line
      target_end = new_last_line
    end
  elseif last_line > first_line and first_line >= start_row and last_line <= end_row then
    -- Only a replacement wholly contained by the review has an unambiguous
    -- relationship to it. An edit crossing either boundary may contain
    -- unrelated code and must not silently widen the review range.
    target_start = start_row
    target_end = end_row + (new_last_line - last_line)
  else
    local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
    local matches = exact_matches(lines, entry.tracked_lines)
    if #matches == 1 then
      target_start = matches[1]
      target_end = target_start + #entry.tracked_lines
    end
  end

  if not target_start or target_end <= target_start then
    entry.needs_relocation = true
    return false
  end
  return set_range(entry, target_start, target_end) ~= nil
end

local function position_le(left, right)
  return left.row < right.row or (left.row == right.row and left.col <= right.col)
end

local function absolute_end(start_row, start_col, row_offset, column_offset)
  return {
    row = start_row + row_offset,
    col = row_offset == 0 and start_col + column_offset or column_offset,
  }
end

local function mapped_position(position, old_end, new_end)
  if position.row == old_end.row then
    return {
      row = new_end.row,
      col = new_end.col + (position.col - old_end.col),
    }
  end
  return {
    row = position.row + (new_end.row - old_end.row),
    col = position.col,
  }
end

local function repair_char_entry(entry, edit)
  local position = mark_position(entry)
  local details = position and position[3] or {}
  if
    position
    and details.invalid ~= true
    and details.end_row ~= nil
    and (
      details.end_row > position[1]
      or (details.end_row == position[1] and (details.end_col or 0) > position[2])
    )
  then
    entry.start_row = position[1]
    entry.start_col = position[2]
    entry.end_row = details.end_row + 1
    entry.end_col = details.end_col
    entry.tracked_lines =
      vim.api.nvim_buf_get_lines(entry.bufnr, entry.start_row, entry.end_row, false)
    return true
  end
  if not edit then
    entry.needs_relocation = true
    return false
  end

  local range_start = { row = entry.start_row, col = entry.start_col or 0 }
  local range_end = { row = entry.end_row - 1, col = entry.end_col or 0 }
  local nonempty_edit = edit.start.row ~= edit.old_end.row or edit.start.col ~= edit.old_end.col
  if
    not nonempty_edit
    or not position_le(range_start, edit.start)
    or not position_le(edit.old_end, range_end)
  then
    entry.needs_relocation = true
    return false
  end

  local next_end = mapped_position(range_end, edit.old_end, edit.new_end)
  if not position_le(range_start, next_end) or vim.deep_equal(range_start, next_end) then
    entry.needs_relocation = true
    return false
  end
  entry.start_row = range_start.row
  entry.start_col = range_start.col
  entry.end_row = next_end.row + 1
  entry.end_col = next_end.col
  return set_range(entry, entry.start_row, entry.end_row) ~= nil
end

local function on_lines(bufnr, first_line, last_line, new_last_line)
  local byte_edit = (M.buffers[bufnr] or {})._byte_edit
  for id, entry in pairs(M.buffers[bufnr] or {}) do
    if id ~= '_attached' and id ~= '_byte_edit' then
      local touches_range = last_line > first_line
        and first_line < entry.end_row
        and last_line > entry.start_row
      local insertion_inside = last_line == first_line
        and first_line > entry.start_row
        and first_line < entry.end_row
      if insertion_inside and not entry.needs_relocation then
        entry.end_row = entry.end_row + (new_last_line - last_line)
        entry.tracked_lines =
          vim.api.nvim_buf_get_lines(entry.bufnr, entry.start_row, entry.end_row, false)
      elseif entry.needs_relocation or touches_range then
        if entry.comment.anchor.mode == 'char' then
          repair_char_entry(entry, byte_edit)
        else
          repair_entry(entry, first_line, last_line, new_last_line)
        end
      else
        -- Extmarks shift predictably for a line edit wholly before/after the
        -- range. Keep the cache in step without an extmark lookup and range
        -- reread for every unrelated comment on every keystroke.
        if last_line <= entry.start_row then
          local delta = new_last_line - last_line
          entry.start_row = entry.start_row + delta
          entry.end_row = entry.end_row + delta
        end
      end
    end
  end
  if M.buffers[bufnr] then
    M.buffers[bufnr]._byte_edit = nil
  end
end

local function ensure_buffer_tracking(bufnr)
  local entries = buffer_entries(bufnr)
  if entries._attached then
    return true
  end
  local attached = vim.api.nvim_buf_attach(bufnr, false, {
    on_bytes = function(
      _,
      changed_bufnr,
      _,
      start_row,
      start_col,
      _,
      old_end_row,
      old_end_col,
      _,
      new_end_row,
      new_end_col
    )
      local entries_for_buffer = M.buffers[changed_bufnr]
      if entries_for_buffer then
        entries_for_buffer._byte_edit = {
          start = { row = start_row, col = start_col },
          old_end = absolute_end(start_row, start_col, old_end_row, old_end_col),
          new_end = absolute_end(start_row, start_col, new_end_row, new_end_col),
        }
      end
    end,
    on_lines = function(_, changed_bufnr, _, first_line, last_line, new_last_line)
      on_lines(changed_bufnr, first_line, last_line, new_last_line)
    end,
    on_detach = function(_, detached_bufnr)
      M.drop_buffer(detached_bufnr)
    end,
  })
  if attached then
    entries._attached = true
  end
  return attached
end

--- Attach or restore a comment extmark.
--- @return integer? extmark_id
--- @return string? error
--- @return boolean changed Whether durable anchor metadata changed.
function M.attach(root, comment, bufnr, target, config)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, 'Buffer is not valid', false
  end
  local compatible, source_err = source_compatible(comment, target)
  if not compatible then
    return nil, source_err, false
  end

  local existing = root_entries(root)[comment.id]
  if existing and existing.bufnr == bufnr and existing.needs_relocation then
    -- Preserve the trusted in-session cache until BufWritePost records the
    -- orphan. A later exact undo/reinsertion can then repair the same entry.
    existing.comment = comment
    return nil, 'Review range is waiting for an exact in-session relocation', false
  end
  if entry_live(existing) then
    local source = comment.anchor and comment.anchor.source or {}
    local target_source = target.source or {}
    local should_reassign = existing.bufnr ~= bufnr
      and source.kind == 'worktree'
      and target_source.kind == 'worktree'
      and ((target.difftool == true and target.view == 'right') or existing.difftool == true)
    if not should_reassign then
      existing.comment = comment
      return existing.extmark_id, nil, false
    end
    remove_entry(existing)
  elseif existing then
    remove_entry(existing)
  end

  local start_row, end_row, trusted, result = relocate_on_restore(comment, bufnr, config)
  if not start_row then
    local changed = comment.anchor.valid ~= false
      or comment.anchor.stale ~= true
      or comment.anchor.failure_reason ~= result.failure_reason
      or comment.anchor.resolution_method ~= result.method
    comment.anchor.valid = false
    comment.anchor.stale = true
    comment.anchor.failure_reason = result.failure_reason
    comment.anchor.resolution_method = result.method
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local row = math.max(0, math.min((comment.anchor.start_line or 1) - 1, line_count - 1))
    local entry = {
      bufnr = bufnr,
      config = config,
      root = root,
      comment_id = comment.id,
      comment = comment,
      start_row = row,
      end_row = row + 1,
      tracked_lines = {},
      orphan = true,
      view = target.view,
      difftool = target.difftool == true,
    }
    local point, point_err = set_point(entry, row)
    if point then
      index_entry(entry)
      ensure_buffer_tracking(bufnr)
      return point, nil, changed
    end
    return nil, point_err or 'Could not create the orphaned review marker', changed
  end
  local changed =
    update_restored_anchor(comment, bufnr, start_row, end_row, trusted, config, result)
  local entry = {
    bufnr = bufnr,
    config = config,
    root = root,
    comment_id = comment.id,
    comment = comment,
    start_row = start_row,
    end_row = end_row,
    start_col = comment.anchor.mode == 'char' and comment.anchor.start_column or 0,
    end_col = comment.anchor.mode == 'char' and comment.anchor.end_column or 0,
    tracked_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false),
    -- A context-only candidate has an intentionally untrusted live position;
    -- durable stale flags from a deletion can still recover if exact text is
    -- reinserted into the edit-tracked mark later.
    stale = trusted == false,
    view = target.view,
    difftool = target.difftool == true,
  }
  local extmark_id, mark_err = set_range(entry, start_row, end_row)
  if not extmark_id then
    return nil, mark_err, changed
  end
  index_entry(entry)
  ensure_buffer_tracking(bufnr)
  return extmark_id, nil, changed
end

function M.restore_buffer(root, document, bufnr, target, config)
  local changed = false
  for _, comment in ipairs(document.comments) do
    if comment.file == target.file then
      local _, _, anchor_changed = M.attach(root, comment, bufnr, target, config)
      changed = anchor_changed or changed
    end
  end
  return changed
end

function M.sync_comment(root, comment, config, snapshot)
  local entry = root_entries(root)[comment.id]
  if not entry or not vim.api.nvim_buf_is_valid(entry.bufnr) then
    return false
  end
  if entry.orphan then
    return false
  end
  local position = mark_position(entry)
  local details = position and position[3] or {}
  local char_mode = comment.anchor.mode == 'char'
  local empty_or_reversed = details.end_row ~= nil
    and (
      char_mode
        and (details.end_row < position[1] or (details.end_row == position[1] and (details.end_col or 0) <= position[2]))
      or not char_mode and details.end_row <= position[1]
    )
  if
    entry.needs_relocation
    or not position
    or details.invalid == true
    or details.end_row == nil
    or empty_or_reversed
  then
    local changed = comment.anchor.valid ~= false or comment.anchor.stale ~= true
    comment.anchor.valid = false
    comment.anchor.stale = true
    return changed
  end

  local start_line = position[1] + 1
  local end_line = char_mode and details.end_row + 1 or details.end_row
  local start_column = char_mode and position[2] or 0
  local end_column = char_mode and details.end_col or 0
  local changed = comment.anchor.start_line ~= start_line
    or comment.anchor.end_line ~= end_line
    or comment.anchor.start_column ~= start_column
    or comment.anchor.end_column ~= end_column
  comment.anchor.start_line = start_line
  comment.anchor.end_line = end_line
  comment.anchor.start_column = start_column
  comment.anchor.end_column = end_column
  if entry.stale then
    comment.anchor.stale = true
    return changed
  end

  local lines = char_mode
      and vim.api.nvim_buf_get_text(
        entry.bufnr,
        start_line - 1,
        start_column,
        end_line - 1,
        end_column,
        {}
      )
    or vim.api.nvim_buf_get_lines(entry.bufnr, start_line - 1, end_line, false)
  local before, after = line_context(entry.bufnr, start_line, end_line, config.context_lines)
  local current_text = table.concat(lines, '\n')
  snapshot = snapshot or {}
  local all_lines = snapshot.lines
  if not all_lines then
    all_lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
    snapshot.lines = all_lines
  end
  local current_file_sha256 = snapshot.sha256
  if not current_file_sha256 then
    current_file_sha256 = vim.fn.sha256(table.concat(all_lines, '\n'))
    snapshot.sha256 = current_file_sha256
  end
  local current_prefix = ''
  local current_suffix = ''
  if char_mode then
    current_prefix = (all_lines[start_line] or ''):sub(1, start_column)
    current_suffix = (all_lines[end_line] or ''):sub(end_column + 1)
  end
  if
    (comment.anchor.stale == true or comment.anchor.valid == false)
    and current_text ~= comment.anchor.current_text
  then
    -- A live mark with trusted provenance may recover after undo/reinsertion,
    -- but only when its text is exactly the last durable trusted text.
    comment.anchor.stale = true
    return changed
  end
  changed = changed
    or comment.anchor.current_text ~= current_text
    or not vim.deep_equal(comment.anchor.current_context_before, before)
    or not vim.deep_equal(comment.anchor.current_context_after, after)
    or comment.anchor.current_prefix ~= current_prefix
    or comment.anchor.current_suffix ~= current_suffix
    or comment.anchor.current_file_sha256 ~= current_file_sha256
    or comment.anchor.valid == false
    or comment.anchor.stale == true
  comment.anchor.current_text = current_text
  comment.anchor.current_text_sha256 = vim.fn.sha256(current_text)
  comment.anchor.current_prefix = current_prefix
  comment.anchor.current_suffix = current_suffix
  comment.anchor.current_file_sha256 = current_file_sha256
  comment.anchor.current_context_before = before
  comment.anchor.current_context_after = after
  comment.anchor.valid = true
  comment.anchor.stale = false
  comment.anchor.failure_reason = nil
  comment.anchor.resolution_method = 'extmark'
  return changed
end

function M.sync_root(root, document, config, opts)
  opts = opts or {}
  local changed = false
  local snapshots = {}
  for _, comment in ipairs(document.comments) do
    local entry = root_entries(root)[comment.id]
    if
      entry
      and vim.api.nvim_buf_is_valid(entry.bufnr)
      and (not opts.only_unmodified or not vim.bo[entry.bufnr].modified)
      and (not opts.bufnr or opts.bufnr == entry.bufnr)
    then
      snapshots[entry.bufnr] = snapshots[entry.bufnr] or {}
      changed = M.sync_comment(root, comment, config, snapshots[entry.bufnr]) or changed
    end
  end
  return changed
end

function M.sync_buffer(root, document, bufnr, config)
  return M.sync_root(root, document, config, { bufnr = bufnr })
end

function M.comments_at(root, bufnr, line)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local ids = {}
  local row = math.max(0, (line or 1) - 1)
  for id, entry in pairs(M.buffers[bufnr] or {}) do
    if id ~= '_attached' and id ~= '_byte_edit' and entry.root == root and entry_live(entry) then
      local position = mark_position(entry)
      local details = position and position[3] or {}
      if
        position
        and (
          (entry.orphan and row == position[1])
          or (
            not entry.orphan
            and row >= position[1]
            and (
              entry.comment.anchor.mode == 'char' and row <= (details.end_row or position[1])
              or entry.comment.anchor.mode ~= 'char' and row < (details.end_row or position[1])
            )
          )
        )
      then
        table.insert(ids, id)
      end
    end
  end
  table.sort(ids)
  return ids
end

function M.detach(root, comment_id)
  local entry = M.entries[root] and M.entries[root][comment_id] or nil
  if not entry then
    return false
  end
  remove_entry(entry)
  return true
end

function M.restyle(root, comment)
  local entry = M.entries[root] and M.entries[root][comment.id] or nil
  if not entry or not entry_live(entry) then
    return false
  end
  local position = mark_position(entry)
  entry.comment = comment
  if entry.orphan then
    return set_point(entry, position[1]) ~= nil
  end
  local end_row = comment.anchor.mode == 'char' and position[3].end_row + 1 or position[3].end_row
  return set_range(entry, position[1], end_row) ~= nil
end

function M.clear_root(root)
  local ids = vim.tbl_keys(M.entries[root] or {})
  for _, id in ipairs(ids) do
    M.detach(root, id)
  end
end

function M.drop_buffer(bufnr)
  local entries = M.buffers[bufnr] or {}
  local pending = {}
  for id, entry in pairs(entries) do
    if id ~= '_attached' and id ~= '_byte_edit' then
      table.insert(pending, entry)
    end
  end
  for _, entry in ipairs(pending) do
    remove_entry(entry)
  end
  M.buffers[bufnr] = nil
end

function M.get(comment_id, root)
  local entry = M.entries[root] and M.entries[root][comment_id] or nil
  return entry_live(entry) and entry or nil
end

function M.reset()
  -- nvim_buf_detach() invokes on_detach synchronously, which mutates M.buffers.
  -- Iterate a snapshot so one buffer cannot be skipped while resetting several.
  local bufnrs = vim.tbl_keys(M.buffers)
  for _, bufnr in ipairs(bufnrs) do
    local entries = M.buffers[bufnr]
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)
      if entries and entries._attached then
        pcall(vim.api.nvim_buf_detach, bufnr)
      end
    end
  end
  M.entries = {}
  M.buffers = {}
end

return M
