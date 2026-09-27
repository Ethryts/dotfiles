local M = {}

---@return table
function M.new()
  local next_id = 0
  local state = {}
  local calls = {}

  local backend = {}

  function backend.available()
    return true
  end

  function backend.supported()
    return true
  end

  function backend.set(bytes, opts)
    next_id = next_id + 1
    state[next_id] = { bytes = bytes, opts = vim.deepcopy(opts) }
    calls[#calls + 1] = { method = 'set', id = next_id, opts = vim.deepcopy(opts) }
    return next_id
  end

  function backend.update(id, opts)
    assert(state[id], 'unknown fake image id')
    state[id].opts = vim.tbl_extend('force', state[id].opts, vim.deepcopy(opts))
    calls[#calls + 1] = { method = 'update', id = id, opts = vim.deepcopy(opts) }
  end

  function backend.delete(id)
    local found = state[id] ~= nil
    state[id] = nil
    calls[#calls + 1] = { method = 'delete', id = id }
    return found
  end

  function backend.get(id)
    return state[id] and vim.deepcopy(state[id].opts) or nil
  end

  function backend._state()
    return state
  end

  function backend._calls()
    return calls
  end

  return backend
end

return M
