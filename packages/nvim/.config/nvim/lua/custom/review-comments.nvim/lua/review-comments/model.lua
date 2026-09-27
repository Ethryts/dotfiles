local util = require('review_comments.util')

local M = {}

M.SCHEMA_VERSION = 3

local function is_list(value)
  if type(value) ~= 'table' then
    return false
  end
  local check = vim.islist or vim.tbl_islist
  return check(value)
end

local function is_integer(value)
  return type(value) == 'number' and value % 1 == 0
end

local function is_object(value)
  return type(value) == 'table' and not is_list(value)
end

local function is_nonempty_string(value)
  return type(value) == 'string' and value ~= ''
end

local function is_optional_nonempty_string(value)
  return value == nil or is_nonempty_string(value)
end

local function is_string_list(value)
  if not is_list(value) then
    return false
  end
  for _, item in ipairs(value) do
    if type(item) ~= 'string' then
      return false
    end
  end
  return true
end

local function valid_source(source)
  if not is_object(source) then
    return false
  end
  if source.kind == 'worktree' then
    return source.side == nil and source.content_sha256 == nil
  end
  if source.kind == 'snapshot' then
    return (source.side == 'left' or source.side == 'right')
      and is_optional_nonempty_string(source.content_sha256)
  end
  return false
end

local function valid_file_anchor(value)
  if not is_object(value) or not util.is_safe_relative(value.created_path) then
    return false
  end
  if
    not is_object(value.tracking)
    or not util.is_safe_relative(value.tracking.path)
    or not is_optional_nonempty_string(value.tracking.commit)
  then
    return false
  end
  if value.history == nil then
    return true
  end
  if not is_list(value.history) then
    return false
  end
  for _, entry in ipairs(value.history) do
    if
      not is_object(entry)
      or not util.is_safe_relative(entry.from)
      or not util.is_safe_relative(entry.to)
      or not is_nonempty_string(entry.method)
      or not is_nonempty_string(entry.at)
      or (
        entry.score ~= nil and (not is_integer(entry.score) or entry.score < 0 or entry.score > 100)
      )
    then
      return false
    end
  end
  return true
end

local function source_from_args(args)
  if args.source ~= nil then
    return vim.deepcopy(args.source)
  end
  if args.view == 'left' then
    return {
      kind = 'snapshot',
      side = 'left',
    }
  end
  return { kind = 'worktree' }
end

--- Create a new, empty review session.
--- @param opts? {started_from?: {commit?: string, branch?: string}, scope?: table}
--- @return table
function M.new_session(opts)
  opts = opts or {}
  local now = util.timestamp()
  local started_from = opts.started_from or vim.empty_dict()
  local scope = opts.scope or { kind = 'unscoped' }
  return {
    schema_version = M.SCHEMA_VERSION,
    revision = 0,
    session = {
      id = util.new_id('session'),
      created_at = now,
      updated_at = now,
      started_from = vim.deepcopy(started_from),
      scope = vim.deepcopy(scope),
    },
    comments = {},
  }
end

local function valid_scope(scope)
  if not is_object(scope) or not is_nonempty_string(scope.kind) then
    return false
  end
  if scope.kind == 'unscoped' then
    return true
  end
  if scope.kind ~= 'git_diff' then
    return false
  end
  return is_object(scope.base)
    and is_nonempty_string(scope.base.requested)
    and is_nonempty_string(scope.base.commit)
    and is_object(scope.target)
    and scope.target.kind == 'worktree'
    and is_optional_nonempty_string(scope.target.head_commit_at_start)
    and is_optional_nonempty_string(scope.target.branch_at_start)
end

