local M = {}

local function is_integer(value)
  return type(value) == 'number' and value % 1 == 0
end

local function validate_lines(lines)
  if type(lines) ~= 'table' then
    return 'Buffer lines must be an array of strings'
  end
  for index, line in ipairs(lines) do
    if type(line) ~= 'string' then
      return string.format('Buffer line %d is not a string', index)
    end
  end
  return nil
end

local function validate_anchor(anchor)
  if type(anchor) ~= 'table' then
    return 'Anchor must be a table'
  end
  if anchor.mode ~= 'line' and anchor.mode ~= 'char' then
    return "Anchor mode must be 'line' or 'char'"
  end
  if
    not is_integer(anchor.start_line)
    or not is_integer(anchor.end_line)
    or anchor.start_line < 1
    or anchor.end_line < anchor.start_line
  then
    return 'Anchor has an invalid line range'
  end
  if anchor.mode == 'char' then
    if
      not is_integer(anchor.start_column)
      or not is_integer(anchor.end_column)
      or anchor.start_column < 0
      or anchor.end_column < 0
      or (anchor.start_line == anchor.end_line and anchor.end_column <= anchor.start_column)
    then
      return 'Anchor has an invalid character range'
    end
  end
  return nil
end

local function normalized_position(anchor)
  return {
    start_line = anchor.start_line,
    end_line = anchor.end_line,
    start_column = anchor.mode == 'char' and anchor.start_column or 0,
    end_column = anchor.mode == 'char' and anchor.end_column or 0,
  }
end

