-- ~/.config/nvim/lua/worktree_picker.lua
-- Neovim 0.10+, fzf-lua, Git, tmux and Bash/Zsh.
-- A worktree is a tmux workspace. This module NEVER remaps editor buffers,
-- changes Neovim's cwd, saves/stashes edits, or terminates an existing session.
local M = {}
local api, fn, uv = vim.api, vim.fn, vim.uv
local config = {
  shell = nil,         -- defaults to $SHELL
  work_file = vim.fn.expand((vim.env.XDG_CONFIG_HOME or "~/.config") .. "/bash/scripts/work.sh"),
  worktrees_dir = nil, -- defaults to <primary-parent>/.worktrees/<repo>
}
local opening = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Worktrees" })
end
local function fail(message) error(message, 0) end
local function display(text)
  return (tostring(text):gsub("%c", function(c) return string.format("\\x%02x", c:byte()) end))
end
local function normalize(path)
  local normalized = vim.fs.normalize(uv.fs_realpath(path) or path, { expand_env = false })
  return normalized == "/" and normalized or (normalized:gsub("/$", ""))
end
local function inside(path, root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end
local function run(argv, timeout)
  return vim.system(argv, { timeout = timeout or 5000 }):wait()
end
local function checked(argv, timeout)
  local result = run(argv, timeout)
  if result.code ~= 0 then
    fail(vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or "Command failed or timed out: " .. argv[1])
  end
  return result.stdout or ""
end
local function git(path, ...)
  return checked({ "git", "-C", path, ... })
end
local function root_at(path)
  local ok, result = pcall(git, path, "rev-parse", "--show-toplevel")
  return ok and normalize(result:gsub("\n$", "")) or nil
end
local function parse_worktrees(text)
  local trees, item = {}, nil
  for field in text:gmatch("([^%z]+)") do
    local path = field:match("^worktree (.*)$")
    if path then
      item = { path = normalize(path) }
      trees[#trees + 1] = item
    elseif item then
      if field == "bare" then item.bare = true end
      if field:match("^locked") then item.locked = true end
      if field:match("^prunable") then item.prunable = true end
      item.branch = field:match("^branch refs/heads/(.*)$") or item.branch
      item.head = field:match("^HEAD (.*)$") or item.head
    end
  end
  return trees
end
local function context(path)
  local root = root_at(path or fn.getcwd())
  if not root and not path and vim.bo.buftype == "" then
    local filename = api.nvim_buf_get_name(0)
    if filename ~= "" then root = root_at(vim.fs.dirname(filename)) end
  end
  if not root then fail("Open the picker from a Git worktree or one of its files.") end
  local trees = parse_worktrees(git(root, "worktree", "list", "--porcelain", "-z"))
  if not trees[1] then fail("No worktrees found.") end
  local primary = trees[1].path
  local repo = vim.fs.basename(primary)
  if repo == ".bare" or repo == ".git" then repo = vim.fs.basename(vim.fs.dirname(primary)) end
  repo = repo:gsub("%.git$", "")
  return { root = root, trees = trees, primary = primary, repo = repo }
end
local function resolve(ctx, path)
  path = normalize(fn.fnamemodify(path, ":p"))
  for _, tree in ipairs(ctx.trees) do
    if tree.path == path and not tree.bare then return tree end
  end
  fail("The target is not a worktree of this repository.")
end
local function sessions()
  local by_path = {}
  local result = run({ "tmux", "list-sessions", "-F", "#{session_id}" })
  if result.code ~= 0 then
    -- When inside tmux, failure is not equivalent to 'no running workspaces'.
    if vim.env.TMUX then fail("Cannot inspect tmux sessions; refusing to guess.") end
    return by_path
  end
  for id in result.stdout:gmatch("[^\n]+") do
    local path = checked({ "tmux", "show-options", "-qv", "-t", id, "@worktree_root" }):gsub("\n$", "")
    local name = checked({ "tmux", "display-message", "-p", "-t", id, "#{session_name}" }):gsub("\n$", "")
    if path == "" then
      -- Recognize sessions from the old work() too.
      local original = checked({ "tmux", "display-message", "-p", "-t", id, "#{session_path}" }):gsub("\n$", "")
      if name == vim.fs.basename(original) then path = original end
    end
    if path ~= "" then by_path[normalize(path)] = { id = id, name = name } end
  end
  return by_path
end

-- Use Neovim theme colours when available, terminal ANSI colours otherwise.
local function colour(text, group, fallback)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = group, link = false })
  local prefix
  if ok and hl.fg then
    local n = hl.fg
    prefix = string.format("\27[38;2;%d;%d;%dm", math.floor(n / 65536), math.floor(n / 256) % 256, n % 256)
  else
    prefix = "\27[" .. fallback .. "m"
  end
  return prefix .. text .. "\27[0m"
