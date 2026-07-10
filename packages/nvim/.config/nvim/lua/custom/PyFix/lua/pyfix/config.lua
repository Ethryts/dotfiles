local log = require("pyfix.util.log")

local PyFix = {}

--- PyFix configuration with its default values.
---
---@type table
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
PyFix.options = {
    -- Prints useful logs about what event are triggered, and reasons actions are executed.
    debug = false,
}

---@private
local defaults = vim.deepcopy(PyFix.options)

--- Defaults PyFix options by merging user provided options with the default plugin values.
---
---@param options table Module config table. See |PyFix.options|.
---
---@private
function PyFix.defaults(options)
    PyFix.options =
        vim.deepcopy(vim.tbl_deep_extend("keep", options or {}, defaults or {}))

    -- let your user know that they provided a wrong value, this is reported when your plugin is executed.
    assert(
        type(PyFix.options.debug) == "boolean",
        "`debug` must be a boolean (`true` or `false`)."
    )

    return PyFix.options
end

--- Define your pyfix setup.
---
---@param options table Module config table. See |PyFix.options|.
---
---@usage `require("pyfix").setup()` (add `{}` with your |PyFix.options| table)
function PyFix.setup(options)
    PyFix.options = PyFix.defaults(options or {})


    log.warn_deprecation(PyFix.options)

    return PyFix.options
end

return PyFix
