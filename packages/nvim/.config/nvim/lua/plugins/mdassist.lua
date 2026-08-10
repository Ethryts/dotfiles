return {
    dir = vim.fn.stdpath("config") .. "/lua/custom/MdAssist/",
    enabled = true,
    name = "MdAssist",
    ft = "markdown",
    dev = true,
    opts = {
        header_indent = true,
        list_continue = true,
    },
}
