-- Read-only inspection and removal policy. Cached remote refs are never proof
-- that a commit is currently present on the remote; remove.lua verifies that.
local M = {}
local C = require("plugins.fzf_custom.worktree_picker.common")
local api, fn, uv = vim.api, vim.fn, vim.uv

local function add(list, text) list[#list + 1] = text end

function M.parse_status(raw)
  local result = { staged = 0, unstaged = 0, untracked = 0, files = {}, ignored = {} }
  local records, i = C.split0(raw), 1
  while i <= #records do
    local record = records[i]
    local xy, path = record:sub(1, 2), record:sub(4)
    if xy == "!!" then
      add(result.ignored, path)
    else
      local entry = { xy = xy, path = path }
      if xy == "??" then
        result.untracked = result.untracked + 1
      else
        if xy:sub(1, 1) ~= " " then result.staged = result.staged + 1 end
        if xy:sub(2, 2) ~= " " then result.unstaged = result.unstaged + 1 end
        -- In porcelain -z, rename/copy destination precedes a second, source path.
        if xy:find("R", 1, true) or xy:find("C", 1, true) then
          i = i + 1
          entry.original = records[i]
        end
      end
      add(result.files, entry)
    end
    i = i + 1
  end
  return result
end

-- Includes unlisted buffers and any window/tab-local working directories.
function M.editor_state(path, trees)
  local state = { buffers = {}, modified = {}, displayed = {}, terminals = {}, cwd = false }
  local function inside(name)
    return name ~= "" and C.owned_relative(name, path, trees) ~= nil
  end
  if inside(fn.getcwd(-1, -1)) then state.cwd = true end
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_call(win, function() return inside(fn.getcwd()) end) then
      state.cwd = true
    end
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(buf) then
      local name = api.nvim_buf_get_name(buf)
      local missing = vim.b[buf].worktree_missing
      if vim.bo[buf].buftype == "terminal" then
        local terminal_cwd = name:match("^term://(.-)//")
        if terminal_cwd and inside(terminal_cwd) then add(state.terminals, buf) end
      elseif (vim.bo[buf].buftype == "" and inside(name))
          or (missing and missing.root == path) then
        add(state.buffers, buf)
        if vim.bo[buf].modified then add(state.modified, buf) end
        if #fn.win_findbuf(buf) > 0 then add(state.displayed, buf) end
      end
    end
  end
  return state
end

local function upstream(path, branch)
  if not branch then return nil end
  local raw = C.git(path, "for-each-ref",
    "--format=%(upstream)%00%(upstream:short)%00%(upstream:remotename)%00%(upstream:remoteref)",
    "refs/heads/" .. branch)
  if raw == "" then return nil end
  local fields = C.split0((raw:gsub("\n$", "")))
  if not fields[1] or fields[1] == "" then return nil end
  local u = { full = fields[1], short = fields[2], remote = fields[3], remote_ref = fields[4] }
  local ok, counts = pcall(C.git, path, "rev-list", "--left-right", "--count", "HEAD..." .. u.full)
  if ok then
    local ahead, behind = counts:match("(%d+)%s+(%d+)")
    u.ahead, u.behind = tonumber(ahead), tonumber(behind)
  else
    u.gone = true
  end
  return u
end

function M.inspect(tree, source, trees, thorough)
  local d = { tree = tree, blockers = {}, warnings = {} }
  local block = function(text) add(d.blockers, text) end
  local warn = function(text) add(d.warnings, text) end
  if tree.main then block("Main worktree: cannot be removed.") end
  if tree.bare then block("Bare repository: cannot be removed.") end
  if tree.path == source then block("Active worktree: switch elsewhere first.") end
  if tree.locked then block("Locked: " .. (tree.lock_reason or "unlock explicitly first")) end
  if tree.prunable or fn.isdirectory(tree.path) ~= 1 then
    block("Unavailable/stale worktree: repair or prune it manually.")
    return d
  end
  if C.root_at(tree.path) ~= tree.path then
    C.fail("Worktree path does not resolve to the expected repository root.")
  end
  for _, other in ipairs(trees) do
    if other.path ~= tree.path and C.relative(other.path, tree.path) ~= nil then
      block("Contains another registered worktree: " .. C.display(other.path))
    end
  end
  d.editor = M.editor_state(tree.path, trees)
  if #d.editor.modified > 0 then block("Unsaved Neovim edits in this worktree.") end
  if #d.editor.displayed > 0 then block("Files/placeholders still displayed in an editor window.") end
  if #d.editor.terminals > 0 then block("A terminal buffer belongs to this worktree; close it first.") end
  if d.editor.cwd and tree.path ~= source then block("A Neovim working directory still uses this worktree.") end

  d.raw_status = C.git(tree.path, "status", "--porcelain=v1", "-z",
    "--untracked-files=normal", "--ignored=matching", "--ignore-submodules=none")
  d.status = M.parse_status(d.raw_status)
  if #d.status.files > 0 then block("Uncommitted changes or untracked paths: commit, move or remove them first.") end
  if #d.status.ignored > 0 then
    warn(#d.status.ignored .. " ignored paths/directories will be permanently deleted (including their contents).")
  end
  if not tree.head or tree.head:match("^0+$") then
    block("No committed HEAD; create a commit before removing this worktree.")
    return d
  end
  d.latest = (C.git(tree.path, "show", "-s", "--format=%h %cr | %s", "HEAD"):gsub("\n$", ""))
  d.upstream = upstream(tree.path, tree.branch)
  local u = d.upstream
  if not tree.branch then
    warn("Detached HEAD: a recovery branch will be created to retain the current commit and its ancestors.")
  elseif not u or not u.remote or u.remote == "" or u.remote == "." then
    warn("No configured remote upstream; remote backup is not verified.")
  elseif u.gone or u.ahead == nil then
    warn("Upstream tracking ref is unavailable; remote backup is not verified.")
  elseif u.ahead > 0 then
    warn(u.ahead .. " commits ahead of cached " .. C.display(u.short or u.full)
      .. "; the local branch will be retained.")
  elseif u.behind > 0 then
    warn("Branch is behind its cached upstream; it is not an exact synced checkout.")
  end

  if thorough then
    local gd = (C.git(tree.path, "rev-parse", "--absolute-git-dir"):gsub("\n$", ""))
    for _, name in ipairs({ "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge",
      "rebase-apply", "sequencer", "BISECT_LOG", "index.lock", "HEAD.lock" }) do
      if uv.fs_stat(gd .. "/" .. name) then block("Git operation/state still present: " .. name) end
    end
    if uv.fs_stat(gd .. "/config.worktree") then
      warn("Per-worktree Git configuration will be removed with its administrative directory.")
    end
    -- Status can hide edits under assume-unchanged / skip-worktree. Never bypass
    -- those flags or submodule protection from this picker, even after confirming.
    local index = C.git(tree.path, "ls-files", "-v", "--stage", "-z")
    local special, submodule = false, false
    for record in index:gmatch("([^%z]+)") do
      local tag, mode = record:match("^(%a) (%d+)")
      if tag and (tag == "S" or tag == tag:lower()) then special = true end
      if mode == "160000" then submodule = true end
    end
    if special then block("Index uses assume-unchanged/skip-worktree flags; review/remove manually.") end
    if submodule then block("Contains submodule entries; review/remove manually.") end
  end
  return d
end

function M.safe_inspect(tree, source, trees, thorough)
  local ok, d = pcall(M.inspect, tree, source, trees, thorough)
  if ok then return d end
  return { tree = tree, error = tostring(d), warnings = {}, blockers = { "Inspection failed: " .. tostring(d) } }
end

function M.fingerprint(d)
  local u, t = d.upstream or {}, d.tree
  return table.concat({ t.path, t.head or "", t.branch or "", tostring(t.locked),
    d.raw_status or "", u.full or "", u.remote or "", u.remote_ref or "",
    tostring(u.ahead), tostring(u.behind), table.concat(d.warnings, "\n") }, "\0")
end

return M
