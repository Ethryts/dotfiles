local M = {}

---@return string
local function version_string()
  local version = vim.version()
  return ('%d.%d.%d%s'):format(
    version.major,
    version.minor,
    version.patch,
    version.prerelease and '-dev' or ''
  )
end

---@return boolean, string?
function M.available()
  if not (vim.ui and vim.ui.img) then
    return false,
      ('vim.ui.img is unavailable in Neovim %s; use a build exposing the experimental API (currently 0.13 nightly)'):format(
        version_string()
      )
  end
  for _, method in ipairs({ 'set', 'get', 'del' }) do
    if type(vim.ui.img[method]) ~= 'function' then
      return false, ('vim.ui.img.%s is unavailable in Neovim %s'):format(method, version_string())
    end
  end
  return true
end

---@param opts? table
---@return boolean, string?
function M.supported(opts)
  local available, reason = M.available()
  if not available then
    return false, reason
  end
  -- This helper is private in the initial API. Keep it optional and protected.
  if type(vim.ui.img._supported) == 'function' then
    local ok, supported, message = pcall(vim.ui.img._supported, opts or { timeout = 500 })
    if ok then
      return supported, message
    end
    return false, tostring(supported)
  end
  return true, 'terminal capability has not been probed'
end

---@param bytes string
---@param opts table
---@return integer
function M.set(bytes, opts)
  return vim.ui.img.set(bytes, opts)
end

---@param id integer
---@param opts table
function M.update(id, opts)
  vim.ui.img.set(id, opts)
end

---@param id integer
---@return boolean
function M.delete(id)
  return vim.ui.img.del(id)
end

---@param id integer
---@return table?
function M.get(id)
  return vim.ui.img.get(id)
end

return M
