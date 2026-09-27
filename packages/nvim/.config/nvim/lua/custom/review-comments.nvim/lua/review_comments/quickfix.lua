local marks = require('review_comments.marks')
local util = require('review_comments.util')

local OWNER = 'review-comments.nvim'

local M = {
  last_lists = {},
}

local function document_session_id(document)
  local session = type(document) == 'table' and document.session or nil
  return type(session) == 'table' and session.id or nil
end

local function review_context(list)
  return {
    review_comments = {
      owner = OWNER,
      root = list.root,
      kind = list.kind,
      token = list.token,
      session_id = list.session_id,
      include_resolved = list.include_resolved == true,
    },
  }
end

local function context_data(context)
  if type(context) ~= 'table' or type(context.review_comments) ~= 'table' then
    return nil
  end
  return context.review_comments
end

local function plugin_context(data)
  return type(data) == 'table'
    and data.owner == OWNER
    and type(data.root) == 'string'
    and (data.kind == 'quickfix' or data.kind == 'loclist')
    and type(data.token) == 'string'
    and data.token ~= ''
    and type(data.session_id) == 'string'
end

local function context_matches(data, list)
  return plugin_context(data)
    and data.root == list.root
    and data.kind == list.kind
    and data.token == list.token
    and data.session_id == list.session_id
    and data.include_resolved == (list.include_resolved == true)
end

local function new_list(root, kind, document, include_resolved, owner)
  return {
    root = root,
    kind = kind,
    owner = owner,
    token = util.new_id('list'),
    session_id = document_session_id(document),
    include_resolved = include_resolved == true,
    navigated = false,
  }
end

local function comment_status(comment)
  return comment.status == 'resolved' and 'resolved' or 'active'
end

local function comment_anchor(comment)
  return type(comment.anchor) == 'table' and comment.anchor or {}
end

local function anchor_source(anchor)
  return type(anchor.source) == 'table' and anchor.source or {}
end

local function comment_view(anchor, source)
  -- The semantic source model replaces the old anchor.view field. Retain the
  -- only so an in-memory v1 document remains displayable while it migrates.
  if source.kind == 'snapshot' then
    return source.side == 'left' and 'left' or source.side
  end
  if source.kind == 'worktree' then
    return 'right'
  end
  local view = anchor.view or source.view or source.side
  return type(view) == 'string' and view or nil
end

local function comment_file(comment)
  local file = comment.file
  return util.is_safe_relative(file) and file or nil
end

local function line_number(value, fallback)
  if type(value) == 'number' and value % 1 == 0 and value >= 1 then
    return value
  end
  return fallback
end

local function item_comment_id(item)
  local data = item and item.user_data
  if type(data) ~= 'table' or type(data.review_comment_id) ~= 'string' then
    return nil
  end
  return data.review_comment_id
end

local function display_location(file, start_line, end_line, start_column, end_column, mode)
  local line = start_line == end_line and tostring(start_line)
    or string.format('%d-%d', start_line, end_line)
  if mode == 'char' then
    line = string.format('%s:%d-%d', line, start_column + 1, end_column)
  end
  return string.format('%s:%s', file, line)
end