function M.validate(document)
  if not is_object(document) then
    return false, 'Review document must be a JSON object'
  end
  if document.schema_version ~= M.SCHEMA_VERSION then
    return false,
      string.format('Unsupported review schema version: %s', tostring(document.schema_version))
  end
  if not is_integer(document.revision) or document.revision < 0 then
    return false, 'Review document has an invalid revision'
  end
  if
    not is_object(document.session)
    or not is_nonempty_string(document.session.id)
    or not is_nonempty_string(document.session.created_at)
    or not is_nonempty_string(document.session.updated_at)
    or not is_object(document.session.started_from)
    or not valid_scope(document.session.scope)
    or not is_optional_nonempty_string(document.session.started_from.commit)
    or not is_optional_nonempty_string(document.session.started_from.branch)
  then
    return false, 'Review document has no valid session'
  end
  if not is_list(document.comments) then
    return false, 'Review document comments must be an array'
  end

  local ids = {}
  for index, comment in ipairs(document.comments) do
    if not is_object(comment) then
      return false, string.format('Comment %d is not an object', index)
    end
    if not is_nonempty_string(comment.id) or ids[comment.id] then
      return false, string.format('Comment %d has an invalid or duplicate ID', index)
    end
    ids[comment.id] = true
    if not util.is_safe_relative(comment.file) then
      return false, string.format('Comment %s has an unsafe file path', comment.id)
    end
    if
      not is_nonempty_string(comment.comment)
      or not is_nonempty_string(comment.created_at)
      or not is_nonempty_string(comment.updated_at)
      or not is_optional_nonempty_string(comment.relocated_at)
      or (comment.status ~= 'active' and comment.status ~= 'resolved')
      or not is_optional_nonempty_string(comment.resolved_at)
      or (comment.status == 'active' and comment.resolved_at ~= nil)
      or (comment.status == 'resolved' and comment.resolved_at == nil)
    then
      return false, string.format('Comment %s has invalid review metadata', comment.id)
    end
    local anchor = comment.anchor
    if
      not is_object(anchor)
      or anchor.kind ~= 'line_range'
      or (anchor.mode ~= 'line' and anchor.mode ~= 'char')
      or not is_integer(anchor.start_line)
      or not is_integer(anchor.end_line)
      or anchor.start_line < 1
      or anchor.end_line < anchor.start_line
      or not is_integer(anchor.start_column)
      or not is_integer(anchor.end_column)
      or anchor.start_column < 0
      or anchor.end_column < 0
      or (anchor.mode == 'line' and (anchor.start_column ~= 0 or anchor.end_column ~= 0))
      or (
        anchor.mode == 'char'
        and anchor.start_line == anchor.end_line
        and anchor.end_column <= anchor.start_column
      )
    then
      return false, string.format('Comment %s has an invalid line-range anchor', comment.id)
    end
    if
      type(anchor.original_text) ~= 'string'
      or not is_nonempty_string(anchor.original_text_sha256)
      or type(anchor.current_text) ~= 'string'
      or not is_nonempty_string(anchor.current_text_sha256)
      or type(anchor.original_prefix) ~= 'string'
      or type(anchor.original_suffix) ~= 'string'
      or type(anchor.current_prefix) ~= 'string'
      or type(anchor.current_suffix) ~= 'string'
      or not is_optional_nonempty_string(anchor.current_file_sha256)
      or not is_optional_nonempty_string(anchor.resolution_method)
      or not is_string_list(anchor.original_context_before)
      or not is_string_list(anchor.original_context_after)
      or not is_string_list(anchor.current_context_before)
      or not is_string_list(anchor.current_context_after)
      or type(anchor.valid) ~= 'boolean'
      or type(anchor.stale) ~= 'boolean'
      or not valid_source(anchor.source)
      or (anchor.source.kind == 'worktree' and not valid_file_anchor(anchor.file_anchor))
      or (anchor.source.kind == 'snapshot' and anchor.file_anchor ~= nil)
      or not is_optional_nonempty_string(anchor.failure_reason)
    then
      return false, string.format('Comment %s has invalid anchor metadata', comment.id)
    end
  end
  return true
end

