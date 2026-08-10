if _G.MdAssistLoaded then
    return
end

_G.MdAssistLoaded = true

if vim.fn.has("nvim-0.7") == 0 then
    vim.cmd("command! MdAssist lua require('mdassist').toggle()")
else
    vim.api.nvim_create_user_command("MdAssist", function()
        require("mdassist").toggle()
    end, {})
end
