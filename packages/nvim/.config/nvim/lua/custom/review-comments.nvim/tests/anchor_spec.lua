local h = require('tests.helpers')
local anchor = require('review_comments.anchor')

h.run('anchor_spec', function()
  local config = {
    relocation = {
      enabled = true,
      min_context_lines = 2,
      context_score_margin = 1,
      max_candidate_lines = 20,
    },
  }

  local function line_anchor(lines, start_line, end_line, before, after)
    local value = {
      mode = 'line',
      start_line = start_line,
      end_line = end_line,
      start_column = 0,
      end_column = 0,
      current_context_before = before or {},
      current_context_after = after or {},
      file_sha256 = assert(anchor.file_sha256(lines)),
    }
    value.current_text = assert(anchor.extract(lines, value))
    return value
  end

  local function char_anchor(lines, start_line, start_column, end_line, end_column, before, after)
    local value = {
      mode = 'char',
      start_line = start_line,
      end_line = end_line,
      start_column = start_column,
      end_column = end_column,
      current_context_before = before or {},
      current_context_after = after or {},
      file_sha256 = assert(anchor.file_sha256(lines)),
    }
    local text, prefix, suffix = anchor.extract(lines, value)
    value.current_text = assert(text)
    value.current_prefix = prefix
    value.current_suffix = suffix
    return value
  end

  do
    local lines = { 'before', 'target', 'after' }
    local stored = line_anchor(lines, 2, 2, { 'before' }, { 'after' })
    local result = anchor.reconcile(lines, stored, config)
    h.equal(result.valid, true, 'an unchanged stored range should remain valid')
    h.equal(result.stale, false, 'an unchanged stored range should remain trusted')
    h.equal(result.method, 'stored_hash', 'an unchanged file should use its fingerprint')
    h.equal(result.start_line, 2, 'the stored line should be preserved')
    h.equal(result.current_text, 'target', 'trusted results should return current text')
  end

  do
    local original = { 'before', 'target', 'after' }
    local stored = line_anchor(original, 2, 2, { 'before' }, { 'after' })
    local current = { 'inserted one', 'inserted two', 'before', 'target', 'after' }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.start_line, 4, 'a unique exact range should follow inserted lines')
    h.equal(result.end_line, 4, 'a relocated line range should retain its length')
    h.equal(result.method, 'unique_exact', 'global exact relocation should be explicit')
    h.equal(result.stale, false, 'a unique exact match should be trusted')
  end

  do
    local original = { 'target', 'unrelated' }
    local stored = line_anchor(original, 1, 1)
    local current = {
      'target',
      'nearby',
      'many',
      'lines',
      'between',
      'the matches',
      'target',
    }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.valid, false, 'near and far exact duplicates must remain unresolved')
    h.equal(result.stale, true, 'ambiguous duplicates should be stale')
    h.equal(result.method, 'orphan', 'distance must not choose between duplicates')
  end

  do
    local original = { 'unique before', 'target', 'unique after' }
    local stored = line_anchor(original, 2, 2, { 'unique before' }, { 'unique after' })
    local current = {
      'other before',
      'target',
      'other after',
      'unique before',
      'target',
      'unique after',
    }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.valid, true, 'stored context should disambiguate exact duplicates')
    h.equal(result.start_line, 5, 'the context-supported duplicate should win')
    h.equal(result.method, 'context_exact', 'context-supported exact matches are trusted')
    h.equal(result.stale, false, 'an exact context-supported duplicate should not be stale')
  end

  do
    local original = { 'before', 'old target', 'after' }
    local stored = line_anchor(original, 2, 2, { 'before' }, { 'after' })
    local current = { 'before', 'rewritten target', 'after' }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.valid, true, 'unique context should retain a changed-text candidate')
    h.equal(result.stale, true, 'changed text must require confirmation')
    h.equal(result.method, 'context', 'changed text should use context relocation')
    h.equal(result.current_text, 'rewritten target', 'a stale candidate should expose current text')
    h.truthy(result.failure_reason, 'a stale candidate should explain why it needs confirmation')
  end

  do
    local original = { 'before', 'one old line', 'after' }
    local stored = line_anchor(original, 2, 2, { 'before' }, { 'after' })
    local current = {
      'before',
      'expanded one',
      'expanded two',
      'expanded three',
      'after',
    }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.valid, true, 'unique before/after boundaries should retain an expanded range')
    h.equal(result.stale, true, 'an expanded range should require confirmation')
    h.equal(result.start_line, 2, 'the expanded range should begin after the before context')
    h.equal(result.end_line, 4, 'the expanded range should end before the after context')
    h.equal(
      result.current_text,
      'expanded one\nexpanded two\nexpanded three',
      'expanded candidate text should be returned in full'
    )
  end

  do
    local original = { 'before', 'old one', 'old two', 'old three', 'after' }
    local stored = line_anchor(original, 2, 4, { 'before' }, { 'after' })
    local current = { 'before', 'contracted', 'after' }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.valid, true, 'unique before/after boundaries should retain a contracted range')
    h.equal(result.stale, true, 'a contracted range should require confirmation')
    h.equal(result.start_line, 2, 'the contracted range should begin after its before context')
    h.equal(result.end_line, 2, 'the contracted range should end before its after context')
    h.equal(result.current_text, 'contracted', 'contracted candidate text should be returned')
  end

  do
    local lines = { 'local value = old + 1' }
    local start_column = #'local value = '
    local stored = char_anchor(lines, 1, start_column, 1, start_column + #'old')
    local text, prefix, suffix = anchor.extract(lines, stored)
    h.equal(text, 'old', 'same-line character extraction should use byte columns')
    h.equal(prefix, 'local value = ', 'same-line extraction should preserve its prefix')
    h.equal(suffix, ' + 1', 'same-line extraction should preserve its suffix')
  end

  do
    local lines = { 'call(foo,', '  bar,', '  baz)' }
    local stored = char_anchor(lines, 1, #'call(', 3, #'  baz')
    local text, prefix, suffix = anchor.extract(lines, stored)
    h.equal(text, 'foo,\n  bar,\n  baz', 'multiline character extraction should preserve newlines')
    h.equal(prefix, 'call(', 'multiline extraction should retain the first-line prefix')
    h.equal(suffix, ')', 'multiline extraction should retain the last-line suffix')

    local current = { '-- inserted', 'call(foo,', '  bar,', '  baz)' }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.start_line, 2, 'a multiline character range should relocate exactly')
    h.equal(result.end_line, 4, 'a multiline character range should preserve its end line')
    h.equal(result.start_column, #'call(', 'multiline relocation should retain its start byte')
    h.equal(result.end_column, #'  baz', 'multiline relocation should retain its end byte')
    h.equal(result.current_text, text, 'multiline relocation should reproduce the stored text')
  end

  do
    local original = { 'préfixe = café!' }
    local start_column = #'préfixe = '
    local stored = char_anchor(original, 1, start_column, 1, start_column + #'café')
    local extracted = anchor.extract(original, stored)
    h.equal(extracted, 'café', 'character columns should be UTF-8 byte offsets')

    local current = { '-- inserted', 'préfixe = café!' }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.start_line, 2, 'a Unicode character range should relocate exactly')
    h.equal(result.start_column, start_column, 'relocation should preserve the byte start column')
    h.equal(
      result.end_column,
      start_column + #'café',
      'relocation should preserve the exclusive byte end column'
    )
    h.equal(result.current_text, 'café', 'Unicode exact relocation should retain complete text')
  end

  do
    local original = { 'return calculate(old_value);' }
    local prefix = 'return calculate('
    local stored = char_anchor(original, 1, #prefix, 1, #prefix + #'old_value')
    local current = { '-- moved while closed', 'return calculate(new_value);' }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.valid, true, 'same-line boundaries should identify rewritten character text')
    h.equal(result.stale, true, 'rewritten character text should require confirmation')
    h.equal(result.start_line, 2, 'same-line boundary relocation should follow inserted lines')
    h.equal(result.start_column, #prefix, 'the matching prefix should define the start column')
    h.equal(result.end_column, #prefix + #'new_value', 'the suffix should define the end column')
    h.equal(
      result.current_text,
      'new_value',
      'the stale character candidate should expose new text'
    )
    h.equal(result.current_prefix, prefix, 'the reconciler should return the candidate prefix')
    h.equal(result.current_suffix, ');', 'the reconciler should return the candidate suffix')
  end

  do
    local original = { 'before', 'target', 'after' }
    local stored = line_anchor(original, 2, 2, { 'before' }, { 'after' })
    local current = { 'completely', 'different', 'file' }
    local result = anchor.reconcile(current, stored, config)
    h.equal(result.valid, false, 'an anchor with no exact or context match should be orphaned')
    h.equal(result.stale, true, 'an orphaned anchor should remain stale')
    h.equal(result.method, 'orphan', 'orphaned anchors should be distinguishable by method')
    h.truthy(result.failure_reason, 'an orphaned anchor should retain a failure reason')
    h.equal(
      result.file_sha256,
      anchor.file_sha256(current),
      'even orphan results should fingerprint the inspected file'
    )
  end
end)