end
local function selected_tree(selected, choices)
  local line = selected and selected[1]
  -- IDs are uncoloured, and paths are never recovered by splitting display text.
  local id = line and tonumber(line:match("^(%d+)\t"))
  return id and choices[id] or nil
end
local function quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end
local function preview_command(tree, session)
  if not tree then return "printf ''" end
  local header = display(tree.path) .. "\n" .. (session and "tmux: " .. display(session.name) or "tmux: not started")
  local g = "git --no-pager -C " .. quote(tree.path) .. " -c color.ui=always "
  return "printf '%s\\n\\n' " .. quote(header)
      .. "; " .. g .. "status --short --branch"
      .. "; printf '\\n'; " .. g .. "diff --no-ext-diff --stat"
      .. "; printf '\\n'; " .. g .. "log -6 --color=always --format='%C(yellow)%h%Creset %s %C(dim white)(%cr)%Creset'"
end

---Open or reuse a tmux workspace. Unsaved editor buffers stay untouched.
---@param path string
---@return boolean started
function M.open(path)
  if opening then
    notify("A workspace is already opening.", vim.log.levels.WARN); return false
  end
  local ok, err = pcall(function()
    if type(path) ~= "string" or path == "" then fail("A worktree path is required.") end
    if not vim.env.TMUX or not vim.env.TMUX_PANE then
      fail("Start this Neovim inside tmux first (run work from your terminal).")
    end
    local tree = resolve(context(), path)
    if fn.isdirectory(tree.path) ~= 1 then fail("The worktree directory is missing.") end
    if tree.path:find("[\n\r\t]") then fail("Tabs/newlines in worktree paths are not supported by work().") end
    local shell = config.shell or vim.env.SHELL or "/bin/bash"
    local shell_name = vim.fs.basename(shell)
    if shell_name ~= "bash" and shell_name ~= "zsh" then
      fail("Configure shell = '/bin/bash' or '/bin/zsh'; the supplied work() uses Bash/Zsh syntax.")
    end
    local command = 'cd -- "$WORKTREE_TARGET" && work'
    local env = { WORKTREE_TARGET = tree.path }
    if config.work_file then
      if fn.filereadable(config.work_file) ~= 1 then fail("Install the updated work function at " .. config.work_file) end
      env.WORK_FUNCTION_FILE = config.work_file
      command = 'source "$WORK_FUNCTION_FILE" && ' .. command
    end
    local client = checked({ "tmux", "display-message", "-p", "-t", vim.env.TMUX_PANE, "#{client_name}" }):gsub("\n$", "")
    if client == "" then fail("No attached tmux client could be found for this Neovim pane.") end
    env.WORK_TMUX_CLIENT = client
    opening = true
    vim.system({ shell, "-ic", command }, { env = env, text = true, timeout = 20000 }, function(result)
      vim.schedule(function()
        opening = false
        if result.code ~= 0 then
          notify("work failed:\n" .. vim.trim((result.stderr or "") .. "\n" .. (result.stdout or "")),
            vim.log.levels.ERROR)
        end
      end)
    end)
  end)
  if not ok then
    opening = false; notify(tostring(err), vim.log.levels.ERROR)
  end
  return ok
end

M.switch = M.open -- compatibility with existing mappings; no editor switching.