local function build_items(root, document, list)
  local result = {}
  local difftool = list.kind == 'loclist'
  local owner = list.owner
  local owner_bufnr = owner and vim.api.nvim_win_is_valid(owner) and vim.api.nvim_win_get_buf(owner)
    or nil
  local active_target = owner_bufnr and util.current_difftool_target(owner_bufnr) or nil

  for _, comment in ipairs(document.comments or {}) do
    local status = comment_status(comment)
    if list.include_resolved or status ~= 'resolved' then
      local anchor = comment_anchor(comment)
      local source = anchor_source(anchor)
      local file = comment_file(comment)
      local id = type(comment.id) == 'string' and comment.id or nil
      if file and id then
        local start_line = line_number(anchor.start_line, 1)
        local end_line = math.max(start_line, line_number(anchor.end_line, start_line))
        local start_column = anchor.mode == 'char' and math.max(0, anchor.start_column or 0) or 0
        local end_column = anchor.mode == 'char' and math.max(0, anchor.end_column or 0) or 0
        local view = comment_view(anchor, source)
        local orphaned = anchor.valid == false
        local candidate = not orphaned and anchor.stale == true
        local text = type(comment.comment) == 'string' and comment.comment or ''
        if orphaned then
          local reason = type(anchor.failure_reason) == 'string' and anchor.failure_reason or nil
          text = string.format('[orphaned%s] %s', reason and ': ' .. reason or '', text)
        elseif candidate then
          text = '[candidate location] ' .. text
        end
        if status == 'resolved' then
          text = '[resolved] ' .. text
        end

        local item = {
          lnum = start_line,
          end_lnum = end_line,
          col = start_column + 1,
          text = text,
          type = orphaned and 'E' or (candidate and 'W' or 'I'),
          user_data = {
            review_comment_id = id,
            review_root = root,
            review_file = file,
            review_view = view,
            review_status = status,
            review_source_kind = type(source.kind) == 'string' and source.kind or nil,
            review_start_line = start_line,
            review_end_line = end_line,
            review_start_column = start_column,
            review_end_column = end_column,
            review_difftool = difftool,
            review_anchor_valid = not orphaned,
            review_anchor_stale = anchor.stale == true,
          },
        }
        if anchor.mode == 'char' and end_column > 0 then
          item.end_col = end_column
        end

        if orphaned then
          -- Broken anchors retain a last-known location for display only. A
          -- native target here could silently jump to unrelated code or even
          -- recreate a path that was renamed outside Neovim.
          item.valid = 0
          item.text = string.format(
            '%s — %s',
            display_location(file, start_line, end_line, start_column, end_column, anchor.mode),
            item.text
          )
        elseif difftool then
          -- DiffTool owns the global quickfix list and coordinates both panes.
          -- A filename or bufnr here could reopen only one old side after the
          -- DiffTool quickfix item changes, so every projected row is targetless.
          item.valid = 0
          local active = active_target
            and active_target.file == file
            and active_target.view == (view or 'right')
          local location =
            display_location(file, start_line, end_line, start_column, end_column, anchor.mode)
          if not active then
            item.text =
              string.format('[not active in this DiffTool pane] %s — %s', location, item.text)
          else
            item.text = string.format('%s — %s', location, item.text)
          end
        elseif source.kind == 'snapshot' then
          -- A historical snapshot has no safe native target once DiffTool is
          -- no longer coordinating that side. Pointing at root/file would
          -- silently turn historical feedback into a working-tree jump.
          item.valid = 0
          local side = type(source.side) == 'string' and source.side or 'snapshot'
          item.text = string.format(
            '[historical %s side unavailable] %s — %s',
            side,
            display_location(file, start_line, end_line, start_column, end_column, anchor.mode),
            item.text
          )
        elseif source.kind ~= 'worktree' then
          item.valid = 0
          item.text = string.format(
            '[source unavailable] %s — %s',
            display_location(file, start_line, end_line, start_column, end_column, anchor.mode),
            item.text
          )
        else
          local live = marks.get(id, root)
          if live and vim.api.nvim_buf_is_valid(live.bufnr) then
            item.bufnr = live.bufnr
          else
            item.filename = util.join(root, file)
          end
        end

        table.insert(result, item)
      end
    end
  end
  return result
end

local function list_title(list)
  return list.include_resolved and 'Review Comments (all)' or 'Review Comments'
end

local function loclist_info(list, id)
  if not list.owner or not vim.api.nvim_win_is_valid(list.owner) then
    return nil
  end
  local result
  vim.api.nvim_win_call(list.owner, function()
    result = vim.fn.getloclist(0, {
      id = id or 0,
      nr = 0,
      idx = 0,
      title = 1,
      items = 1,
      context = 1,
      qfbufnr = 1,
    })
  end)
  return result
end

local function quickfix_info(id)
  return vim.fn.getqflist({
    id = id or 0,
    nr = 0,
    idx = 0,
    title = 1,
    items = 1,
    context = 1,
    qfbufnr = 1,
  })
end

local function list_info(list, id)
  if list.kind == 'loclist' then
    return loclist_info(list, id)
  end
  return quickfix_info(id)
end

