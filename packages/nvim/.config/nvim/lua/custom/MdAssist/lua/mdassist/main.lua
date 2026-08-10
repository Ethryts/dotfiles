local log = require("mdassist.util.log")
local state = require("mdassist.state")
local header = require("mdassist.header")
local list = require("mdassist.list")

local main = {}

local AUGROUP = "MdAssist"
local attached_buffers = {}

local function get_config()
    return _G.MdAssist and _G.MdAssist.config
end

local function map_opts(bufnr)
    return { buffer = bufnr, silent = true }
end

---@param bufnr integer
function main.attach_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    if vim.bo[bufnr].filetype ~= "markdown" then
        return
    end

    local config = get_config()
    if not config or not state.get_enabled(state) then
        return
    end

    main.detach_buffer(bufnr)

    local opts = map_opts(bufnr)

    if config.header_indent then
        vim.keymap.set("n", ">>", function()
            header.indent(1)
        end, opts)
        vim.keymap.set("n", "<<", function()
            header.indent(-1)
        end, opts)
        vim.keymap.set("v", ">", function()
            header.visual_indent(1)
        end, opts)
        vim.keymap.set("v", "<", function()
            header.visual_indent(-1)
        end, opts)
    end

    if config.list_continue then
        vim.keymap.set("i", "<CR>", function()
            if list.on_enter() then
                return
            end

            return vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes("<CR>", true, false, true),
                "n",
                true
            )
        end, opts)
    end

    attached_buffers[bufnr] = true
    log.debug("attach_buffer", "attached maps to buffer %d", bufnr)
end

---@param bufnr integer
function main.detach_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        attached_buffers[bufnr] = nil
        return
    end

    local opts = map_opts(bufnr)
    pcall(vim.keymap.del, "n", ">>", opts)
    pcall(vim.keymap.del, "n", "<<", opts)
    pcall(vim.keymap.del, "v", ">", opts)
    pcall(vim.keymap.del, "v", "<", opts)
    pcall(vim.keymap.del, "i", "<CR>", opts)

    attached_buffers[bufnr] = nil
    log.debug("detach_buffer", "detached maps from buffer %d", bufnr)
end

local function attach_existing_buffers()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "markdown" then
            main.attach_buffer(bufnr)
        end
    end
end

local function detach_all_buffers()
    for bufnr in pairs(attached_buffers) do
        main.detach_buffer(bufnr)
    end
end

---@param scope string
function main.enable(scope)
    if state.get_enabled(state) then
        log.debug(scope, "mdassist is already enabled")
        return
    end

    state.set_enabled(state)
    state.save(state)

    local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })

    vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "markdown",
        callback = function(args)
            main.attach_buffer(args.buf)
        end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function(args)
            attached_buffers[args.buf] = nil
        end,
    })

    attach_existing_buffers()
    log.debug(scope, "mdassist is now enabled!")
end

---@param scope string
function main.disable(scope)
    if not state.get_enabled(state) then
        log.debug(scope, "mdassist is already disabled")
        return
    end

    vim.api.nvim_clear_autocmds({ group = AUGROUP })
    detach_all_buffers()

    state.set_disabled(state)
    state.save(state)

    log.debug(scope, "mdassist is now disabled!")
end

---@param scope string
function main.toggle(scope)
    if state.get_enabled(state) then
        log.debug(scope, "mdassist is now disabled!")
        return main.disable(scope)
    end

    log.debug(scope, "mdassist is now enabled!")
    main.enable(scope)
end

return main
