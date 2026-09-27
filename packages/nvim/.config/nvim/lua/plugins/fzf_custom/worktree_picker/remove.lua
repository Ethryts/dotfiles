-- Guarded removal. No --force, git clean, reset, stash, or branch deletion.
local M = {}
local C = require("plugins.fzf_custom.worktree_picker.common")
local I = require("plugins.fzf_custom.worktree_picker.inspect")
local api, fn = vim.api, vim.fn

local function label(tree)
  return tree.branch or ("detached@" .. (tree.head or "?"):sub(1, 8))
end

local function report(d, reasons)
  local lines = { C.display(d.tree.path) }
  for _, reason in ipairs(reasons) do lines[#lines + 1] = "- " .. reason end
  if d.status then
    for i = 1, math.min(8, #d.status.files) do
      local f = d.status.files[i]
      lines[#lines + 1] = "  " .. f.xy .. " " .. C.display(f.path)
    end
    for i = 1, math.min(8, #d.status.ignored) do
      lines[#lines + 1] = "  ignored: " .. C.display(d.status.ignored[i])
    end
  end
  return table.concat(lines, "\n")
end

local function backup_detached(root, tree)
  local base = "worktree-backup/" .. os.date("!%Y%m%d-%H%M%S") .. "-" .. tree.head:sub(1, 8)
  for n = 0, 99 do
    local name = base .. (n == 0 and "" or ("-" .. n))
    local exists = pcall(C.git, root, "rev-parse", "--verify", "refs/heads/" .. name)
    if not exists then
      -- An explicit commit SHA is used, never whichever HEAD happens to be current.
      C.git(root, "branch", "--", name, tree.head)
      return name
    end
  end
  C.fail("Could not allocate a detached-HEAD recovery branch; nothing removed.")
end

function M.remove(path, on_done)
  if C.busy then
    C.notify("Another worktree operation is running.", vim.log.levels.WARN); return false
  end
  C.busy = true
  local completed = false
  local function finish(ok, message)
    if completed then return end
    completed, C.busy = true, false
    C.notify(message, ok and vim.log.levels.INFO or vim.log.levels.WARN)
    if on_done then vim.schedule(function() on_done(ok, message) end) end
  end
  local function guarded(f)
    local ok, err = pcall(f)
    if not ok then finish(false, tostring(err)) end
  end

  guarded(function()
    local root = C.context()
    path = C.absolute(path)
    local function fresh()
      local active = C.context()
      local tree, trees = C.find(root, path)
      return I.safe_inspect(tree, active, trees, true)
    end
    local original = fresh()
    if #original.blockers > 0 then
      finish(false, "Removal blocked.\n" .. report(original, original.blockers)); return
    end
    local fingerprint = I.fingerprint(original)

    local function commit_removal()
      guarded(function()
        -- Repeat every check after the network request / confirmation dialog.
        local current = fresh()
        if #current.blockers > 0 then
          finish(false, "Removal blocked after rechecking.\n" .. report(current, current.blockers)); return
        end
        if I.fingerprint(current) ~= fingerprint then
          finish(false, "Worktree state changed during the check. Nothing removed; review it again."); return
        end
        local backup
        if not current.tree.branch then backup = backup_detached(root, current.tree) end
        local head = (C.git(path, "rev-parse", "--verify", "HEAD"):gsub("\n$", ""))
        if head ~= current.tree.head then
          C.fail("HEAD changed before removal. Nothing removed; stop the writer and review again.")
        end
        -- Never force removal. Override configuration that could otherwise hide
        -- untracked files. Do not impose a timeout on destructive directory I/O.
        C.run(root, { "-c", "status.showUntrackedFiles=all", "worktree", "remove", "--", path },
          { timeout = false })
        local retained = 0
        for _, buf in ipairs(current.editor.buffers) do
          if api.nvim_buf_is_valid(buf) then
            if vim.bo[buf].modified or #fn.win_findbuf(buf) > 0
                or not pcall(api.nvim_buf_delete, buf, { force = false }) then
              retained = retained + 1
            end
          end
        end
        local message = "Removed worktree: " .. C.display(path)
            .. "\nBranch retained: " .. C.display(current.tree.branch or backup)
        if retained > 0 then message = message .. "\nSome editor buffers were retained; close them manually." end
        -- Hooks cannot convert a successful removal into a reported failure.
        local ok, err = pcall(api.nvim_exec_autocmds, "User", {
          pattern = "WorktreeRemoved",
          modeline = false,
          data = { path = path, branch = current.tree.branch, recovery_branch = backup },
        })
        if not ok then message = message .. "\nWorktreeRemoved hook failed: " .. tostring(err) end
        finish(true, message)
      end)
    end

    local function confirm(reasons)
      local phrase = "remove " .. label(original.tree)
      C.notify("Removal needs confirmation.\n" .. report(original, reasons)
        .. "\nLocal branches are kept. Stop agents/dev servers before continuing.", vim.log.levels.WARN)
      vim.ui.input({ prompt = "Type '" .. C.display(phrase) .. "' to remove this worktree: " }, function(answer)
        if answer ~= phrase then
          finish(false, "Removal cancelled."); return
        end
        commit_removal()
      end)
    end

    if #original.warnings > 0 then
      confirm(original.warnings); return
    end
    local u = original.upstream
    if not u or not u.remote_ref or u.remote_ref == "" then
      confirm({ "No remote branch could be verified." }); return
    end
    -- Only a live, exact match enables the no-dialog path. This does not fetch,
    -- merge, push, prune, or alter tracking refs. Failure falls back to confirmation.
    C.notify("Verifying " .. C.display(u.short or u.full) .. " before removal...")
    vim.system({ "git", "-C", root, "ls-remote", "--exit-code", "--refs", "--", u.remote, u.remote_ref },
      { timeout = 10000, env = { GIT_TERMINAL_PROMPT = "0" } }, function(result)
        vim.schedule(function()
          guarded(function()
            local found
            for sha, ref in (result.stdout or ""):gmatch("([0-9a-f]+)\t([^\n]+)") do
              if ref == u.remote_ref then found = sha end
            end
            if result.code == 0 and found == original.tree.head then
              commit_removal()
            else
              local reason = result.code == 0
                  and "Live upstream is not an exact match for this HEAD. The local branch will be retained."
                  or "Could not verify the live remote branch (offline, missing, authentication failure or timeout)."
              confirm({ reason })
            end
          end)
        end)
      end)
  end)
  return true
end

-- Git locks are a deliberate protection flag, not a process detector.
function M.toggle_lock(path, on_done)
  if C.busy then
    C.notify("Another worktree operation is running.", vim.log.levels.WARN); return
  end
  C.busy = true
  local function finish(ok, message)
    C.busy = false
    C.notify(message, ok and vim.log.levels.INFO or vim.log.levels.WARN)
    if on_done then vim.schedule(on_done) end
  end
  local ok, err = pcall(function()
    local root = C.context()
    local tree = C.find(root, path)
    if tree.main or tree.bare then C.fail("The main/bare worktree cannot be locked.") end
    local function change()
      local changed, why = pcall(function()
        local current = C.find(root, tree.path)
        if current.locked ~= tree.locked or current.lock_reason ~= tree.lock_reason then
          C.fail("Lock state changed. Review it again.")
        end
        if current.locked then
          C.git(root, "worktree", "unlock", "--", tree.path)
        else
          C.git(root, "worktree", "lock", "--reason", "Protected in Neovim worktree picker", "--", tree.path)
        end
      end)
      finish(changed, changed and ((tree.locked and "Unlocked: " or "Locked: ") .. C.display(tree.path)) or tostring(why))
    end
    if tree.locked then
      local phrase = "unlock " .. label(tree)
      C.notify("Lock reason: " .. C.display(tree.lock_reason or "") .. "\n" .. C.display(tree.path))
      vim.ui.input({ prompt = "Type '" .. C.display(phrase) .. "' to unlock: " }, function(answer)
        if answer ~= phrase then
          finish(false, "Unlock cancelled."); return
        end
        change()
      end)
    else
      change()
    end
  end)
  if not ok then finish(false, tostring(err)) end
end

return M
