local M = {}

local function qualifiers(comment)
  local result = {}
  local anchor = comment.anchor
  if anchor.valid == false then
    table.insert(result, 'orphaned location')
  elseif anchor.stale == true then
    table.insert(result, 'candidate location')
  end
  if anchor.source and anchor.source.kind == 'snapshot' then
    table.insert(result, string.format('historical %s side', anchor.source.side or 'snapshot'))
  end
  if comment.status == 'resolved' then
    table.insert(result, 'resolved')
  end
  if anchor.failure_reason then
    table.insert(result, anchor.failure_reason)
  end
  return #result > 0 and ' [' .. table.concat(result, '; ') .. ']' or ''
end

local function location(comment)
  local anchor = comment.anchor
  local range = anchor.start_line == anchor.end_line and tostring(anchor.start_line)
    or string.format('%d-%d', anchor.start_line, anchor.end_line)
  if anchor.mode == 'char' then
    -- Columns are 1-based for humans; the end column remains exclusive.
    range = string.format('%s:%d-%d', range, (anchor.start_column or 0) + 1, anchor.end_column or 0)
  end
  return string.format('%s:%s%s', comment.file, range, qualifiers(comment))
end

--- Render review comments as provider-neutral plain text.
--- @param document table
--- @param config table
--- @param opts? {include_resolved?: boolean}
function M.render(document, config, opts)
  opts = opts or {}
  local blocks = {}
  for _, comment in ipairs(document.comments) do
    if opts.include_resolved or comment.status ~= 'resolved' then
      local lines = { location(comment), '', comment.comment }
      if config.clipboard.include_original_text and comment.anchor.original_text ~= '' then
        vim.list_extend(lines, { '', 'Original selection:', '', comment.anchor.original_text })
      end
      if
        config.clipboard.include_current_text
        and comment.anchor.current_text ~= ''
        and (
          not config.clipboard.include_original_text
          or comment.anchor.current_text ~= comment.anchor.original_text
        )
      then
        vim.list_extend(lines, { '', 'Current selection:', '', comment.anchor.current_text })
      end
      table.insert(blocks, table.concat(lines, '\n'))
    end
  end
  if #blocks == 0 then
    return ''
  end
  local scope = document.session and document.session.scope or nil
  if scope and scope.kind == 'git_diff' and scope.base then
    table.insert(
      blocks,
      1,
      string.format(
        'Review scope: %s (%s) -> worktree',
        scope.base.requested,
        scope.base.commit:sub(1, 12)
      )
    )
  end
  return table.concat(blocks, '\n\n---\n\n')
end

return M
