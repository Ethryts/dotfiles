local M = {}

local BULLET_BLANK = "^(%s*)([-*+])%s*$"
local BULLET_LINE = "^(%s*)([-*+])%s+(.*)$"
local NUMBERED_BLANK = "^(%s*)(%d+)([.)])%s*$"
local NUMBERED_LINE = "^(%s*)(%d+)([.)])%s+(.*)$"
local BLOCKQUOTE_BLANK = "^(%s*)(>+)%s*$"
local BLOCKQUOTE_LINE = "^(%s*)(>+)%s*(.*)$"

---@param indent string
---@param bullet string
---@return string
local function bullet_prefix(indent, bullet)
    return indent .. bullet .. " "
end

---@param indent string
---@param number string
---@param delimiter string
---@return string
local function numbered_prefix(indent, number, delimiter)
    return indent .. tostring(tonumber(number) + 1) .. delimiter .. " "
end

---@param indent string
---@param markers string
---@return string
local function blockquote_prefix(indent, markers)
    return indent .. markers .. " "
end

---@param line string
---@return string? prefix
---@return boolean? blank_marker
local function list_prefix(line)
    local indent, bullet = line:match(BULLET_BLANK)
    if indent and bullet then
        return bullet_prefix(indent, bullet), true
    end

    local content
    indent, bullet, content = line:match(BULLET_LINE)
    if indent and bullet and content ~= nil then
        return bullet_prefix(indent, bullet), false
    end

    local number, delimiter
    indent, number, delimiter = line:match(NUMBERED_BLANK)
    if indent and number and delimiter then
        return numbered_prefix(indent, number, delimiter), true
    end

    indent, number, delimiter, content = line:match(NUMBERED_LINE)
    if indent and number and delimiter and content ~= nil then
        return numbered_prefix(indent, number, delimiter), false
    end

    local markers
    indent, markers = line:match(BLOCKQUOTE_BLANK)
    if indent and markers then
        return blockquote_prefix(indent, markers), true
    end

    indent, markers, content = line:match(BLOCKQUOTE_LINE)
    if indent and markers and content ~= nil then
        return blockquote_prefix(indent, markers), false
    end

    return nil, nil
end

---@return boolean handled
function M.on_enter()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local line = vim.api.nvim_get_current_line()
    local prefix, blank_marker = list_prefix(line)

    if not prefix then
        return false
    end

    if blank_marker then
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, { "" })
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        return true
    end

    local before = line:sub(1, col)
    local after = line:sub(col + 1)

    if after == "" then
        vim.api.nvim_buf_set_lines(0, row, row, false, { prefix })
        vim.api.nvim_win_set_cursor(0, { row + 1, #prefix })
        return true
    end

    vim.api.nvim_buf_set_lines(0, row - 1, row, false, { before })
    vim.api.nvim_buf_set_lines(0, row, row, false, { prefix .. after })
    vim.api.nvim_win_set_cursor(0, { row + 1, #prefix })
    return true
end

return M
