local util = require('review_comments.util')

local M = {}

M.defaults = {
  storage = {
    directory = '.local/review',
    current_file = 'current.json',
    archive_directory = 'archive',
    recovery_directory = 'recovery',
    add_to_git_exclude = true,
  },
  context_lines = 2,
  relocation = {
    enabled = true,
    min_context_lines = 2,
    context_score_margin = 1,
    max_candidate_lines = 200,
    git_renames = true,
    file_search = true,
    max_candidate_files = 2000,
    max_file_bytes = 2 * 1024 * 1024,
  },
  clipboard = {
    register = '+',
    include_original_text = false,
    include_current_text = false,
  },
  display = {
    highlight = 'ReviewCommentRegion',
    sign_highlight = 'ReviewCommentSign',
    sign_text = 'R',
    resolved_highlight = 'ReviewCommentResolved',
    resolved_sign_highlight = 'ReviewCommentResolvedSign',
    resolved_sign_text = '✓',
    candidate_highlight = 'ReviewCommentCandidate',
    candidate_sign_highlight = 'ReviewCommentCandidateSign',
    candidate_sign_text = '?',
    orphaned_sign_highlight = 'ReviewCommentOrphanedSign',
    orphaned_sign_text = '!',
  },
  list = {
    open = true,
    height = 12,
    -- Neovim's built-in DiffTool owns the active quickfix list. Use a
    -- location list in that case, or set this to false to refuse.
    difftool_fallback = 'loclist',
  },
  editor = {
    start_insert = true,
    spell = false,
    window = {},
  },
  session = {
    open_on_start = false,
    open_diff = nil,
  },
  notify = true,
  repository_root = nil,
  resolve_target = nil,
}

M.options = vim.deepcopy(M.defaults)

local function nonempty_string(value)
  return type(value) == 'string' and value ~= ''
end

local function integer(value, minimum)
  return type(value) == 'number' and value % 1 == 0 and value >= minimum
end

local function normalized_relative_path(value)
  if
    not nonempty_string(value)
    or value:find('\\', 1, true)
    or value:find('%c')
    or value:match('^%a:')
  then
    return nil
  end
  for component in value:gmatch('[^/]+') do
    if component == '..' then
      return nil
    end
  end
  local normalized = vim.fs.normalize(value):gsub('/+$', '')
  if normalized == '' or not util.is_safe_relative(normalized) then
    return nil
  end
  return normalized
end

local function basename(value)
  local normalized = normalized_relative_path(value)
  return normalized and normalized ~= '.' and not normalized:find('/', 1, true)
end

local function storage_paths_are_distinct(storage)
  local directory = normalized_relative_path(storage.directory)
  local current_file = normalized_relative_path(storage.current_file)
  local archive_directory = normalized_relative_path(storage.archive_directory)
  local recovery_directory = normalized_relative_path(storage.recovery_directory)
  if not directory or not current_file or not archive_directory or not recovery_directory then
    return false
  end

  local current = vim.fs.normalize(util.join(directory, current_file))
  local paths = {
    current,
    current .. '.lock',
    vim.fs.normalize(util.join(directory, archive_directory)),
    vim.fs.normalize(util.join(directory, recovery_directory)),
  }
  for left_index, left in ipairs(paths) do
    for right_index = left_index + 1, #paths do
      local right = paths[right_index]
      if
        left == right
        or vim.startswith(left, right .. '/')
        or vim.startswith(right, left .. '/')
      then
        return false
      end
    end
  end
  return true
end

local function sign_text(value)
  return type(value) == 'string' and vim.api.nvim_strwidth(value) <= 2
end

--- Validate a fully-merged configuration.
--- @return boolean
--- @return string? error
function M.validate(options)
  if type(options) ~= 'table' then
    return false, 'configuration must be a table'
  end
  local storage = options.storage
  if
    type(storage) ~= 'table'
    or not normalized_relative_path(storage.directory)
    or normalized_relative_path(storage.directory) == '.'
    or not basename(storage.current_file)
    or not normalized_relative_path(storage.archive_directory)
    or not normalized_relative_path(storage.recovery_directory)
    or not storage_paths_are_distinct(storage)
    or type(storage.add_to_git_exclude) ~= 'boolean'
  then
    return false, 'storage paths must be safe, repository-relative, and non-overlapping'
  end
  if not integer(options.context_lines, 0) then
    return false, 'context_lines must be a non-negative integer'
  end

  local relocation = options.relocation
  if
    type(relocation) ~= 'table'
    or relocation.search_window ~= nil
    or relocation.global_search ~= nil
    or type(relocation.enabled) ~= 'boolean'
    or not integer(relocation.min_context_lines, 1)
    or not integer(relocation.context_score_margin, 1)
    or not integer(relocation.max_candidate_lines, 1)
    or type(relocation.git_renames) ~= 'boolean'
    or type(relocation.file_search) ~= 'boolean'
    or not integer(relocation.max_candidate_files, 1)
    or not integer(relocation.max_file_bytes, 1)
  then
    return false,
      'relocation settings are invalid (exact-text uniqueness is always checked globally; search_window/global_search are unsupported)'
  end

  local clipboard = options.clipboard
  if
    type(clipboard) ~= 'table'
    or not nonempty_string(clipboard.register)
    or type(clipboard.include_original_text) ~= 'boolean'
    or type(clipboard.include_current_text) ~= 'boolean'
  then
    return false, 'clipboard settings are invalid'
  end

  local display = options.display
  if
    type(display) ~= 'table'
    or not nonempty_string(display.highlight)
    or not nonempty_string(display.sign_highlight)
    or not sign_text(display.sign_text)
    or not nonempty_string(display.resolved_highlight)
    or not nonempty_string(display.resolved_sign_highlight)
    or not sign_text(display.resolved_sign_text)
    or not nonempty_string(display.candidate_highlight)
    or not nonempty_string(display.candidate_sign_highlight)
    or not sign_text(display.candidate_sign_text)
    or not nonempty_string(display.orphaned_sign_highlight)
    or not sign_text(display.orphaned_sign_text)
  then
    return false, 'display highlights must be named and sign text must fit in two cells'
  end

  local list = options.list
  if
    type(list) ~= 'table'
    or type(list.open) ~= 'boolean'
    or not integer(list.height, 1)
    or (list.difftool_fallback ~= 'loclist' and list.difftool_fallback ~= false)
  then
    return false, 'list settings are invalid'
  end
  if type(options.notify) ~= 'boolean' then
    return false, 'notify must be boolean'
  end
  local editor = options.editor
  if
    type(editor) ~= 'table'
    or type(editor.start_insert) ~= 'boolean'
    or type(editor.spell) ~= 'boolean'
    or type(editor.window) ~= 'table'
  then
    return false, 'editor settings are invalid'
  end
  local session = options.session
  if
    type(session) ~= 'table'
    or type(session.open_on_start) ~= 'boolean'
    or (session.open_diff ~= nil and type(session.open_diff) ~= 'function')
  then
    return false, 'session settings are invalid'
  end
  if
    options.repository_root ~= nil
    and type(options.repository_root) ~= 'string'
    and type(options.repository_root) ~= 'function'
  then
    return false, 'repository_root must be a path, function, or nil'
  end
  if options.resolve_target ~= nil and type(options.resolve_target) ~= 'function' then
    return false, 'resolve_target must be a function or nil'
  end
  return true
end

function M.setup(opts)
  local options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  local valid, err = M.validate(options)
  if not valid then
    error('review-comments.nvim: ' .. err, 2)
  end
  M.options = options
  return M.options
end

return M