local migrations = {
  [1] = function(document)
    document.revision = 0
    if type(document.session) == 'table' then
      document.session.started_from = document.session.started_from or vim.empty_dict()
    end
    if type(document.comments) == 'table' then
      for _, comment in ipairs(document.comments) do
        if type(comment) == 'table' then
          comment.updated_at = comment.updated_at or comment.created_at
          comment.status = comment.status or 'active'
          if comment.status == 'active' then
            comment.resolved_at = nil
          end
          if type(comment.anchor) == 'table' and comment.anchor.source == nil then
            if comment.anchor.view == 'left' then
              comment.anchor.source = { kind = 'snapshot', side = 'left' }
            else
              comment.anchor.source = { kind = 'worktree' }
            end
          end
          if type(comment.anchor) == 'table' then
            comment.anchor.view = nil
          end
        end
      end
    end
    document.schema_version = 2
    return document
  end,
  [2] = function(document)
    if type(document.session) == 'table' then
      document.session.scope = document.session.scope or { kind = 'unscoped' }
    end
    if type(document.comments) == 'table' then
      for _, comment in ipairs(document.comments) do
        if type(comment) == 'table' and type(comment.anchor) == 'table' then
          if
            type(comment.file) == 'string'
            and comment.file ~= ''
            and comment.anchor.source
            and comment.anchor.source.kind == 'worktree'
          then
            comment.anchor.file_anchor = comment.anchor.file_anchor
              or {
                created_path = comment.file,
                tracking = {
                  path = comment.file,
                  commit = document.session
                      and document.session.started_from
                      and document.session.started_from.commit
                    or nil,
                },
                history = {},
              }
          elseif comment.anchor.source and comment.anchor.source.kind == 'snapshot' then
            comment.anchor.file_anchor = nil
          end
          comment.anchor.mode = comment.anchor.mode or 'line'
          comment.anchor.current_text_sha256 = comment.anchor.current_text_sha256
            or vim.fn.sha256(comment.anchor.current_text or '')
          comment.anchor.original_prefix = comment.anchor.original_prefix or ''
          comment.anchor.original_suffix = comment.anchor.original_suffix or ''
          comment.anchor.current_prefix = comment.anchor.current_prefix or ''
          comment.anchor.current_suffix = comment.anchor.current_suffix or ''
          comment.anchor.resolution_method = comment.anchor.resolution_method
            or 'migrated_line_range'
        end
      end
    end
    document.schema_version = 3
    return document
  end,
}

--- Upgrade a decoded document to the current schema without mutating the input.
--- @param document table
--- @return table? document
--- @return table? migration `{ from = integer, to = integer }` when upgraded
--- @return string? error
function M.upgrade(document)
  if type(document) ~= 'table' then
    return nil, nil, 'Review document must be a JSON object'
  end
  if not is_integer(document.schema_version) then
    return nil, nil, 'Review document has no valid schema version'
  end
  if document.schema_version > M.SCHEMA_VERSION then
    return nil,
      nil,
      string.format('Unsupported future review schema version: %s', document.schema_version)
  end
  if document.schema_version < 1 then
    return nil, nil, string.format('Unsupported review schema version: %s', document.schema_version)
  end

  local upgraded = vim.deepcopy(document)
  local from = upgraded.schema_version
  while upgraded.schema_version < M.SCHEMA_VERSION do
    local migrate = migrations[upgraded.schema_version]
    if not migrate then
      return nil,
        nil,
        string.format('No migration from review schema version %s', upgraded.schema_version)
    end
    local ok, result = pcall(migrate, upgraded)
    if not ok then
      return nil, nil, 'Review schema migration failed: ' .. tostring(result)
    end
    upgraded = result
  end

  local valid, validation_err = M.validate(upgraded)
  if not valid then
    return nil, nil, validation_err
  end
  if from == upgraded.schema_version then
    return upgraded
  end
  return upgraded, { from = from, to = upgraded.schema_version }
end