--- Extract an anchor from an array of buffer lines.
---
--- Lines are 1-based and inclusive. Character columns are 0-based byte
--- offsets, with an exclusive end column. For line anchors the prefix and
--- suffix are empty strings.
--- @param lines string[]
--- @param anchor table
--- @return string? text
--- @return string? prefix
--- @return string? suffix
--- @return string? error
function M.extract(lines, anchor)
  local lines_err = validate_lines(lines)
  if lines_err then
    return nil, nil, nil, lines_err
  end
  local anchor_err = validate_anchor(anchor)
  if anchor_err then
    return nil, nil, nil, anchor_err
  end
  if anchor.end_line > #lines then
    return nil, nil, nil, 'Anchor falls outside the buffer'
  end

  if anchor.mode == 'line' then
    local selected = {}
    for line = anchor.start_line, anchor.end_line do
      selected[#selected + 1] = lines[line]
    end
    return table.concat(selected, '\n'), '', ''
  end

  local first = lines[anchor.start_line]
  local last = lines[anchor.end_line]
  if anchor.start_column > #first or anchor.end_column > #last then
    return nil, nil, nil, 'Anchor byte column falls outside the buffer line'
  end

  local prefix = first:sub(1, anchor.start_column)
  local suffix = last:sub(anchor.end_column + 1)
  if anchor.start_line == anchor.end_line then
    return first:sub(anchor.start_column + 1, anchor.end_column), prefix, suffix
  end

  local selected = { first:sub(anchor.start_column + 1) }
  for line = anchor.start_line + 1, anchor.end_line - 1 do
    selected[#selected + 1] = lines[line]
  end
  selected[#selected + 1] = last:sub(1, anchor.end_column)
  return table.concat(selected, '\n'), prefix, suffix
end

--- Hash the exact buffer representation used by the anchor reconciler.
--- @param lines string[]
--- @return string? digest
--- @return string? error
function M.file_sha256(lines)
  local err = validate_lines(lines)
  if err then
    return nil, err
  end
  return vim.fn.sha256(table.concat(lines, '\n'))
end

local function split_lines(text)
  local result = {}
  local from = 1
  while true do
    local newline = text:find('\n', from, true)
    if not newline then
      result[#result + 1] = text:sub(from)
      return result
    end
    result[#result + 1] = text:sub(from, newline - 1)
    from = newline + 1
  end
end

local function context_list(anchor, current, generic, original)
  if type(anchor[current]) == 'table' then
    return anchor[current]
  end
  if type(anchor[generic]) == 'table' then
    return anchor[generic]
  end
  if type(anchor[original]) == 'table' then
    return anchor[original]
  end
  return {}
end

local function boundary_text(anchor, current, generic, original)
  if type(anchor[current]) == 'string' then
    return anchor[current]
  end
  if type(anchor[generic]) == 'string' then
    return anchor[generic]
  end
  if type(anchor[original]) == 'string' then
    return anchor[original]
  end
  return ''
end

local function contexts(anchor)
  return context_list(anchor, 'current_context_before', 'context_before', 'original_context_before'),
    context_list(anchor, 'current_context_after', 'context_after', 'original_context_after'),
    boundary_text(anchor, 'current_prefix', 'prefix', 'original_prefix'),
    boundary_text(anchor, 'current_suffix', 'suffix', 'original_suffix')
end

local function relocation_config(config, old_length)
  local relocation = type(config) == 'table' and config.relocation or nil
  if type(relocation) ~= 'table' then
    relocation = type(config) == 'table' and config or {}
  end
  local maximum = relocation.max_candidate_lines
  if not is_integer(maximum) or maximum < 1 then
    maximum = math.max(200, old_length)
  end
  local minimum = relocation.min_context_lines
  if not is_integer(minimum) or minimum < 1 then
    minimum = 2
  end
  local margin = relocation.context_score_margin
  if not is_integer(margin) or margin < 1 then
    margin = 1
  end
  return {
    enabled = relocation.enabled ~= false,
    max_candidate_lines = maximum,
    min_context_lines = minimum,
    context_score_margin = margin,
  }
end

local function line_exact_matches(lines, text)
  local needle = split_lines(text)
  if #needle > #lines then
    return {}
  end
  local matches = {}
  for first = 1, #lines - #needle + 1 do
    local equal = true
    for offset = 1, #needle do
      if lines[first + offset - 1] ~= needle[offset] then
        equal = false
        break
      end
    end
    if equal then
      matches[#matches + 1] = {
        start_line = first,
        end_line = first + #needle - 1,
        start_column = 0,
        end_column = 0,
      }
    end
  end
  return matches
end

local function line_starts(lines)
  local starts = {}
  local offset = 0
  for index, line in ipairs(lines) do
    starts[index] = offset
    offset = offset + #line
    if index < #lines then
      offset = offset + 1
    end
  end
  return starts
end

local function offset_position(lines, starts, offset)
  local low = 1
  local high = #starts
  local found = 1
  while low <= high do
    local middle = math.floor((low + high) / 2)
    if starts[middle] <= offset then
      found = middle
      low = middle + 1
    else
      high = middle - 1
    end
  end
  return found, offset - starts[found]
end

local function char_exact_matches(lines, text)
  if text == '' or #lines == 0 then
    return {}
  end
  local content = table.concat(lines, '\n')
  local starts = line_starts(lines)
  local matches = {}
  local from = 1
  while from <= #content do
    local first, last = content:find(text, from, true)
    if not first then
      break
    end
    local start_line, start_column = offset_position(lines, starts, first - 1)
    local end_line, end_column = offset_position(lines, starts, last)
    matches[#matches + 1] = {
      start_line = start_line,
      end_line = end_line,
      start_column = start_column,
      end_column = end_column,
    }
    -- Advance one byte so overlapping occurrences are included.
    from = first + 1
  end
  return matches
end

local function exact_matches(lines, anchor, text)
  if anchor.mode == 'line' then
    return line_exact_matches(lines, text)
  end
  return char_exact_matches(lines, text)
end

local function context_evidence(lines, anchor, candidate)
  local before, after, expected_prefix, expected_suffix = contexts(anchor)
  local before_matches = 0
  local after_matches = 0

  for offset = 1, #before do
    local line = candidate.start_line - offset
    if line >= 1 and lines[line] == before[#before - offset + 1] then
      before_matches = before_matches + 1
    else
      break
    end
  end
  for offset = 1, #after do
    local line = candidate.end_line + offset
    if line <= #lines and lines[line] == after[offset] then
      after_matches = after_matches + 1
    else
      break
    end
  end

  local _, actual_prefix, actual_suffix, extract_err = M.extract(lines, {
    mode = anchor.mode,
    start_line = candidate.start_line,
    end_line = candidate.end_line,
    start_column = candidate.start_column,
    end_column = candidate.end_column,
  })
  if extract_err then
    return nil
  end

  local prefix_present = anchor.mode == 'char' and expected_prefix ~= ''
  local suffix_present = anchor.mode == 'char' and expected_suffix ~= ''
  local prefix_matches = prefix_present and actual_prefix == expected_prefix
  local suffix_matches = suffix_present and actual_suffix == expected_suffix

  -- When both line contexts or both same-line boundaries are available, a
  -- candidate must have evidence on both sides. This deliberately favors an
  -- orphan over silently attaching a note to plausible but unrelated code.
  if #before > 0 and #after > 0 and (before_matches == 0 or after_matches == 0) then
    return nil
  end
  if prefix_present and suffix_present and (not prefix_matches or not suffix_matches) then
    return nil
  end

  return before_matches + after_matches + (prefix_matches and 1 or 0) + (suffix_matches and 1 or 0)
end

local function candidate_key(candidate)
  return table.concat({
    candidate.start_line,
    candidate.end_line,
    candidate.start_column,
    candidate.end_column,
  }, ':')
end

local function unique_candidates(candidates)
  local result = {}
  local seen = {}
  for _, candidate in ipairs(candidates) do
    local key = candidate_key(candidate)
    if not seen[key] then
      seen[key] = true
      result[#result + 1] = candidate
    end
  end
  return result
end

local function supported_candidate(lines, anchor, candidates, config)
  local best
  local best_score
  local second_score
  for _, candidate in ipairs(unique_candidates(candidates)) do
    local score = context_evidence(lines, anchor, candidate)
    if score and score >= config.min_context_lines then
      if not best_score or score > best_score then
        second_score = best_score
        best = candidate
        best_score = score
      elseif not second_score or score > second_score then
        second_score = score
      end
    end
  end
  if not best then
    return nil
  end
  if second_score and best_score - second_score < config.context_score_margin then
    return nil
  end
  return best
end

local function full_line_sequence_matches(lines, sequence)
  if #sequence == 0 or #sequence > #lines then
    return {}
  end
  local starts = {}
  for first = 1, #lines - #sequence + 1 do
    local equal = true
    for offset = 1, #sequence do
      if lines[first + offset - 1] ~= sequence[offset] then
        equal = false
        break
      end
    end
    if equal then
      starts[#starts + 1] = first
    end
  end
  return starts
end

local function line_context_candidates(lines, anchor, config)
  local candidates = {}
  local old_length = anchor.end_line - anchor.start_line + 1
  if old_length <= config.max_candidate_lines then
    for first = 1, #lines - old_length + 1 do
      candidates[#candidates + 1] = {
        start_line = first,
        end_line = first + old_length - 1,
        start_column = 0,
        end_column = 0,
      }
    end
  end

  -- Full contexts on both sides define a variable-sized range without using
  -- its old position or length. This safely handles formatter expansion and
  -- contraction while the editor is closed.
  local before, after = contexts(anchor)
  if #before > 0 and #after > 0 then
    local before_starts = full_line_sequence_matches(lines, before)
    local after_starts = full_line_sequence_matches(lines, after)
    for _, before_start in ipairs(before_starts) do
      local first = before_start + #before
      for _, after_start in ipairs(after_starts) do
        local last = after_start - 1
        local length = last - first + 1
        if length >= 1 and length <= config.max_candidate_lines then
          candidates[#candidates + 1] = {
            start_line = first,
            end_line = last,
            start_column = 0,
            end_column = 0,
          }
        end
      end
    end
  end
  return candidates
end

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function ends_with(value, suffix)
  return suffix == '' or value:sub(-#suffix) == suffix
end

local function char_context_candidates(lines, anchor, config)
  local candidates = {}
  local old_span = anchor.end_line - anchor.start_line + 1

  -- Keep a fixed-shape candidate available for changes that preserve the
  -- selected columns and are identified by surrounding line context.
  if old_span <= config.max_candidate_lines then
    for first = 1, #lines - old_span + 1 do
      local last = first + old_span - 1
      if
        anchor.start_column <= #lines[first]
        and anchor.end_column <= #lines[last]
        and (first ~= last or anchor.end_column >= anchor.start_column)
      then
        candidates[#candidates + 1] = {
          start_line = first,
          end_line = last,
          start_column = anchor.start_column,
          end_column = anchor.end_column,
        }
      end
    end
  end

  local _, _, prefix, suffix = contexts(anchor)
  local starts = {}
  local finishes = {}
  if prefix ~= '' then
    for index, line in ipairs(lines) do
      if starts_with(line, prefix) then
        starts[#starts + 1] = { line = index, column = #prefix }
      end
    end
  end
  if suffix ~= '' then
    for index, line in ipairs(lines) do
      if ends_with(line, suffix) then
        finishes[#finishes + 1] = { line = index, column = #line - #suffix }
      end
    end
  end

  if prefix ~= '' and suffix ~= '' then
    for _, first in ipairs(starts) do
      for _, last in ipairs(finishes) do
        local span = last.line - first.line + 1
        if
          span >= 1
          and span <= config.max_candidate_lines
          and (first.line ~= last.line or last.column >= first.column)
        then
          candidates[#candidates + 1] = {
            start_line = first.line,
            end_line = last.line,
            start_column = first.column,
            end_column = last.column,
          }
        end
      end
    end
  elseif prefix ~= '' and old_span <= config.max_candidate_lines then
    for _, first in ipairs(starts) do
      local last = first.line + old_span - 1
      if last <= #lines and anchor.end_column <= #lines[last] then
        candidates[#candidates + 1] = {
          start_line = first.line,
          end_line = last,
          start_column = first.column,
          end_column = anchor.end_column,
        }
      end
    end
  elseif suffix ~= '' and old_span <= config.max_candidate_lines then
    for _, last in ipairs(finishes) do
      local first = last.line - old_span + 1
      if first >= 1 and anchor.start_column <= #lines[first] then
        candidates[#candidates + 1] = {
          start_line = first,
          end_line = last.line,
          start_column = anchor.start_column,
          end_column = last.column,
        }
      end
    end
  end
  return candidates
end

local function result_at(lines, anchor, candidate, digest, stale, method)
  local text, prefix, suffix, err = M.extract(lines, {
    mode = anchor.mode,
    start_line = candidate.start_line,
    end_line = candidate.end_line,
    start_column = candidate.start_column,
    end_column = candidate.end_column,
  })
  if err then
    return nil, err
  end
  return {
    start_line = candidate.start_line,
    end_line = candidate.end_line,
    start_column = candidate.start_column,
    end_column = candidate.end_column,
    valid = true,
    stale = stale,
    method = method,
    failure_reason = stale and 'Stored review text changed; confirm the context-based location'
      or nil,
    current_text = text,
    current_prefix = prefix,
    current_suffix = suffix,
    file_sha256 = digest,
  }
end

local function failed_result(anchor, digest, method, reason)
  local position = normalized_position(anchor)
  position.valid = false
  position.stale = true
  position.method = method
  position.failure_reason = reason
  position.file_sha256 = digest
  return position
end

--- Reconcile durable anchor metadata against an array of current buffer lines.
---
--- This function is intentionally independent of buffers, extmarks, files,
--- and Git. Callers decide when to load content and persist the returned
--- metadata. `current_text` on a stale result describes the proposed range;
--- callers must not promote it to trusted anchor text until the user confirms
--- that candidate.
--- @param lines string[]
--- @param anchor table
--- @param config? table Full plugin configuration or a relocation table.
--- @return table result
function M.reconcile(lines, anchor, config)
  local lines_err = validate_lines(lines)
  if lines_err then
    return {
      start_line = 1,
      end_line = 1,
      start_column = 0,
      end_column = 0,
      valid = false,
      stale = true,
      method = 'invalid',
      failure_reason = lines_err,
    }
  end
  local anchor_err = validate_anchor(anchor)
  if anchor_err then
    return {
      start_line = type(anchor) == 'table' and anchor.start_line or 1,
      end_line = type(anchor) == 'table' and anchor.end_line or 1,
      start_column = type(anchor) == 'table' and anchor.start_column or 0,
      end_column = type(anchor) == 'table' and anchor.end_column or 0,
      valid = false,
      stale = true,
      method = 'invalid',
      failure_reason = anchor_err,
    }
  end

  local digest = assert(M.file_sha256(lines))
  if type(anchor.current_text) ~= 'string' then
    return failed_result(anchor, digest, 'invalid', 'Anchor has no stored current text')
  end
  if anchor.mode == 'char' and anchor.current_text == '' then
    return failed_result(anchor, digest, 'invalid', 'Character anchors cannot track empty text')
  end

  local old_length = anchor.end_line - anchor.start_line + 1
  local options = relocation_config(config, old_length)
  local stored_text = M.extract(lines, anchor)
  local stored_digest = anchor.file_sha256 or anchor.current_file_sha256
  if stored_text == anchor.current_text and stored_digest == digest then
    return assert(
      result_at(lines, anchor, normalized_position(anchor), digest, false, 'stored_hash')
    )
  end

  if not options.enabled then
    return failed_result(
      anchor,
      digest,
      'disabled',
      'Stored review range no longer has a matching file fingerprint and relocation is disabled'
    )
  end

  -- Always enumerate the entire file. A nearby duplicate is not safer than a
  -- distant duplicate, so search-window distance is never a deciding signal.
  local exact = exact_matches(lines, anchor, anchor.current_text)
  if #exact == 1 then
    return assert(result_at(lines, anchor, exact[1], digest, false, 'unique_exact'))
  end
  if #exact > 1 then
    local supported = supported_candidate(lines, anchor, exact, options)
    if supported then
      return assert(result_at(lines, anchor, supported, digest, false, 'context_exact'))
    end
    return failed_result(
      anchor,
      digest,
      'orphan',
      'Stored review text occurs more than once without uniquely identifying context'
    )
  end

  local candidates = anchor.mode == 'line' and line_context_candidates(lines, anchor, options)
    or char_context_candidates(lines, anchor, options)
  local supported = supported_candidate(lines, anchor, candidates, options)
  if supported then
    return assert(result_at(lines, anchor, supported, digest, true, 'context'))
  end
  return failed_result(
    anchor,
    digest,
    'orphan',
    'Could not safely relocate the stored review range'
  )
end

return M
