local main = require("pyfix.main")
local config = require("pyfix.config")

local PyFix = {}

--- Toggle the plugin by calling the `enable`/`disable` methods respectively.
function PyFix.toggle()
    if _G.PyFix.config == nil then
        _G.PyFix.config = config.options
    end

    main.toggle("public_api_toggle")
end

--- Initializes the plugin, sets event listeners and internal state.
function PyFix.enable(scope)
    if _G.PyFix.config == nil then
        _G.PyFix.config = config.options
    end

    main.toggle(scope or "public_api_enable")
end

--- Disables the plugin, clear highlight groups and autocmds, closes side buffers and resets the internal state.
function PyFix.disable()
    main.toggle("public_api_disable")
end

-- setup PyFix options and merge them with user provided ones.
function PyFix.setup(opts)
    _G.PyFix.config = config.setup(opts)
    -- vim.print(opts)
    -- vim.api.nvim_create_autocmd({ "BufEnter" }, {
    --     pattern = { '*.py' },
    --     callback = main.toggle
    -- })

end

_G.PyFix = PyFix

return _G.PyFix