local function owned_info(list)
  local info = list_info(list, list.id)
  local data = info and context_data(info.context)
  if not info or info.id ~= list.id or not context_matches(data, list) then
    return nil
  end
  return info
end

local function current_list_info(list)
  return list_info(list, 0)
end

local function list_is_current(list)
  local current = current_list_info(list)
  return current and current.id == list.id and context_matches(context_data(current.context), list)
end

local function visible_list_windows(info, list)
  if not info.qfbufnr or info.qfbufnr == 0 then
    return {}
  end

  local windows = {}
  for _, winid in ipairs(vim.fn.win_findbuf(info.qfbufnr)) do
    if
      vim.api.nvim_win_is_valid(winid)
      and vim.api.nvim_win_get_buf(winid) == info.qfbufnr
      and vim.bo[info.qfbufnr].buftype == 'quickfix'
    then
      if list.kind ~= 'loclist' and not list_is_current(list) then
        goto continue
      end
      local row = vim.api.nvim_win_get_cursor(winid)[1]
      table.insert(windows, {
        winid = winid,
        row = row,
        comment_id = item_comment_id(info.items and info.items[row]),
      })
    end
    ::continue::
  end
  return windows
end

local function find_item(items, comment_id)
  if not comment_id then
    return nil
  end
  for index, item in ipairs(items) do
    if item_comment_id(item) == comment_id then
      return index
    end
  end
  return nil
end

local function selected_comment_position(info, windows)
  local current_win = vim.api.nvim_get_current_win()
  for _, window in ipairs(windows) do
    if window.winid == current_win and window.comment_id then
      return window.comment_id, window.row
    end
  end
  for _, window in ipairs(windows) do
    if window.comment_id then
      return window.comment_id, window.row
    end
  end
  local row = tonumber(info.idx) or 1
  return item_comment_id(info.items and info.items[row]), row
end

