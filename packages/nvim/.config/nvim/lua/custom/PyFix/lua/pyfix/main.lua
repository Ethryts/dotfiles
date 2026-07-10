local log = require("pyfix.util.log")
local state = require("pyfix.state")
local fixes = require("pyfix.fixes")

-- internal methods
local main = {}

-- Toggle the plugin by calling the `enable`/`disable` methods respectively.
--
---@param scope string: internal identifier for logging purposes.
---@private
function main.toggle(scope)
    if state.get_enabled(state) then
        log.debug(scope, "pyfix is now disabled!")

        return main.disable(scope)
    end

    log.debug(scope, "pyfix is now enabled!")

    main.enable(scope)
end

--- Initializes the plugin, sets event listeners and internal state.
---
--- @param scope string: internal identifier for logging purposes.
---@private
function main.enable(scope)
    if state.get_enabled(state) then
        log.debug(scope, "pyfix is already enabled")

        return
    end

    main.register_commands()


    state.set_enabled(state)


    -- saves the state globally to `_G.PyFix.state`
    state.save(state)
end

--- Disables the plugin for the given tab, clear highlight groups and autocmds, closes side buffers and resets the internal state.
---
--- @param scope string: internal identifier for logging purposes.
---@private
function main.disable(scope)
    if not state.get_enabled(state) then
        log.debug(scope, "pyfix is already disabled")

        return
    end

    state.set_disabled(state)

    -- saves the state globally to `_G.PyFix.state`
    state.save(state)
end

function main.command(args)
    local subcommand = args.fargs[1]
    if subcommand == nil then
        print("Usage: subcommand not found")
    end
    local handler = main.commands[subcommand]
    if handler then
        args.fargs = vim.list_slice(args.fargs,2)
        handler(args)
    else
        print("Unknown subcommand "..subcommand)
    end
end

main.commands = {}
main.commands.print = fixes.fix_prints
main.commands.raise = fixes.fix_raise
main.commands.bool = fixes.fix_bool
main.commands.retab = fixes.retab
main.commands.contains = fixes.fix_contains
main.commands.getValues = fixes.getValues
main.commands.getValue = fixes.getValue
main.commands.getText = fixes.getText

function main.register_commands()
    vim.api.nvim_create_user_command(
        "PyFix",
        main.command,
        {
            nargs = "*",
            range = true,
            complete = function(_, line)

                local matches = {}
                for name, cmd in pairs(main.commands) do
                    table.insert(matches, name)
                end
                return matches
            end
        }
    )
    -- vim.api.nvim_create_user_command(
    --     'PyRetab',
    --     fixes.retab,
    --     { nargs = 0, range = true }
    -- )
    --
    -- vim.api.nvim_create_user_command(
    --     "PyFix",
    --     fixes.prints,
    --     { nargs = 0 }
    -- )
    --
    -- vim.api.nvim_create_user_command(
    --     "Pyx",
    --     fixes.prints,
    --     { nargs = 0 }
    -- )
end

return main
