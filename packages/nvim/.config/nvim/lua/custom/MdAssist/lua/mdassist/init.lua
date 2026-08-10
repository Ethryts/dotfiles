local main = require("mdassist.main")
local config = require("mdassist.config")

local MdAssist = {}

function MdAssist.toggle()
    if _G.MdAssist.config == nil then
        _G.MdAssist.config = config.options
    end

    main.toggle("public_api_toggle")
end

function MdAssist.enable(scope)
    if _G.MdAssist.config == nil then
        _G.MdAssist.config = config.options
    end

    main.enable(scope or "public_api_enable")
end

function MdAssist.disable()
    main.disable("public_api_disable")
end

function MdAssist.setup(opts)
    _G.MdAssist.config = config.setup(opts)
    main.enable("setup")
end

_G.MdAssist = MdAssist

return _G.MdAssist
