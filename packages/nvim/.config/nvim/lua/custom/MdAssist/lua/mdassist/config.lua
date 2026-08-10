local log = require("mdassist.util.log")

local MdAssist = {}

--- MdAssist configuration with its default values.
---
---@type table
MdAssist.options = {
    -- Deepen/shallow ATX headers when indenting with >> and <<.
    header_indent = true,
    -- Continue list and blockquote markers on Enter in insert mode.
    list_continue = true,
    -- Prints useful logs about what events are triggered.
    debug = false,
}

---@private
local defaults = vim.deepcopy(MdAssist.options)

---@param options table Module config table. See |MdAssist.options|.
---@private
function MdAssist.defaults(options)
    MdAssist.options =
        vim.deepcopy(vim.tbl_deep_extend("keep", options or {}, defaults or {}))

    assert(
        type(MdAssist.options.header_indent) == "boolean",
        "`header_indent` must be a boolean (`true` or `false`)."
    )
    assert(
        type(MdAssist.options.list_continue) == "boolean",
        "`list_continue` must be a boolean (`true` or `false`)."
    )
    assert(
        type(MdAssist.options.debug) == "boolean",
        "`debug` must be a boolean (`true` or `false`)."
    )

    return MdAssist.options
end

---@param options table Module config table. See |MdAssist.options|.
function MdAssist.setup(options)
    MdAssist.options = MdAssist.defaults(options or {})

    log.warn_deprecation(MdAssist.options)

    return MdAssist.options
end

return MdAssist
