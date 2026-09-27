local M = {}

local editors = {}
local group = vim.api.nvim_create_augroup('ReviewCommentsEditor', { clear = false })

local function notify(state, message, level)
  if state.opts.notify == false then
    return
  end
  if type(state.opts.notify) == 'function' then
    local ok = pcall(state.opts.notify, message, level or vim.log.levels.INFO)
    if ok then
      return
    end
  end
  vim.notify(message, level or vim.log.levels.INFO, { title = 'review-comments.nvim' })
end

local function normalize_lines(value)
  if value == nil then
    return { '' }
  end
  if type(value) == 'string' then
    value = value:gsub('\r\n', '\n')
    return vim.split(value, '\n', { plain = true })
  end
  if type(value) ~= 'table' then
    return nil, 'initial_text must be a string or list of lines'
  end
  local lines = {}
  for index, line in ipairs(value) do
    if type(line) ~= 'string' or line:find('\n', 1, true) then
      return nil, string.format('initial_text line %d is invalid', index)
    end
    lines[index] = line
  end
  return #lines > 0 and lines or { '' }
end

local function buffer_text(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
end

local function set_pending(state, value)
  if vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.b[state.bufnr].review_comments_editor_pending = value and 1 or 0
  end
end

local function editor_window_config(state)
  local columns = math.max(vim.o.columns, 1)
  local lines = math.max(vim.o.lines - vim.o.cmdheight, 1)
  local widest = 0
  for _, line in ipairs(state.initial_lines) do
    widest = math.max(widest, vim.api.nvim_strwidth(line))
  end

  local width = math.min(math.max(48, widest + 4), math.max(columns - 4, 1))
  local height = math.min(math.max(5, #state.initial_lines + 2), math.max(lines - 4, 1))
  local defaults = {
    relative = 'editor',
    row = math.max(math.floor((lines - height) / 2) - 1, 0),
    col = math.max(math.floor((columns - width) / 2), 0),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. state.opts.title .. ' ',
    title_pos = 'center',
  }
  return vim.tbl_deep_extend('force', defaults, state.opts.window or {})
end

local function open_window(state)
  for _, winid in ipairs(vim.fn.win_findbuf(state.bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_set_current_win(winid)
      return winid
    end
  end

  local ok, winid = pcall(
    vim.api.nvim_open_win,
    state.bufnr,
    state.opts.enter ~= false,
    editor_window_config(state)
  )
  if not ok then
    return nil, tostring(winid)
  end
  state.winid = winid
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = 'no'
  vim.wo[winid].foldcolumn = '0'
  vim.wo[winid].spell = state.opts.spell == true

  local last_line = state.initial_lines[#state.initial_lines] or ''
  pcall(vim.api.nvim_win_set_cursor, winid, { #state.initial_lines, #last_line })
  if state.opts.start_insert ~= false then
    vim.schedule(function()
      if
        editors[state.bufnr] == state
        and vim.api.nvim_win_is_valid(winid)
        and vim.api.nvim_get_current_win() == winid
      then
        vim.cmd('startinsert')
      end
    end)
  end
  return winid
end

local function cancel_callback(state, reason)
  if state.cancel_notified or state.finished then
    return
  end
  state.cancel_notified = true
  if type(state.opts.on_cancel) == 'function' then
    local ok, err = pcall(state.opts.on_cancel, {
      bufnr = state.bufnr,
      reason = reason,
      text = buffer_text(state.bufnr) or state.last_draft,
      pending = state.pending ~= nil,
    })
    if not ok then
      notify(state, 'Review editor cancel callback failed: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

local function forget(state, reason)
  if editors[state.bufnr] ~= state then
    return
  end
  state.last_draft = buffer_text(state.bufnr) or state.last_draft
  editors[state.bufnr] = nil
  set_pending(state, false)
  cancel_callback(state, state.cancel_reason or reason or 'buffer_deleted')
end

local function validate(state, text)
  if type(state.opts.validate) == 'function' then
    local ok, valid, err = pcall(state.opts.validate, text)
    if not ok then
      return false, tostring(valid)
    end
    if not valid then
      return false, err or 'The review comment is invalid'
    end
    return true
  end
  if not text:find('%S') then
    return false, 'A review comment cannot be empty'
  end
  return true
end

local function close_if_unchanged(state, committed_text)
  if state.opts.close_on_submit == false then
    return
  end
  vim.schedule(function()
    if
      editors[state.bufnr] ~= state
      or not vim.api.nvim_buf_is_valid(state.bufnr)
      or state.pending ~= nil
      or buffer_text(state.bufnr) ~= committed_text
    then
      return
    end
    state.finished = true
    vim.bo[state.bufnr].modified = false
    local deleted, delete_err = pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true })
    if not deleted and editors[state.bufnr] == state then
      state.finished = false
      vim.bo[state.bufnr].modified = true
      notify(
        state,
        'The review comment was saved, but its editor could not close: ' .. tostring(delete_err),
        vim.log.levels.WARN
      )
    end
  end)
end

local function complete(state, attempt, ok, err)
  if editors[state.bufnr] ~= state or state.pending ~= attempt then
    return false
  end
  state.pending = nil
  set_pending(state, false)

  if not ok then
    state.last_error = err and tostring(err) or 'The review comment could not be saved'
    if vim.api.nvim_buf_is_valid(state.bufnr) then
      vim.bo[state.bufnr].modified = true
    end
    notify(state, state.last_error, vim.log.levels.ERROR)
    return false
  end

  state.last_error = nil
  state.last_committed_text = attempt.text
  state.submitted = true
  if buffer_text(state.bufnr) == attempt.text then
    vim.bo[state.bufnr].modified = false
    close_if_unchanged(state, attempt.text)
  else
    vim.bo[state.bufnr].modified = true
    notify(
      state,
      'The earlier review draft was saved; newer edits remain in the editor',
      vim.log.levels.INFO
    )
  end
  return true
end

local function request_write(state)
  if editors[state.bufnr] ~= state or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return false, 'The review editor is no longer open'
  end
  if state.pending then
    local err = 'A review comment save is already in progress'
    notify(state, err, vim.log.levels.WARN)
    return false, err
  end

  local text = buffer_text(state.bufnr)
  local valid, validation_err = validate(state, text)
  if not valid then
    state.last_error = validation_err
    vim.bo[state.bufnr].modified = true
    notify(state, validation_err, vim.log.levels.WARN)
    return false, validation_err
  end

  state.attempt = state.attempt + 1
  local attempt = {
    id = state.attempt,
    text = text,
    changedtick = vim.api.nvim_buf_get_changedtick(state.bufnr),
  }
  state.pending = attempt
  state.last_draft = text
  set_pending(state, true)

  local finished = false
  local function finish(ok, err)
    if finished then
      return false
    end
    finished = true
    local callback = function()
      complete(state, attempt, ok == true, err)
    end
    if vim.in_fast_event() then
      vim.schedule(callback)
    else
      callback()
    end
    return true
  end
  local context = {
    bufnr = state.bufnr,
    attempt = attempt.id,
    changedtick = attempt.changedtick,
    is_current = function()
      return editors[state.bufnr] == state and state.pending == attempt
    end,
  }

  local called, result, result_err = pcall(state.opts.on_submit, text, finish, context)
  if not called then
    finish(false, result)
  elseif not finished then
    if result == false then
      finish(false, result_err)
    elseif result ~= nil then
      finish(true)
    elseif result_err ~= nil then
      finish(false, result_err)
    end
  end
  return true
end

local function handle_for(state)
  local handle = { bufnr = state.bufnr }

  function handle:submit()
    return M.submit(self.bufnr)
  end

  function handle:cancel(opts)
    return M.cancel(self.bufnr, opts)
  end

  function handle:show()
    return M.show(self.bufnr)
  end

  function handle:status()
    return M.status(self.bufnr)
  end

  return handle
end

--- Open a multiline review comment editor.
---
--- `on_submit` may return a truthy value for synchronous success, `false, error`
--- for synchronous failure, or return nil and later invoke `finish(ok, error)`.
--- Asynchronous callbacks should check `context.is_current()` immediately before
--- making a durable change. A stale `finish` call never closes or modifies a newer draft.
--- @param opts {on_submit: function, initial_text?: string|string[], title?: string, filetype?: string, close_on_submit?: boolean, start_insert?: boolean, enter?: boolean, spell?: boolean, window?: table, validate?: function, notify?: function|boolean, on_cancel?: function}
--- @return table? handle
--- @return string? error
function M.open(opts)
  opts = opts or {}
  if type(opts.on_submit) ~= 'function' then
    return nil, 'on_submit must be a function'
  end
  local initial_lines, lines_err = normalize_lines(opts.initial_text)
  if not initial_lines then
    return nil, lines_err
  end
  opts.title = type(opts.title) == 'string' and opts.title ~= '' and opts.title or 'Review comment'

  local bufnr = vim.api.nvim_create_buf(false, true)
  local state = {
    bufnr = bufnr,
    opts = opts,
    initial_lines = initial_lines,
    last_draft = table.concat(initial_lines, '\n'),
    attempt = 0,
    submitted = false,
    finished = false,
  }
  editors[bufnr] = state

  vim.api.nvim_buf_set_name(bufnr, string.format('review-comments://editor/%d', bufnr))
  vim.bo[bufnr].buftype = 'acwrite'
  -- The editor is meaningful only while one of its windows is open. Wiping it
  -- when the last window closes makes ordinary :q/:q! a complete cancellation
  -- instead of leaving an unloaded buffer registered as an active draft.
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].undofile = false
  vim.bo[bufnr].filetype = opts.filetype or 'markdown'
  vim.bo[bufnr].modifiable = true
  vim.b[bufnr].review_comments_editor = 1
  set_pending(state, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)
  vim.bo[bufnr].modified = false

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    buffer = bufnr,
    callback = function()
      request_write(state)
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    buffer = bufnr,
    callback = function(args)
      forget(state, args.event == 'BufWipeout' and 'buffer_wiped' or 'buffer_deleted')
    end,
  })
  vim.api.nvim_buf_create_user_command(bufnr, 'ReviewCancel', function(command)
    M.cancel(bufnr, { force = command.bang })
  end, {
    bang = true,
    desc = 'Discard this review comment draft; use ! while a save is pending',
  })
  vim.keymap.set('n', '<C-s>', '<Cmd>write<CR>', { buffer = bufnr, silent = true })
  vim.keymap.set('i', '<C-s>', '<Esc><Cmd>write<CR>', { buffer = bufnr, silent = true })

  local winid, window_err = open_window(state)
  if not winid then
    state.finished = true
    editors[bufnr] = nil
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return nil, 'Could not open review editor: ' .. window_err
  end
  return handle_for(state)
end

function M.submit(bufnr)
  local state = editors[bufnr]
  if not state then
    return false, 'The review editor is no longer open'
  end
  return request_write(state)
end

function M.cancel(bufnr, opts)
  opts = opts or {}
  local state = editors[bufnr]
  if not state then
    return false, 'The review editor is no longer open'
  end
  if state.pending and not opts.force then
    local err = 'A save is in progress; use :ReviewCancel! to discard the editor anyway'
    notify(state, err, vim.log.levels.WARN)
    return false, err
  end
  state.cancel_reason = state.pending and 'forced_while_pending' or 'cancelled'
  local ok, delete_err = pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  if not ok then
    return false, tostring(delete_err)
  end
  forget(state, state.cancel_reason)
  return true
end

function M.show(bufnr)
  local state = editors[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, 'The review editor is no longer open'
  end
  return open_window(state)
end

function M.status(bufnr)
  local state = editors[bufnr]
  if not state then
    return nil
  end
  return {
    bufnr = bufnr,
    valid = vim.api.nvim_buf_is_valid(bufnr),
    pending = state.pending ~= nil,
    attempt = state.attempt,
    submitted = state.submitted,
    last_error = state.last_error,
    last_committed_text = state.last_committed_text,
  }
end

function M.active()
  local result = {}
  for bufnr in pairs(editors) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      result[#result + 1] = bufnr
    end
  end
  table.sort(result)
  return result
end

function M.reset()
  local active = editors
  editors = {}
  for bufnr, state in pairs(active) do
    state.finished = true
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.bo[bufnr].modified = false
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

return M
