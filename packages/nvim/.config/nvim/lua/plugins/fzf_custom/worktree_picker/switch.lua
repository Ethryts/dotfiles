-- Buffer remapping from the previous picker, now separated from the UI.
local M = {}
local C = require("plugins.fzf_custom.worktree_picker.common")
local api, fn, uv = vim.api, vim.fn, vim.uv
local notify, fail, normalize = C.notify, C.fail, C.normalize
local display, relative = C.display, C.relative
local context, owned_relative = C.context, C.owned_relative

local function assert_clean(buf)
  if api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
    fail("Save or discard edits before switching:\n" .. display(api.nvim_buf_get_name(buf)))
  end
end

local function file_exists(path)
  local stat, err, code = uv.fs_stat(path)
  if not stat and code ~= "ENOENT" and code ~= "ENOTDIR" then
    fail("Cannot inspect " .. display(path) .. ": " .. tostring(err))
  end
  if not stat or stat.type ~= "file" then return false end
  if fn.filereadable(path) ~= 1 then fail("Cannot read " .. display(path)) end
  return true
end

local function restore_view(win, buf, view)
  api.nvim_win_call(win, function()
    local v = vim.deepcopy(view)
    local lines = api.nvim_buf_line_count(buf)
    v.lnum = math.max(1, math.min(v.lnum, lines))
    v.topline = math.max(1, math.min(v.topline, lines))
    local line = api.nvim_buf_get_lines(buf, v.lnum - 1, v.lnum, false)[1] or ""
    v.col = math.min(v.col, #line)
    v.coladd = 0
    fn.winrestview(v)
  end)
end

-- Preserve existing local-directory scopes; rebase only directories belonging
-- to the source worktree. Missing subdirectories fall back to the target root.
local function directories()
  local snapshot = { global = fn.getcwd(-1, -1), tabs = {}, wins = {} }
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    local win = api.nvim_tabpage_get_win(tab)
    api.nvim_win_call(win, function()
      if fn.haslocaldir(-1, 0) == 1 then
        snapshot.tabs[#snapshot.tabs + 1] = { win = win, path = fn.getcwd(-1, 0) }
      end
    end)
  end
  for _, win in ipairs(api.nvim_list_wins()) do
    api.nvim_win_call(win, function()
      if fn.haslocaldir() == 1 then
        snapshot.wins[#snapshot.wins + 1] = { win = win, path = fn.getcwd() }
      end
    end)
  end
  return snapshot
end

local function set_directories(snapshot, target, source, trees)
  local function rebase(path)
    if not source then return path end -- rollback
    local rel = owned_relative(path, source, trees)
    if rel == nil then return path end
    local mapped = rel == "" and target or target .. "/" .. rel
    return fn.isdirectory(mapped) == 1 and mapped or target
  end
  api.nvim_set_current_dir(target)
  for _, group in ipairs({ { "tcd", snapshot.tabs }, { "lcd", snapshot.wins } }) do
    for _, item in ipairs(group[2]) do
      if api.nvim_win_is_valid(item.win) then
        api.nvim_win_call(item.win, function()
          api.nvim_cmd({ cmd = group[1], args = { rebase(item.path) } }, {})
        end)
      end
    end
  end
end

local function switch_impl(target)
  local source, trees = context()
  target = normalize(fn.fnamemodify(target, ":p"))
  target = normalize(uv.fs_realpath(target) or target)
  local selected
  for _, tree in ipairs(trees) do
    if tree.path == target and not tree.bare then selected = tree end
  end
  if not selected or fn.isdirectory(target) ~= 1 then
    fail("The target is not an available worktree of the active repository.")
  end
  if source == target then
    notify("Already in " .. display(target)); return
  end

  local windows, shown = {}, {}
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    shown[buf] = true
    windows[#windows + 1] = { win = win, old = buf }
  end
  local before, plan, by_old = {}, {}, {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    before[buf] = true
    local missing = vim.b[buf].worktree_missing
    local name, rel = api.nvim_buf_get_name(buf), nil
    if missing and missing.root == source then
      rel = missing.relative
    elseif vim.bo[buf].buftype == "" and name ~= "" then
      rel = owned_relative(name, source, trees)
    end
    if rel and rel ~= "" and rel ~= ".git" and not rel:match("^%.git/")
        and (vim.bo[buf].buflisted or shown[buf]) then
      assert_clean(buf)
      local entry = {
        old = buf,
        relative = rel,
        path = target .. "/" .. rel,
        listed = vim.bo[buf].buflisted,
        views = {},
      }
      entry.exists = file_exists(entry.path)
      plan[#plan + 1], by_old[buf] = entry, entry
    end
  end
  -- A deleted-on-disk destination may still have a stale editor buffer. Do not
  -- leave that editable beside a "missing" placeholder, or discard its edits.
  for _, entry in ipairs(plan) do
    if not entry.exists then
      for buf in pairs(before) do
        if vim.bo[buf].buftype == "" and normalize(api.nvim_buf_get_name(buf)) == entry.path then
          assert_clean(buf)
          fail("Close the existing buffer for this missing destination first:\n" .. display(entry.path))
        end
      end
    end
  end
  for _, window in ipairs(windows) do
    local entry = by_old[window.old]
    if entry then
      local missing = vim.b[window.old].worktree_missing
      window.view = api.nvim_win_call(window.win, fn.winsaveview)
      entry.views[tostring(window.win)] = missing and missing.views[tostring(window.win)]
          or window.view
    end
  end

  local dirs, original_autochdir = directories(), vim.o.autochdir
  local protected, created, changed, missing_paths = {}, {}, {}, {}
  local function protect(buf)
    if not protected[buf] then
      protected[buf] = { hidden = vim.bo[buf].bufhidden, listed = vim.bo[buf].buflisted }
      vim.bo[buf].bufhidden = "hide" -- retain source buffers until commit/rollback
    end
  end

  vim.o.autochdir = false
  local ok, err = pcall(function()
    for _, entry in ipairs(plan) do protect(entry.old) end
    -- Allocate/preflight every destination before replacing any source window.
    for _, entry in ipairs(plan) do
      local buf = entry.exists and fn.bufadd(entry.path) or api.nvim_create_buf(false, true)
      if not buf or buf == 0 then fail("Cannot allocate a destination buffer.") end
      if by_old[buf] then fail("Source and target share a file buffer; close that file first.") end
      entry.new = buf
      if not before[buf] then created[buf] = true end
      if not entry.exists then vim.bo[buf].bufhidden = "hide" end
      assert_clean(buf)
      protect(buf)
    end
    set_directories(dirs, target, source, trees)
    for _, entry in ipairs(plan) do
      local buf = entry.new
      if entry.exists then
        fn.bufload(buf)
        if not api.nvim_buf_is_loaded(buf) or not file_exists(entry.path) then
          fail("File disappeared or could not be loaded: " .. display(entry.path))
        end
        -- Refresh a previously loaded destination that an agent changed on disk.
        local autoread = vim.bo[buf].autoread
        vim.bo[buf].autoread = true
        local read_ok, read_err = pcall(vim.cmd, "checktime " .. buf)
        vim.bo[buf].autoread = autoread
        if not read_ok then fail(tostring(read_err)) end
      else
        api.nvim_buf_set_name(buf, "worktree-missing://" .. buf .. "/" .. display(entry.relative))
        vim.b[buf].worktree_missing = {
          root = target, relative = entry.relative, views = entry.views,
        }
        api.nvim_buf_set_lines(buf, 0, -1, false, {
          "File unavailable in this worktree", "",
          "File:     " .. display(entry.relative),
          "Worktree: " .. display(target), "",
          "This is a placeholder, not a file on disk.",
          "Switch worktrees again to reopen the corresponding file.",
          "Use :bdelete to stop carrying this file between worktrees.",
        })
        vim.bo[buf].modifiable = false
        vim.bo[buf].readonly = true
        vim.bo[buf].modified = false
        vim.bo[buf].filetype = "worktree_missing"
        missing_paths[#missing_paths + 1] = entry.relative
      end
      vim.bo[buf].buflisted = entry.listed or vim.bo[buf].buflisted
    end
    -- Autocommands may have run while loading; check again before replacing.
    for _, entry in ipairs(plan) do
      assert_clean(entry.old); assert_clean(entry.new)
    end
    for _, window in ipairs(windows) do
      local entry = by_old[window.old]
      if entry and api.nvim_win_is_valid(window.win) then
        changed[#changed + 1] = window
        api.nvim_win_set_buf(window.win, entry.new)
        if entry.exists then
          restore_view(window.win, entry.new, entry.views[tostring(window.win)])
        end
      end
    end
  end)

  if not ok then
    -- Best-effort editor rollback. Never force-delete modified buffers.
    for _, window in ipairs(changed) do
      if api.nvim_win_is_valid(window.win) and api.nvim_buf_is_valid(window.old) then
        pcall(api.nvim_win_set_buf, window.win, window.old)
        pcall(restore_view, window.win, window.old, window.view)
      end
    end
    pcall(set_directories, dirs, dirs.global)
  end
  for buf, options in pairs(protected) do
    if api.nvim_buf_is_valid(buf) then
      vim.bo[buf].bufhidden = options.hidden
      if not ok then vim.bo[buf].buflisted = options.listed or vim.bo[buf].modified end
    end
  end
  vim.o.autochdir = original_autochdir
  if not ok then
    for buf in pairs(created) do
      if api.nvim_buf_is_valid(buf) then
        if vim.bo[buf].modified then
          vim.bo[buf].buflisted = true
        elseif #fn.win_findbuf(buf) == 0 then
          pcall(api.nvim_buf_delete, buf, { force = false })
        end
      end
    end
    fail("Switch failed; editor rollback attempted.\n" .. tostring(err))
  end

  -- Source buffers leave :buffers/:bnext; there is no content transfer.
  local retained = {}
  for _, entry in ipairs(plan) do
    if api.nvim_buf_is_valid(entry.old) then
      if vim.bo[entry.old].modified or #fn.win_findbuf(entry.old) > 0 then
        retained[#retained + 1] = entry.relative
      else
        local deleted = pcall(api.nvim_buf_delete, entry.old, { force = false })
        if not deleted then retained[#retained + 1] = entry.relative end
      end
    end
  end
  vim.g.worktree_root = target
  vim.g.worktree_branch = selected.branch or "detached"
  local message = "Switched to " .. display(selected.branch or "detached") .. "\n" .. display(target)
  if #missing_paths > 0 then
    message = message .. "\nUnavailable: " .. display(table.concat(missing_paths, ", "))
  end
  if #retained > 0 then
    message = message .. "\nOld buffers retained (in use/modified): " .. display(table.concat(retained, ", "))
  end
  notify(message, (#missing_paths > 0 or #retained > 0) and vim.log.levels.WARN or nil)
  local event_ok, event_err = pcall(api.nvim_exec_autocmds, "User", {
    pattern = "WorktreeSwitched",
    modeline = false,
    data = { from = source, to = target, branch = selected.branch, missing = missing_paths },
  })
  if not event_ok then notify("WorktreeSwitched hook failed: " .. tostring(event_err), vim.log.levels.WARN) end
end

---Switch the current editing workspace to an existing worktree of this repo.
---@param path string Absolute or current-directory-relative worktree path.
---@return boolean success
---@return string? error
function M.switch(path)
  if C.busy then
    notify("A worktree operation is already running.", vim.log.levels.WARN); return false
  end
  if type(path) ~= "string" or path == "" then
    notify("A worktree path is required.", vim.log.levels.ERROR); return false
  end
  C.busy = true
  local ok, err = pcall(switch_impl, path)
  C.busy = false
  if not ok then notify(tostring(err), vim.log.levels.ERROR) end
  return ok, err
end

return M
