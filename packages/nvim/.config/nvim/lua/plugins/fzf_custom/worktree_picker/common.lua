-- Shared path/Git helpers. No shell-interpolated repository paths.
local M = { busy = false }
local api, fn, uv = vim.api, vim.fn, vim.uv

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Worktrees" })
end

local function fail(message)
  error(message, 0)
end

local function normalize(path)
  local normalized = vim.fs.normalize(path, { expand_env = false })
  if #normalized > 1 and not normalized:match("^%a:/$") then
    normalized = normalized:gsub("/$", "")
  end
  return normalized
end

-- Control characters must not become fzf row separators or terminal escapes.
local function display(text)
  return (text:gsub("%c", function(c) return string.format("\\x%02x", c:byte()) end))
end

local function relative(path, root)
  if path == root then return "" end
  local prefix = root .. "/"
  if path:sub(1, #prefix) == prefix then return path:sub(#prefix + 1) end
end

local function run(cwd, args, opts)
  opts = opts or {}
  local argv = { "git", "-C", cwd }
  for _, arg in ipairs(args) do argv[#argv + 1] = arg end
  local timeout = opts.timeout == nil and 5000 or opts.timeout
  local result = vim.system(argv, {
    timeout = timeout ~= false and timeout or nil,
    env = { GIT_TERMINAL_PROMPT = "0", GIT_OPTIONAL_LOCKS = "0" },
  }):wait()
  if result.code ~= 0 then
    fail(vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr)
      or "Git failed or timed out.")
  end
  return result.stdout or ""
end

local function git(cwd, ...)
  return run(cwd, { ... })
end

local function root_at(path)
  local ok, root = pcall(git, path, "rev-parse", "--show-toplevel")
  -- Strip exactly the output terminator, not whitespace in the directory name.
  return ok and normalize((root:gsub("\n$", ""))) or nil
end

local function worktrees(root)
  local trees, item = {}, nil
  -- -z preserves spaces, tabs, backslashes and newlines in real paths.
  for field in git(root, "worktree", "list", "--porcelain", "-z"):gmatch("([^%z]+)") do
    local path = field:match("^worktree (.*)$")
    if path then
      item = { path = normalize(path), main = #trees == 0 }
      trees[#trees + 1] = item
    elseif item then
      if field == "bare" then item.bare = true end
      if field == "locked" or field:match("^locked ") then
        item.locked = true
        item.lock_reason = field:sub(8)
      end
      if field == "prunable" or field:match("^prunable ") then item.prunable = true end
      item.branch = field:match("^branch refs/heads/(.*)$") or item.branch
      item.head = field:match("^HEAD (.*)$") or item.head
    end
  end
  return trees
end

local function context()
  local root = root_at(fn.getcwd())
  if not root then
    local placeholder = vim.b.worktree_missing
    if placeholder then root = root_at(placeholder.root) end
  end
  if not root and vim.bo.buftype == "" then
    local name = api.nvim_buf_get_name(0)
    if name ~= "" then root = root_at(vim.fs.dirname(name)) end
  end
  if not root then fail("Run the picker from a Git worktree or one of its files.") end

  return root, worktrees(root)
end

-- Longest match prevents a nested .worktrees/foo checkout being mistaken for
-- part of its parent checkout. Symlink aliases of the checkout are recognized.
local function owned_relative(path, root, trees)
  local function match(candidate)
    local owner, rel
    for _, tree in ipairs(trees) do
      local r = relative(candidate, tree.path)
      if r ~= nil and (not owner or #tree.path > #owner) then
        owner, rel = tree.path, r
      end
    end
    if owner == root then return rel end
  end
  local rel = match(normalize(path))
  if rel ~= nil then return rel end
  return match(normalize(fn.resolve(path)))
end


M.notify = notify
M.fail = fail
M.normalize = normalize
M.display = display
M.relative = relative
M.run = run
M.git = git
M.root_at = root_at
M.worktrees = worktrees
M.context = context
M.owned_relative = owned_relative

function M.absolute(path)
  if type(path) ~= "string" or path == "" then fail("A worktree path is required.") end
  path = normalize(fn.fnamemodify(path, ":p"))
  return normalize(uv.fs_realpath(path) or path)
end

function M.find(root, path)
  path = M.absolute(path)
  local trees = worktrees(root)
  for _, tree in ipairs(trees) do
    if tree.path == path then return tree, trees end
  end
  fail("Not a registered worktree of this repository: " .. display(path))
end

function M.split0(text)
  local items, start = {}, 1
  while true do
    local pos = text:find("\0", start, true)
    if not pos then break end
    items[#items + 1] = text:sub(start, pos - 1)
    start = pos + 1
  end
  if start <= #text then items[#items + 1] = text:sub(start) end
  return items
end

return M
