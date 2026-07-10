return {
    { 'folke/tokyonight.nvim',    lazy = true },
    {
        'navarasu/onedark.nvim',
        priority = 1000,
        config = function()
            vim.cmd([[colorscheme onedark]])
        end
    },
    { 'catppuccin/nvim',          lazy = true },
    { 'EdenEast/nightfox.nvim',   lazy = true },
    { 'ellisonleao/gruvbox.nvim', lazy = true },
}
