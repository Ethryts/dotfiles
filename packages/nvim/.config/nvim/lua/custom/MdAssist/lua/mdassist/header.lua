local M = {}

---@param line string
---@return string? leading
---@return string? hashes
---@return string? spacing
---@return string? rest
local function parse_header(line)
    local leading, rest = line:match("^(%s*)(.*)$")
    if not leading or #leading > 3 then
        return nil
    end

    local hashes, spacing, title = rest:match("^(#+)(%s+)(.*)$")
    if not hashes or #hashes < 1 or #hashes > 6 then
        return nil
    end

    return leading, hashes, spacing, title
end

---@param line string
---@param delta integer
---@return string?
local function adjust_header_line(line, delta)
    local leading, hashes, spacing, rest = parse_header(line)
    if not leading then
        return nil
    end

    local new_depth = math.max(1, math.min(6, #hashes + delta))
    return leading .. string.rep("#", new_depth) .. spacing .. rest
end

---@param bufnr integer
---@param start_line integer
---@param end_line integer
---@param delta integer
local function adjust_range(bufnr, start_line, end_line, delta)
    if delta == 0 then
        return
    end

    local direction = delta > 0 and 1 or -1
    local steps = math.abs(delta)

    for _ = 1, steps do
        for line_nr = start_line, end_line do
            local line = vim.api.nvim_buf_get_lines(bufnr, line_nr - 1, line_nr, false)[1] or ""
            local adjusted = adjust_header_line(line, direction)

            if adjusted then
                vim.api.nvim_buf_set_lines(bufnr, line_nr - 1, line_nr, false, { adjusted })
            else
                vim.cmd(string.format(
                    "%d,%d%s",
                    line_nr,
                    line_nr,
                    direction > 0 and "normal! >>" or "normal! <<"
                ))
            end
        end
    end
end

---@param delta integer
function M.indent(delta)
    local bufnr = vim.api.nvim_get_current_buf()
    local line_nr = vim.api.nvim_win_get_cursor(0)[1]
    local count = math.max(1, vim.v.count1)

    adjust_range(bufnr, line_nr, line_nr, delta * count)
end

---@param delta integer
function M.visual_indent(delta)
    local bufnr = vim.api.nvim_get_current_buf()
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    local count = math.max(1, vim.v.count1)

    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    adjust_range(bufnr, start_line, end_line, delta * count)
    vim.cmd("normal! gv")
end

return M