function M.create_comment(args)
  local now = util.timestamp()
  local original_text = args.selected_text or table.concat(args.selected_lines or {}, '\n')
  local mode = args.mode == 'char' and 'char' or 'line'
  local source = source_from_args(args)
  local file_anchor
  if source.kind == 'worktree' then
    local tracking = args.tracking or { path = args.file, commit = args.tracking_commit }
    file_anchor = {
      created_path = args.file,
      tracking = vim.deepcopy(tracking),
      history = {},
    }
  end
  return {
    id = util.new_id('comment'),
    file = args.file,
    comment = args.comment,
    created_at = now,
    updated_at = now,
    status = 'active',
    anchor = {
      kind = 'line_range',
      mode = mode,
      start_line = args.start_line,
      end_line = args.end_line,
      start_column = mode == 'char' and (args.start_column or 0) or 0,
      end_column = mode == 'char' and (args.end_column or 0) or 0,
      original_text = original_text,
      original_text_sha256 = vim.fn.sha256(original_text),
      current_text = original_text,
      current_text_sha256 = vim.fn.sha256(original_text),
      original_prefix = args.prefix or '',
      original_suffix = args.suffix or '',
      current_prefix = args.prefix or '',
      current_suffix = args.suffix or '',
      original_context_before = vim.deepcopy(args.context_before or {}),
      original_context_after = vim.deepcopy(args.context_after or {}),
      current_context_before = vim.deepcopy(args.context_before or {}),
      current_context_after = vim.deepcopy(args.context_after or {}),
      valid = true,
      stale = false,
      source = source,
      current_file_sha256 = args.file_sha256,
      resolution_method = 'created',
      file_anchor = file_anchor,
    },
  }
end

function M.find(document, id)
  for _, comment in ipairs(document.comments) do
    if comment.id == id then
      return comment
    end
  end
  return nil
end

function M.find_index(document, id)
  for index, comment in ipairs(document.comments) do
    if comment.id == id then
      return index, comment
    end
  end
  return nil
end

function M.set_comment_text(comment, text)
  text = vim.trim(text or '')
  if text == '' then
    return false, 'Review comment text cannot be empty'
  end
  if comment.comment == text then
    return false
  end
  comment.comment = text
  comment.updated_at = util.timestamp()
  return true
end

function M.set_status(comment, status)
  if status ~= 'active' and status ~= 'resolved' then
    return false, 'Review status must be active or resolved'
  end
  if comment.status == status then
    return false
  end
  local now = util.timestamp()
  comment.status = status
  comment.updated_at = now
  comment.resolved_at = status == 'resolved' and now or nil
  return true
end

function M.relocate_comment(comment, args)
  local now = util.timestamp()
  local current_text = args.selected_text or table.concat(args.selected_lines or {}, '\n')
  local mode = args.mode == 'char' and 'char' or 'line'
  comment.file = args.file
  comment.updated_at = now
  comment.relocated_at = now
  comment.anchor.start_line = args.start_line
  comment.anchor.end_line = args.end_line
  comment.anchor.mode = mode
  comment.anchor.start_column = mode == 'char' and (args.start_column or 0) or 0
  comment.anchor.end_column = mode == 'char' and (args.end_column or 0) or 0
  comment.anchor.current_text = current_text
  comment.anchor.current_text_sha256 = vim.fn.sha256(current_text)
  comment.anchor.current_prefix = args.prefix or ''
  comment.anchor.current_suffix = args.suffix or ''
  comment.anchor.current_context_before = vim.deepcopy(args.context_before or {})
  comment.anchor.current_context_after = vim.deepcopy(args.context_after or {})
  comment.anchor.current_file_sha256 = args.file_sha256
  comment.anchor.valid = true
  comment.anchor.stale = false
  comment.anchor.resolution_method = 'manual'
  comment.anchor.source = source_from_args(args)
  comment.anchor.failure_reason = nil
  if comment.anchor.source.kind == 'worktree' then
    comment.anchor.file_anchor = comment.anchor.file_anchor
      or {
        created_path = args.file,
        history = {},
      }
    comment.anchor.file_anchor.tracking =
      vim.deepcopy(args.tracking or { path = args.file, commit = args.tracking_commit })
  else
    comment.anchor.file_anchor = nil
  end
  return true
end

function M.counts(document)
  local counts = { total = 0, active = 0, resolved = 0, stale = 0, orphaned = 0 }
  for _, comment in ipairs(document.comments) do
    counts.total = counts.total + 1
    counts[comment.status] = counts[comment.status] + 1
    if comment.anchor.stale then
      counts.stale = counts.stale + 1
    end
    if comment.anchor.valid == false then
      counts.orphaned = counts.orphaned + 1
    end
  end
  return counts
end

function M.touch(document)
  document.session.updated_at = util.timestamp()
end

return M
