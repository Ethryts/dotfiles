-- fzf-lua interface. Rows and previews are local snapshots; Ctrl-R refreshes.
-- Removal always re-inspects live state, regardless of what this snapshot says.
local M = {}
local C = require("plugins.fzf_custom.worktree_picker.common")
local I = require("plugins.fzf_custom.worktree_picker.inspect")
local fn = vim.fn

local function color(code, text) return "\27[" .. code .. "m" .. text .. "\27[0m" end
local function heading(text) return color("1;36", text) end
local function label(tree) return tree.branch or ("detached@" .. (tree.head or "?"):sub(1, 8)) end

local function status_text(d)
  if not d.status then return "unavailable" end
  local s, parts = d.status, {}
  if s.staged > 0 then parts[#parts + 1] = "S" .. s.staged end
  if s.unstaged > 0 then parts[#parts + 1] = "W" .. s.unstaged end
  if s.untracked > 0 then parts[#parts + 1] = "?" .. s.untracked end
  if #parts == 0 then parts[1] = "clean" end
  if #s.ignored > 0 then parts[#parts + 1] = "I" .. #s.ignored end
  return table.concat(parts, " ")
end

local function sync_text(d)
  local u = d.upstream
  if not u then return "no upstream" end
  if u.ahead == nil then return "upstream?" end
  return string.format("+%d/-%d", u.ahead, u.behind)
end

local function removal_text(d)
  if #d.blockers > 0 then return "BLOCKED" end
  if #d.warnings > 0 then return "CONFIRM" end
  return "VERIFY"
end

function M.row(id, d, source)
  local t = d.tree
  local name = label(t) .. (t.main and " [MAIN]" or "") .. (t.locked and " [LOCK]" or "")
  return string.format("%d\t%s %-28s | %-16s | %-12s | %-7s | %s", id,
    t.path == source and "*" or " ", C.display(name), status_text(d), sync_text(d),
    removal_text(d), C.display(fn.fnamemodify(t.path, ":~")))
end

-- One shared graph for this picker, not an unrelated log per highlighted item.
-- Its roots are checked-out worktree HEADs and their available upstream refs.
function M.graph(root, details, limit)
  local refs, seen = {}, {}
  local function push(ref)
    if ref and ref ~= "" and not ref:match("^0+$") and not seen[ref] then
      seen[ref] = true; refs[#refs + 1] = ref
    end
  end
  for _, d in ipairs(details) do
    push(d.tree.head)
    if d.upstream and not d.upstream.gone then push(d.upstream.full) end
  end
  if #refs == 0 then return "No committed history." end
  local args = { "log", "--graph", "--date-order", "--decorate=short", "--color=never",
    "--abbrev=8", "--max-count=" .. limit, "--format=%H%x09%h %d %s" }
  for _, ref in ipairs(refs) do args[#args + 1] = ref end
  args[#args + 1] = "--"
  local ok, output = pcall(C.run, root, args)
  return ok and output or ("Graph unavailable: " .. C.display(tostring(output)))
end

function M.preview(d, details, graph, opts)
  local t, lines = d.tree, {}
  local function add(s) lines[#lines + 1] = s end
  add(heading(C.display(label(t))) .. (t.path == opts.source and "  [ACTIVE]" or "  [SELECTED]"))
  add("Path: " .. C.display(t.path))
  add("HEAD: " .. C.display(d.latest or t.head or "unavailable"))
  add("Local: " .. status_text(d))
  if d.upstream then
    add("Upstream: " .. C.display(d.upstream.short or d.upstream.full) .. "  " .. sync_text(d) .. " (cached)")
  else
    add("Upstream: none configured")
  end
  add("")
  add(heading("REMOVE: " .. removal_text(d)))
  if #d.blockers > 0 then
    for _, reason in ipairs(d.blockers) do add("  " .. C.display(reason)) end
  elseif #d.warnings > 0 then
    for _, reason in ipairs(d.warnings) do add("  " .. C.display(reason)) end
    add("  Ctrl-X requires typing the removal phrase. Branches are kept.")
  else
    add("  Ctrl-X checks the live upstream. Exact match: no dialog.")
    add("  A failed/mismatched remote check requires typed confirmation.")
  end
  add("  Extra index/operation checks run again immediately before removal.")
  if d.editor and #d.editor.modified > 0 then
    for _, buf in ipairs(d.editor.modified) do add("  unsaved: " .. C.display(vim.api.nvim_buf_get_name(buf))) end
  end
  if d.status and #d.status.ignored > 0 then
    add(""); add(heading("IGNORED PATHS -- removal deletes their contents"))
    for i = 1, math.min(opts.file_limit, #d.status.ignored) do add("  " .. C.display(d.status.ignored[i])) end
    if #d.status.ignored > opts.file_limit then add("  ... more ignored paths") end
  end
  if d.status and #d.status.files > 0 then
    add(""); add(heading("WORKING CHANGES -- index / working tree"))
    for i = 1, math.min(opts.file_limit, #d.status.files) do
      local f = d.status.files[i]
      add("  " .. f.xy .. " " .. (f.original and (C.display(f.original) .. " -> ") or "") .. C.display(f.path))
    end
    if #d.status.files > opts.file_limit then add("  ... more changes") end
  end
  add(""); add(heading("WORKTREE GRAPH -- recent " .. opts.graph_limit .. " commits"))
  add("  Roots: worktree HEADs + their upstreams. <SELECTED> marks this HEAD.")
  local at_head = {}
  for _, other in ipairs(details) do
    if other.tree.head then
      at_head[other.tree.head] = at_head[other.tree.head] or {}
      table.insert(at_head[other.tree.head], label(other.tree))
    end
  end
  for line in graph:gmatch("[^\n]+") do
    local prefix, sha, rest = line:match("^(.-)([0-9a-f]+)\t(.*)$")
    if sha then
      local text = C.display(prefix .. rest)
      if at_head[sha] then text = text .. "  [wt: " .. C.display(table.concat(at_head[sha], ", ")) .. "]" end
      if sha == t.head then text = color("1;33", text .. "  <SELECTED>") end
      add(text)
    else
      add(C.display(line))
    end
  end
  if d.upstream and not d.upstream.gone and not d.error then
    add(""); add(heading("COMMITTED DIFF -- from merge-base with upstream"))
    if not d.diffstat then
      local ok, stat = pcall(function()
        local base = (C.git(t.path, "merge-base", "HEAD", d.upstream.full):gsub("\n$", ""))
        return C.git(t.path, "diff", "--no-ext-diff", "--no-textconv", "--color=never",
          "--stat", "--stat-width=78", base, "HEAD", "--")
      end)
      d.diffstat = ok and stat or ("Unavailable: " .. tostring(stat))
    end
    local count = 0
    for line in d.diffstat:gmatch("[^\n]+") do
      count = count + 1
      if count <= opts.file_limit then add(C.display(line)) end
    end
    if count == 0 then add("  No committed changes since that merge-base.") end
    if count > opts.file_limit then add("  ... more files (truncated)") end
  end
  add(""); add("Ctrl-D / Ctrl-U: scroll preview. Ctrl-R: local refresh. Ctrl-F: fetch remote.")
  add("Stop external agents/dev servers before removal; use Ctrl-L to protect an active task.")
  return table.concat(lines, "\n")
end

local function fetch(path, done)
  if C.busy then
    C.notify("Another worktree operation is running.", vim.log.levels.WARN); return
  end
  C.busy = true
  local function finish(ok, message)
    C.busy = false
    C.notify(message, ok and vim.log.levels.INFO or vim.log.levels.WARN)
    vim.schedule(done)
  end
  local ok, err = pcall(function()
    local root, trees = C.context()
    local tree = C.find(root, path)
    local d = I.safe_inspect(tree, root, trees, false)
    local remote = d.upstream and d.upstream.remote or "origin"
    if not remote or remote == "" or remote == "." then remote = "origin" end
    local found = false
    for name in C.git(root, "remote"):gmatch("[^\n]+") do if name == remote then found = true end end
    if not found then C.fail("No configured remote named " .. C.display(remote) .. ".") end
    C.notify("Fetching " .. C.display(remote) .. "...")
    vim.system({ "git", "-C", root, "fetch", "--no-tags", "--no-recurse-submodules", "--", remote },
      { timeout = 30000, env = { GIT_TERMINAL_PROMPT = "0" } }, function(result)
        vim.schedule(function()
          finish(result.code == 0, result.code == 0 and ("Fetched " .. C.display(remote))
            or ("Fetch failed: " .. C.display(vim.trim(result.stderr or "timeout or unknown error"))))
        end)
      end)
  end)
  if not ok then finish(false, tostring(err)) end
end

function M.pick(opts)
  opts = opts or {}
  if C.busy then
    C.notify("Another worktree operation is running.", vim.log.levels.WARN); return
  end
  local ok, source, trees = pcall(C.context)
  if not ok then
    C.notify(tostring(source), vim.log.levels.ERROR); return
  end
  local settings = {
    source = source,
    graph_limit = math.max(5, math.min(200, math.floor(tonumber(opts.graph_limit) or 45))),
    file_limit = math.max(3, math.min(100, math.floor(tonumber(opts.file_limit) or 12))),
  }
  local entries, details = {}, {}
  for _, tree in ipairs(trees) do
    if not tree.bare then
      local d = I.safe_inspect(tree, source, trees, false)
      details[#details + 1] = d
      entries[#entries + 1] = M.row(#details, d, source)
    end
  end
  if #entries == 0 then
    C.notify("No worktrees found.", vim.log.levels.WARN); return
  end
  local graph
  local function selected(items)
    local id = items and items[1] and tonumber(items[1]:match("^(%d+)\t"))
    return id and details[id]
  end
  local function again(action_opts)
    local next_opts = vim.deepcopy(opts)
    -- Best-effort query preservation across a close/reopen, not a safety dependency.
    next_opts.query = action_opts and action_opts.__call_opts and action_opts.__call_opts.query or opts.query
    return function() M.pick(next_opts) end
  end
  require("fzf-lua").fzf_exec(entries, {
    prompt = "Worktrees> ",
    query = opts.query,
    previewer = false,
    preview = function(items)
      local d = selected(items)
      if not d then return "Select a worktree." end
      graph = graph or M.graph(source, details, settings.graph_limit)
      return M.preview(d, details, graph, settings)
    end,
    winopts = {
      width = 0.95,
      height = 0.9,
      preview = {
        layout = "flex",
        flip_columns = 150,
        horizontal = "right:60%",
        vertical = "down:60%",
        hidden = false,
        wrap = false
      },
    },
    fzf_opts = {
      ["--multi"] = false,
      ["--no-multi"] = true,
      ["--delimiter"] = "\t",
      ["--with-nth"] = "2..",
      ["--header"] = "Enter switch | Ctrl-X remove | Ctrl-L lock | Ctrl-F fetch | Ctrl-R refresh\n"
          .. "* active | S staged W unstaged ? untracked I ignored | +/- cached upstream",
    },
    keymap = { fzf = { ["ctrl-d"] = "preview-page-down", ["ctrl-u"] = "preview-page-up" } },
    actions = {
      ["enter"] = function(items)
        local d = selected(items)
        if d then vim.schedule(function() require("plugins.fzf_custom.worktree_picker.switch").switch(d.tree.path) end) end
      end,
      ["ctrl-x"] = function(items, o)
        local d, done = selected(items), again(o)
        if d then vim.schedule(function() require("plugins.fzf_custom.worktree_picker.remove").remove(d.tree.path, done) end) end
      end,
      ["ctrl-l"] = function(items, o)
        local d, done = selected(items), again(o)
        if d then vim.schedule(function() require("plugins.fzf_custom.worktree_picker.remove").toggle_lock(d.tree.path,
              done) end) end
      end,
      ["ctrl-f"] = function(items, o)
        local d, done = selected(items), again(o)
        if d then vim.schedule(function() fetch(d.tree.path, done) end) end
      end,
      ["ctrl-r"] = function(_, o) vim.schedule(again(o)) end,
    },
  })
end

return M