local function assert_removable(ctx, tree)
  if tree.path == ctx.root then fail("Cannot remove the current worktree.") end
  if tree.path == ctx.primary then fail("Cannot remove the primary checkout.") end
  if tree.locked then fail("The worktree is locked. Ctrl-L explicitly unlocks it.") end
  if tree.prunable or fn.isdirectory(tree.path) ~= 1 then fail("Missing/stale worktree: inspect it manually.") end
  if tree.path:find("[\n\r\t]") then fail("Refusing removal of a control-character path.") end
  if not tree.branch then fail("Detached HEAD: inspect and preserve its commits manually.") end
  local running = sessions()[tree.path]
  if running then fail("Close this workspace normally first: " .. running.name .. ". No sessions will be killed.") end
  -- Also catch shells/editors in worktrees belonging to manually named sessions.
  local pane_paths = checked({ "tmux", "list-panes", "-a", "-F", "#{pane_current_path}" })
  for path in pane_paths:gmatch("[^\n]+") do
    if inside(normalize(path), tree.path) then fail("A tmux pane is still using this worktree.") end
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local name = api.nvim_buf_get_name(buf)
    if name ~= "" and inside(normalize(name), tree.path)
        and (vim.bo[buf].modified or #fn.win_findbuf(buf) > 0) then
      fail("A modified or displayed buffer still uses this worktree: " .. display(name))
    end
  end
  -- Git status can hide changes behind these index flags; fail closed.
  for entry in git(tree.path, "ls-files", "-v", "-z"):gmatch("([^%z]+)") do
    local flag = entry:sub(1, 1)
    if flag == "S" or flag:match("[a-z]") then
      fail("Removal blocked: assume-unchanged/skip-worktree index flags need manual review.")
    end
  end
  -- Include ignored files: .env, local artifacts and environments must not be
  -- silently deleted merely because git status normally hides them.
  local changes = git(tree.path, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored=matching",
    "--ignore-submodules=none")
  if changes ~= "" then fail("Removal blocked: tracked changes, untracked files, or ignored files exist.") end
  local upstream = run({ "git", "-C", tree.path, "rev-parse", "--verify", "@{upstream}" })
  if upstream.code ~= 0 then fail("No upstream configured; cannot verify the commits are preserved remotely.") end
  local remote = git(tree.path, "config", "--get", "branch." .. tree.branch .. ".remote"):gsub("\n$", "")
  if remote == "." then fail("Upstream is a local branch, not a remote-tracking branch.") end
  if run({ "git", "-C", tree.path, "merge-base", "--is-ancestor", "HEAD", "@{upstream}" }).code ~= 0 then
    fail("Unpushed/diverged commits detected. Push or integrate them before removal.")
  end
end

function M.remove(path)
  local ok, err = pcall(function()
    local ctx = context()
    local tree = resolve(ctx, path)
    assert_removable(ctx, tree)
    -- Git rechecks its own guards. Never use --force or delete the branch.
    git(ctx.root, "worktree", "remove", "--", tree.path)
    notify("Removed checkout; branch retained: " .. display(tree.branch))
  end)
  if not ok then notify(tostring(err), vim.log.levels.WARN) end
  return ok
end

function M.create()
  local ok, ctx = pcall(context)
  if not ok then
    notify(tostring(ctx), vim.log.levels.ERROR); return
  end
  vim.ui.input({ prompt = "Worktree branch (existing, or new from current HEAD): " }, function(branch)
    if not branch or branch == "" then return end
    local created, err = pcall(function()
      git(ctx.root, "check-ref-format", "--branch", branch)
      local slug = branch:gsub("[^A-Za-z0-9_-]", "-")
      local parent = config.worktrees_dir or (vim.fs.dirname(ctx.primary) .. "/.worktrees/" .. ctx.repo)
      local path = vim.fs.normalize(parent .. "/" .. slug)
      if uv.fs_lstat(path) then fail("The target path already exists: " .. display(path)) end
      local exists = run({ "git", "-C", ctx.root, "show-ref", "--verify", "--quiet", "refs/heads/" .. branch })
      if exists.code == 0 then
        git(ctx.root, "worktree", "add", "--", path, branch)
      elseif exists.code == 1 then
        git(ctx.root, "worktree", "add", "-b", branch, "--", path, "HEAD")
      else
        fail("Cannot determine whether the branch already exists.")
      end
      M.open(path)
    end)
    if not created then notify(tostring(err), vim.log.levels.ERROR) end
  end)
end

local function toggle_lock(tree)
  local ok, err = pcall(function()
    local ctx = context()
    tree = resolve(ctx, tree.path)
    if tree.path == ctx.primary then fail("The primary checkout cannot be locked this way.") end
    git(ctx.root, "worktree", tree.locked and "unlock" or "lock", "--", tree.path)
  end)
  if not ok then notify(tostring(err), vim.log.levels.WARN) end
  M.pick()
end

function M.pick()
  local ok, ctx, running = pcall(function() return context(), sessions() end)
  if not ok then
    notify(tostring(ctx), vim.log.levels.ERROR); return
  end
  local entries, choices = {}, {}
  for _, tree in ipairs(ctx.trees) do
    if not tree.bare then
      choices[#choices + 1] = tree
      local marker, group, fallback = "new", "Comment", "90"
      if running[tree.path] then marker, group, fallback = "open", "DiagnosticOk", "32" end
      if tree.path == ctx.root then marker, group, fallback = "here", "Special", "36" end
      if fn.isdirectory(tree.path) ~= 1 then marker, group, fallback = "missing", "DiagnosticError", "31" end
      local branch = tree.branch or ("detached@" .. (tree.head or "?"):sub(1, 8))
      entries[#entries + 1] = string.format("%d\t%s %s%s %s", #choices,
        colour(string.format("%-7s", marker), group, fallback),
        colour(string.format("%-26s", display(branch)), "Directory", "34"),
        tree.locked and colour(" [locked]", "DiagnosticWarn", "33") or "",
        colour(display(tree.path), "Comment", "90"))
    end
  end
  if #entries == 0 then
    notify("No worktrees found.", vim.log.levels.WARN); return
  end
  local function action(callback)
    return function(selected)
      local tree = selected_tree(selected, choices)
      if tree then vim.schedule(function() callback(tree) end) end
    end
  end
  require("fzf-lua").fzf_exec(entries, {
    prompt = "Worktrees> ",
    header = "Enter: open  Ctrl-N: create  Ctrl-X: safe remove  Ctrl-L: lock  Ctrl-F: fetch  Ctrl-R: refresh",
    previewer = false,
    preview = {
      type = "cmd",
      fn = function(items)
        local tree = selected_tree(items, choices)
        return preview_command(tree, tree and running[tree.path])
      end
    },
    fzf_colors = true,
    winopts = { width = 0.92, height = 0.8, preview = { layout = "vertical", vertical = "down:45%" } },
    fzf_opts = {
      ["--ansi"] = true,
      ["--no-ansi"] = false,
      ["--no-color"] = false,
      ["--multi"] = false,
      ["--no-multi"] = true,
      ["--delimiter"] = "\t",
      ["--with-nth"] = "2..",
    },
    keymap = { fzf = { ["ctrl-d"] = "preview-half-page-down", ["ctrl-u"] = "preview-half-page-up" } },
    actions = {
      ["enter"] = action(function(tree) M.open(tree.path) end),
      ["ctrl-x"] = action(function(tree)
        M.remove(tree.path); M.pick()
      end),
      ["ctrl-l"] = action(toggle_lock),
      ["ctrl-r"] = function() vim.schedule(M.pick) end,
      ["ctrl-n"] = function() vim.schedule(M.create) end,
      ["ctrl-f"] = function()
        vim.schedule(function()
          notify("Fetching remote refs…")
          vim.system({ "git", "-C", ctx.root, "fetch", "--all", "--prune" }, { text = true }, function(result)
            vim.schedule(function()
              if result.code ~= 0 then notify(vim.trim(result.stderr or "Fetch failed."), vim.log.levels.ERROR) end
              M.pick()
            end)
          end)
        end)
      end,
    },
  })
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
  api.nvim_create_user_command("Worktrees", M.pick, { force = true })
  api.nvim_create_user_command("WorktreeSwitch", M.pick, { force = true })
  vim.keymap.set("n", "<leader>gw", M.pick, { desc = "Git worktree workspaces" })
end

return M
--
--
-- -- Replace the previous lua/worktree_picker.lua with this entry point.
-- -- Requires Neovim 0.10+, Git and fzf-lua. No other plugins are needed.
-- local M = {}
--
-- function M.pick(opts)
--   return require("plugins.fzf_custom.worktree_picker.picker").pick(opts)
-- end
--
-- function M.switch(path)
--   return require("plugins.fzf_custom.worktree_picker.switch").switch(path)
-- end
--
-- -- The same guarded removal used by Ctrl-X. There is deliberately no force flag.
-- -- on_done receives (success, message); confirmation/network checks may be async.
-- function M.remove(path, on_done)
--   return require("plugins.fzf_custom.worktree_picker.remove").remove(path, on_done)
-- end
--
-- return M
