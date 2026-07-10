return {
    {
        'stevearc/oil.nvim',
        config = function(opts)
            require('oil').setup({
                keymaps = {
                    ["<C-t>"] = false
                },
                view_options = {
                    is_hidden_file = function(name, bufnr)
                        local m = name:match("^%.")
                        local k = name:match("%$py%.class$")

                        return k ~= nil or m ~= nil
                    end
                }
            })
            vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open Parent directory" })
            vim.keymap.set("n", "<leader>-", require("oil").toggle_float, { desc = "Open Parent directory" })
        end
    },
}