local function replacement_index(info, new_items, selected_id, selected_row)
  if #new_items == 0 then
    return nil
  end
  return find_item(new_items, selected_id)
    or math.max(1, math.min(selected_row or tonumber(info.idx) or 1, #new_items))
end

local function set_list(list, qf_items, idx)
  local what = {
    id = list.id,
    title = list_title(list),
    items = qf_items,
    context = review_context(list),
  }
  if idx then
    what.idx = idx
  end

  if list.kind == 'loclist' then
    if not list.owner or not vim.api.nvim_win_is_valid(list.owner) then
      return false, 'The review location-list owner no longer exists'
    end
    local ok, result = pcall(vim.api.nvim_win_call, list.owner, function()
      return vim.fn.setloclist(0, {}, 'r', what)
    end)
    if not ok then
      return false, result
    end
    return result == 0, result == 0 and nil or 'Could not update the review location list'
  end

  local ok, result = pcall(vim.fn.setqflist, {}, 'r', what)
  if not ok then
    return false, result
  end
  return result == 0, result == 0 and nil or 'Could not update the review quickfix list'
end

local function restore_visible_cursors(windows, info, qf_items, default_index)
  if #qf_items == 0 then
    return
  end
  for _, window in ipairs(windows) do
    if
      vim.api.nvim_win_is_valid(window.winid)
      and vim.api.nvim_win_get_buf(window.winid) == info.qfbufnr
    then
      local row = find_item(qf_items, window.comment_id)
        or math.max(1, math.min(window.row or default_index or 1, #qf_items))
      pcall(vim.api.nvim_win_set_cursor, window.winid, { row, 0 })
    end
  end
end

local function same_list(left, right)
  return left
    and right
    and left.kind == right.kind
    and left.id == right.id
    and left.owner == right.owner
end

local function clear_record(list)
  local info = owned_info(list)
  if not info then
    return false, 'The recorded review list no longer exists or is no longer owned by the plugin'
  end
  return set_list(list, {}, nil)
end

local function close_record_window(list)
  if list.kind ~= 'loclist' or not list.owner or not vim.api.nvim_win_is_valid(list.owner) then
    return
  end
  if not list_is_current(list) then
    return
  end
  vim.api.nvim_win_call(list.owner, function()
    pcall(vim.cmd, 'lclose')
  end)
end

function M.current_is_difftool()
  local info = vim.fn.getqflist({ title = 1, items = 1 })
  if info.title ~= 'DiffTool' or #(info.items or {}) == 0 then
    return false
  end
  for _, item in ipairs(info.items or {}) do
    local data = item.user_data
    if
      type(data) ~= 'table'
      or data.diff ~= true
      or not util.is_safe_relative(data.rel)
      or type(data.left) ~= 'string'
      or data.left == ''
      or type(data.right) ~= 'string'
      or data.right == ''
    then
      return false
    end
  end
  return true
end

local function source_window()
  local current = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(current)
  if vim.bo[bufnr].buftype ~= 'quickfix' then
    return current
  end

  -- From a location-list window, Neovim can identify the exact file window
  -- that owns it. This matters in DiffTool: choosing an arbitrary non-qf
  -- window can silently migrate a left-side review list to the right pane.
  local associated = vim.fn.getloclist(0, { filewinid = 1, qfbufnr = 1 })
  if
    associated.qfbufnr == bufnr
    and associated.filewinid
    and associated.filewinid ~= 0
    and vim.api.nvim_win_is_valid(associated.filewinid)
  then
    return associated.filewinid
  end

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local candidate = vim.api.nvim_win_get_buf(winid)
    if vim.bo[candidate].buftype ~= 'quickfix' then
      return winid
    end
  end
  return nil
end

local function run_history_command(list, command, count)
  local call = function()
    vim.cmd({ cmd = command, count = count })
  end
  if list.kind == 'loclist' then
    return pcall(vim.api.nvim_win_call, list.owner, call)
  end
  return pcall(call)
end

local function activate_list(list)
  local target = owned_info(list)
  if not target then
    return false, 'The review list no longer exists or is no longer owned by the plugin'
  end
  local current = current_list_info(list)
  if current and current.id == list.id then
    return true
  end
  if
    not current
    or type(current.nr) ~= 'number'
    or type(target.nr) ~= 'number'
    or current.nr < 1
    or target.nr < 1
  then
    return false, 'Could not locate the review list in quickfix history'
  end

  local command = target.nr < current.nr and (list.kind == 'loclist' and 'lolder' or 'colder')
    or (list.kind == 'loclist' and 'lnewer' or 'cnewer')
  local ok, err = run_history_command(list, command, math.abs(target.nr - current.nr))
  if not ok then
    return false, tostring(err)
  end
  if not list_is_current(list) then
    return false, 'Could not activate the recorded review list'
  end
  return true
end

local function open_list_window(list, config, size)
  if not config.list.open or size == 0 then
    return true
  end
  local command = string.format(
    'botright %s %d',
    list.kind == 'loclist' and 'lopen' or 'copen',
    config.list.height
  )
  if list.kind == 'loclist' then
    local ok, err = pcall(vim.api.nvim_win_call, list.owner, function()
      vim.cmd(command)
    end)
    return ok, err
  end
  return pcall(vim.cmd, command)
end

local function restore_current_cursor(list, index)
  if not index then
    return
  end
  local info = current_list_info(list)
  if
    not info
    or info.id ~= list.id
    or not context_matches(context_data(info.context), list)
    or not info.qfbufnr
    or info.qfbufnr == 0
  then
    return
  end
  for _, winid in ipairs(vim.fn.win_findbuf(info.qfbufnr)) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == info.qfbufnr then
      pcall(vim.api.nvim_win_set_cursor, winid, { index, 0 })
    end
  end
end

local function reuse_projection(list, info, document, config, include_resolved)
  local windows = visible_list_windows(info, list)
  local selected_id, selected_row = selected_comment_position(info, windows)
  local updated = vim.deepcopy(list)
  updated.include_resolved = include_resolved == true
  updated.session_id = document_session_id(document)
  updated.navigated = false
  local qf_items = build_items(updated.root, document, updated)
  local idx = replacement_index(info, qf_items, selected_id, selected_row)
  local ok, err = set_list(updated, qf_items, idx)
  if not ok then
    return nil, tostring(err)
  end
  M.last_lists[updated.root] = updated

  local activated, activate_err = activate_list(updated)
  if not activated then
    return nil, activate_err
  end
  if #windows == 0 then
    if #windows == 0 then
      local opened, open_err = open_list_window(updated, config, #qf_items)
      if not opened then
        return nil, tostring(open_err)
      end
    end
  end
  restore_visible_cursors(windows, info, qf_items, idx)
  restore_current_cursor(updated, idx)
  return updated.kind
end

local function open_location_list(root, document, config, owner, include_resolved)
  local previous = M.last_lists[root]
  if previous and previous.kind == 'loclist' and previous.owner == owner then
    local info = owned_info(previous)
    if info then
      return reuse_projection(previous, info, document, config, include_resolved)
    end
    M.last_lists[root] = nil
    previous = nil
  end

  local list = new_list(root, 'loclist', document, include_resolved, owner)
  local qf_items = build_items(root, document, list)
  local list_id
  local history_error
  vim.api.nvim_win_call(owner, function()
    local current_number = vim.fn.getloclist(0, { nr = 0 }).nr
    local newest_number = vim.fn.getloclist(0, { nr = '$' }).nr
    if current_number and newest_number and current_number < newest_number then
      history_error =
        'Location list has newer history; use :lnewer before :ReviewList so newer lists are not discarded'
      return
    end
    vim.fn.setloclist(0, {}, ' ', {
      title = list_title(list),
      items = qf_items,
      context = review_context(list),
    })
    list_id = vim.fn.getloclist(0, { id = 0 }).id
  end)
  if history_error then
    return nil, history_error
  end

  list.id = list_id
  M.last_lists[root] = list
  local opened, open_err = open_list_window(list, config, #qf_items)
  if not opened then
    return nil, tostring(open_err)
  end
  if previous and not same_list(previous, list) then
    clear_record(previous)
    close_record_window(previous)
  end
  return 'loclist'
end

local function open_quickfix(root, document, config, include_resolved)
  local previous = M.last_lists[root]
  if previous and previous.kind == 'quickfix' then
    local info = owned_info(previous)
    if info then
      return reuse_projection(previous, info, document, config, include_resolved)
    end
    M.last_lists[root] = nil
    previous = nil
  end

  local current_number = vim.fn.getqflist({ nr = 0 }).nr
  local newest_number = vim.fn.getqflist({ nr = '$' }).nr
  if current_number and newest_number and current_number < newest_number then
    return nil,
      'Quickfix has newer history; use :cnewer before :ReviewList so newer lists are not discarded'
  end

  local list = new_list(root, 'quickfix', document, include_resolved)
  local qf_items = build_items(root, document, list)
  vim.fn.setqflist({}, ' ', {
    title = list_title(list),
    items = qf_items,
    context = review_context(list),
  })
  list.id = vim.fn.getqflist({ id = 0 }).id
  M.last_lists[root] = list
  local opened, open_err = open_list_window(list, config, #qf_items)
  if not opened then
    return nil, tostring(open_err)
  end
  if previous and not same_list(previous, list) then
    clear_record(previous)
    close_record_window(previous)
  end
  return 'quickfix'
end

--- Materialize and optionally open a review projection.
--- @param root string
--- @param document table
--- @param config table
--- @param opts? { include_resolved?: boolean }|boolean
--- @return string? kind
--- @return string? error
function M.open(root, document, config, opts)
  local include_resolved = opts == true or (type(opts) == 'table' and opts.include_resolved == true)
  local difftool = M.current_is_difftool()
  if difftool then
    if config.list.difftool_fallback ~= 'loclist' then
      return nil, 'DiffTool currently owns quickfix; configure list.difftool_fallback = "loclist"'
    end
    local owner = source_window()
    if not owner then
      return nil, 'No source window is available for a review location list'
    end
    return open_location_list(root, document, config, owner, include_resolved)
  end
  return open_quickfix(root, document, config, include_resolved)
end

--- Refresh an existing projection without creating, opening, or selecting it.
--- @param root string
--- @param document table
--- @param config table Unused currently; retained as part of the projection API.
--- @return boolean refreshed
--- @return string? error
function M.refresh(root, document, config)
  local _ = config
  local list = M.last_lists[root]
  if not list then
    return false
  end

  local info = owned_info(list)
  if not info then
    M.last_lists[root] = nil
    return false, 'The recorded review list no longer exists or is no longer owned by the plugin'
  end
  if document_session_id(document) ~= list.session_id then
    return false, 'The review list belongs to a different review session'
  end

  local windows = visible_list_windows(info, list)
  local selected_id, selected_row = selected_comment_position(info, windows)
  local qf_items = build_items(root, document, list)
  local idx = replacement_index(info, qf_items, selected_id, selected_row)
  local ok, err = set_list(list, qf_items, idx)
  if not ok then
    return false, tostring(err)
  end
  restore_visible_cursors(windows, info, qf_items, idx)
  return true
end

--- Return whether a valid, plugin-owned projection is tracked for a root.
--- @param root string
--- @return boolean
function M.has_projection(root)
  local list = M.last_lists[root]
  if not list then
    return false
  end
  if not owned_info(list) then
    M.last_lists[root] = nil
    return false
  end
  return true
end

local function item_matches_target(item, target, root)
  local data = item and item.user_data
  return type(data) == 'table'
    and data.review_difftool == true
    and data.review_anchor_valid == true
    and data.review_root == root
    and data.review_file == target.file
    and (data.review_view or 'right') == target.view
end

local function current_review_cursor_row(info)
  local bufnr = vim.api.nvim_get_current_buf()
  if
    not info
    or not info.qfbufnr
    or info.qfbufnr == 0
    or bufnr ~= info.qfbufnr
    or vim.bo[bufnr].buftype ~= 'quickfix'
  then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  if row < 1 or row > #(info.items or {}) then
    return nil
  end
  return row
end

local function set_current_index(list, index)
  if list.kind == 'loclist' then
    local ok, result = pcall(vim.api.nvim_win_call, list.owner, function()
      return vim.fn.setloclist(0, {}, 'a', { id = list.id, idx = index })
    end)
    if not ok then
      return false, result
    end
    return result == 0, result == 0 and nil or 'Could not update the location-list index'
  end
  local ok, result = pcall(vim.fn.setqflist, {}, 'a', { id = list.id, idx = index })
  if not ok then
    return false, result
  end
  return result == 0, result == 0 and nil or 'Could not update the quickfix index'
end

local function jump_location_index(root, list, loc, index)
  if not list.owner or not vim.api.nvim_win_is_valid(list.owner) then
    return false, 'The review-list owner no longer exists'
  end
  local owner_bufnr = vim.api.nvim_win_get_buf(list.owner)
  local target = util.current_difftool_target(owner_bufnr)
  if not target then
    return false, 'The review-list owner is no longer an active DiffTool pane'
  end
  local item = loc.items and loc.items[index] or nil
  if not item_matches_target(item, target, root) then
    return false, 'The selected review is not available in the active DiffTool pane'
  end

  local indexed, index_err = set_current_index(list, index)
  if not indexed then
    return false, 'Could not select the review-list row: ' .. tostring(index_err)
  end
  local data = item.user_data
  local line_count = vim.api.nvim_buf_line_count(owner_bufnr)
  local line = math.max(1, math.min(line_number(data.review_start_line, 1), line_count))
  list.navigated = true
  vim.api.nvim_set_current_win(list.owner)
  local column = math.max(0, tonumber(data.review_start_column) or 0)
  local line_text = vim.api.nvim_buf_get_lines(owner_bufnr, line - 1, line, false)[1] or ''
  vim.api.nvim_win_set_cursor(list.owner, { line, math.min(column, #line_text) })
  return true
end

local function navigate_location_review(root, list, direction)
  local loc = current_list_info(list)
  local context = loc and context_data(loc.context)
  if not loc or loc.id ~= list.id or not context_matches(context, list) then
    return false, 'The review location list is not current; run :ReviewList again'
  end

  local owner_bufnr = vim.api.nvim_win_get_buf(list.owner)
  local target = util.current_difftool_target(owner_bufnr)
  if not target then
    return false, 'The review-list owner is no longer an active DiffTool pane'
  end

  local cursor_row = current_review_cursor_row(loc)
  local current = cursor_row or loc.idx or 0
  local current_matches = item_matches_target(loc.items[current], target, root)
  local index
  if cursor_row then
    index = current + direction
  elseif list.navigated ~= true and current_matches then
    -- A new location list starts at idx=1 before a source jump has happened.
    index = current
  elseif not current_matches then
    current = direction > 0 and 0 or #loc.items + 1
    index = current + direction
  else
    index = current + direction
  end
  while index >= 1 and index <= #loc.items do
    local item = loc.items[index]
    if item_matches_target(item, target, root) then
      return jump_location_index(root, list, loc, index)
    end
    index = index + direction
  end
  return false, 'No more review comments for the active DiffTool pane'
end

local function tracked_list_for_context(data)
  if not plugin_context(data) then
    return nil
  end
  local list = M.last_lists[data.root]
  return list and context_matches(data, list) and list or nil
end

function M.is_review_buffer(bufnr)
  local qf = quickfix_info(0)
  local qf_context = context_data(qf.context)
  local qf_list = tracked_list_for_context(qf_context)
  if qf.qfbufnr == bufnr and qf_list and qf.id == qf_list.id then
    return { kind = 'quickfix', root = qf_list.root, id = qf_list.id }
  end

  for root, list in pairs(M.last_lists) do
    if list.kind == 'loclist' then
      local loc
      local associated = vim.fn.getloclist(0, { filewinid = 1, qfbufnr = 1 })
      if
        bufnr == vim.api.nvim_get_current_buf()
        and vim.bo[bufnr].buftype == 'quickfix'
        and associated.qfbufnr == bufnr
        and associated.filewinid
        and associated.filewinid ~= 0
        and associated.filewinid == list.owner
      then
        loc = vim.fn.getloclist(0, {
          id = 0,
          nr = 0,
          idx = 0,
          title = 1,
          items = 1,
          context = 1,
          qfbufnr = 1,
        })
      else
        loc = current_list_info(list)
      end
      local loc_context = loc and context_data(loc.context)
      if
        loc
        and loc.qfbufnr == bufnr
        and loc.id == list.id
        and context_matches(loc_context, list)
      then
        return { kind = 'loclist', root = root, owner = list.owner, id = list.id }
      end
    end
  end
  return nil
end

--- Resolve the review comment represented by the cursor row of an owned list.
--- @param bufnr? integer
--- @return table? selection { root, id, kind, owner? }
--- @return string? error
function M.selected_comment(bufnr)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local review = M.is_review_buffer(bufnr)
  if not review then
    return nil, 'The current buffer is not a tracked review list'
  end

  local winid
  if vim.api.nvim_get_current_buf() == bufnr then
    winid = vim.api.nvim_get_current_win()
  else
    winid = vim.fn.bufwinid(bufnr)
  end
  if not winid or winid == -1 or not vim.api.nvim_win_is_valid(winid) then
    return nil, 'The review list is not visible'
  end

  local list = M.last_lists[review.root]
  local info = list and current_list_info(list) or nil
  if not info or info.id ~= review.id or not context_matches(context_data(info.context), list) then
    return nil, 'The review list is no longer current'
  end
  local row = vim.api.nvim_win_get_cursor(winid)[1]
  local id = item_comment_id(info.items and info.items[row])
  if not id then
    return nil, 'The current review-list row has no review comment'
  end
  return {
    root = review.root,
    id = id,
    kind = review.kind,
    owner = review.owner,
    row = row,
  }
end

--- Jump to the review under the cursor of the current owned list.
--- Snapshot rows outside DiffTool and rows for another DiffTool side remain
--- deliberately non-jumpable so navigation cannot substitute the worktree or
--- tear apart a paired diff.
--- @param root? string
--- @return boolean
--- @return string? error
function M.jump_selected(root)
  local selection, selection_err = M.selected_comment(0)
  if not selection then
    return false, selection_err
  end
  if root and root ~= selection.root then
    return false, 'The selected review belongs to a different repository'
  end

  local list = M.last_lists[selection.root]
  local info = list and current_list_info(list) or nil
  if
    not list
    or not info
    or info.id ~= list.id
    or not context_matches(context_data(info.context), list)
  then
    return false, 'The review list is no longer current'
  end

  if list.kind == 'loclist' then
    return jump_location_index(selection.root, list, info, selection.row)
  end

  local item = info.items and info.items[selection.row] or nil
  local data = item and item.user_data or nil
  if
    type(data) ~= 'table'
    or data.review_root ~= selection.root
    or data.review_comment_id ~= selection.id
  then
    return false, 'The selected row is not an owned review comment'
  end
  if data.review_source_kind == 'snapshot' then
    return false, 'Historical review snapshots are only jumpable in their active DiffTool pane'
  end
  if data.review_source_kind ~= 'worktree' or item.valid ~= 1 then
    return false, 'The selected review target is unavailable'
  end

  local indexed, index_err = set_current_index(list, selection.row)
  if not indexed then
    return false, 'Could not select the review-list row: ' .. tostring(index_err)
  end
  local ok, jump_err = pcall(vim.cmd, { cmd = 'cc', count = selection.row })
  if not ok then
    return false, tostring(jump_err)
  end
  return true
end

function M.current_review_root()
  local review = M.is_review_buffer(vim.api.nvim_get_current_buf())
  return review and review.root or nil
end

function M.close_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local review = M.is_review_buffer(bufnr)
  if not review then
    return false
  end

  if review.kind == 'loclist' then
    if review.owner and vim.api.nvim_win_is_valid(review.owner) then
      vim.api.nvim_win_call(review.owner, function()
        local info = vim.fn.getloclist(0, { nr = 0 })
        if info.nr and info.nr > 1 then
          pcall(vim.cmd, 'lolder')
        end
        vim.cmd('lclose')
      end)
    end
    return true
  end

  local info = vim.fn.getqflist({ nr = 0 })
  if info.nr and info.nr > 1 then
    pcall(vim.cmd, 'colder')
  end
  pcall(vim.cmd, 'cclose')
  return true
end

function M.next(root)
  local list = M.last_lists[root]
  if not list then
    return false, 'Run :ReviewList before navigating review comments'
  end
  if list.kind == 'loclist' and list.owner and vim.api.nvim_win_is_valid(list.owner) then
    return navigate_location_review(root, list, 1)
  end
  local qf = quickfix_info(0)
  if
    list.kind ~= 'quickfix'
    or qf.id ~= list.id
    or not context_matches(context_data(qf.context), list)
  then
    return false, 'The review quickfix list is not current; run :ReviewList again'
  end
  local cursor_row = current_review_cursor_row(qf)
  if cursor_row then
    local indexed, index_err = set_current_index(list, cursor_row)
    if not indexed then
      return false, 'Could not select the review-list row: ' .. tostring(index_err)
    end
  end
  return pcall(vim.cmd, 'cnext')
end

function M.previous(root)
  local list = M.last_lists[root]
  if not list then
    return false, 'Run :ReviewList before navigating review comments'
  end
  if list.kind == 'loclist' and list.owner and vim.api.nvim_win_is_valid(list.owner) then
    return navigate_location_review(root, list, -1)
  end
  local qf = quickfix_info(0)
  if
    list.kind ~= 'quickfix'
    or qf.id ~= list.id
    or not context_matches(context_data(qf.context), list)
  then
    return false, 'The review quickfix list is not current; run :ReviewList again'
  end
  local cursor_row = current_review_cursor_row(qf)
  if cursor_row then
    local indexed, index_err = set_current_index(list, cursor_row)
    if not indexed then
      return false, 'Could not select the review-list row: ' .. tostring(index_err)
    end
  end
  return pcall(vim.cmd, 'cprevious')
end

--- Clear a tracked projection by ID, even when a foreign list is current.
--- The projection handle is then discarded; a later :ReviewList materializes
--- the new session explicitly.
--- @param root string
--- @return boolean cleared
function M.clear(root)
  local list = M.last_lists[root]
  if not list then
    return false
  end
  local cleared, err = clear_record(list)
  if cleared or not owned_info(list) then
    M.last_lists[root] = nil
  end
  return cleared, err
end

function M.reset()
  M.last_lists = {}
end

return M
