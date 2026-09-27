local M = {}

---@param path string
---@return string
function M.ensure_dir(path)
  vim.fn.mkdir(path, 'p')
  return path
end

---@param path string
---@return string
function M.read_binary(path)
  local data = vim.fn.readblob(path)
  if type(data) == 'string' then
    return data
  end
  -- Compatibility with versions where readblob() is represented as a Blob/List.
  return string.char(unpack(vim.fn.blob2list(data)))
end

---@param path string
---@param data string
function M.write_binary(path, data)
  M.ensure_dir(vim.fs.dirname(path))
  vim.fn.writefile(data, path)
end

---@param path string
---@param text string
function M.write_text(path, text)
  M.ensure_dir(vim.fs.dirname(path))
  local lines = vim.split(text, '\n', { plain = true })
  vim.fn.writefile(lines, path)
end

---@param source string
---@param destination string
---@param callback? fun(err?: string)
function M.copy(source, destination, callback)
  M.ensure_dir(vim.fs.dirname(destination))
  vim.uv.fs_copyfile(source, destination, function(err)
    if callback then
      vim.schedule(function()
        callback(err)
      end)
    end
  end)
end

---@param path string
---@return boolean
function M.exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

return M
