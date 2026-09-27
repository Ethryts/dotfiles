local M = {
  sessions = {},
  metadata = {},
  active_root = nil,
}

function M.get(root)
  return M.sessions[root]
end

function M.set(root, session, token, opts)
  opts = opts or {}
  M.sessions[root] = session
  M.metadata[root] = {
    token = token,
    dirty = opts.dirty == true,
  }
  M.active_root = root
  return session
end

function M.token(root)
  local metadata = M.metadata[root]
  return metadata and metadata.token or nil
end

function M.is_dirty(root)
  local metadata = M.metadata[root]
  return metadata and metadata.dirty == true or false
end

function M.mark_dirty(root)
  if not M.sessions[root] then
    return false
  end
  M.metadata[root] = M.metadata[root] or {}
  M.metadata[root].dirty = true
  return true
end

function M.mark_clean(root, token)
  if not M.sessions[root] then
    return false
  end
  M.metadata[root] = M.metadata[root] or {}
  M.metadata[root].token = token
  M.metadata[root].dirty = false
  return true
end

function M.each(callback)
  for root, session in pairs(M.sessions) do
    callback(root, session, M.metadata[root] or {})
  end
end

function M.activate(root)
  if root then
    M.active_root = root
  end
end

function M.remove(root)
  M.sessions[root] = nil
  M.metadata[root] = nil
  if M.active_root == root then
    M.active_root = nil
  end
end

function M.reset()
  M.sessions = {}
  M.metadata = {}
  M.active_root = nil
end

return M
