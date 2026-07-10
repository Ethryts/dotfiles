-- You can use this loaded variable to enable conditional parts of your plugin.
if _G.PyFixLoaded then
    return
end

_G.PyFixLoaded = true

-- Useful if you want your plugin to be compatible with older (<0.7) neovim versions
if vim.fn.has("nvim-0.7") == 0 then
    vim.cmd("command! PyFix lua require('pyfix').toggle()")
else
    vim.api.nvim_create_autocmd({ "BufEnter" }, {
        pattern = { '*.py' },
        callback = require("pyfix").toggle
    })
    -- vim.api.nvim_create_user_command("PyFix", function()
    --
    -- end, {})
end
