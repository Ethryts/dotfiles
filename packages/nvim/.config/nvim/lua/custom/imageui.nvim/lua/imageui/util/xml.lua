local M = {}

---@param value any
---@return string
function M.escape(value)
  return tostring(value)
    :gsub('&', '&amp;')
    :gsub('<', '&lt;')
    :gsub('>', '&gt;')
    :gsub('"', '&quot;')
    :gsub("'", '&apos;')
end

return M
