return {
    'nvim-lualine/lualine.nvim',
    lazy = false,
    priority = 51,
    opts = {
        options = {
            icons_enabled = true,
            theme = 'auto',
            always_show_tabline=false,
            component_separators = { left = '', right = '' },
            section_separators = { left = '', right = '' },
            disabled_filetypes = {
                winbar = { 'toggleterm', 'Avante', 'AvanteTodos', 'AvanteInput' },
            },
            ignore_focus = {},
            always_divide_middle = true,
            globalstatus = true,
        },
        tabline = {
            -- this is the line at the top that contains different tabs
            lualine_a = {
                {
                    'tabs',
                    max_length = vim.o.columns / 3,      -- Maximum width of tabs component.
                    mode = 2,
                    active = 'lualine_{section}_normal', -- Color for active tab.
                    inactive = 'lualine_{section}_inactive', -- Color for inactive tab.


                    --		  separator = {left="",right=""},      -- Determines what separator to use for the component.

                },'avante'

            },
            lualine_b = {},
            lualine_c = {},
            lualine_x = {},
            lualine_y = {},
            lualine_z = {
                -- 'windows' -- This is for the window line at the top right
            }
        },
        sections = {
            lualine_a = { 'mode' },
            lualine_b = { 'branch', 'diff', 'diagnostics' },
            lualine_c = { {
                'filename',
                file_status = true, -- Displays file status (readonly status, modified status)
                newfile_status = false, -- Display new file status (new file means no write after created)
                path = 3,           -- 0: Just the filename
                -- 1: Relative path
                -- 2: Absolute path
                -- 3: Absolute path, with tilde as the home directory
                shorting_target = 40, -- Shortens path to leave 40 spaces in the window
                -- for other components. (terrible name, any suggestions?)
                symbols = {
                    modified = '', -- Text to show when the file is modified.
                    readonly = '', -- Text to show when the file is non-modifiable or readonly.
                    unnamed = ' ', -- Text to show for unnamed buffers.
                    newfile = '', -- Text to show for new created file before first writting
                }
            },
            },
            lualine_x = { 'encoding', 'fileformat', 'filetype' },
            lualine_y = { 'progress' },
            lualine_z = { 'location' }
        },
        inactive_sections = {
            lualine_a = {},
            lualine_b = {},
            lualine_c = { {
                'filename',
                file_status = true, -- Displays file status (readonly status, modified status)
                newfile_status = false, -- Display new file status (new file means no write after created)
                path = 1,           -- 0: Just the filename
                -- 1: Relative path
                -- 2: Absolute path
                -- 3: Absolute path, with tilde as the home directory
                shorting_target = 40, -- Shortens path to leave 40 spaces in the window
                -- for other components. (terrible name, any suggestions?)
                symbols = {
                    modified = '', -- Text to show when the file is modified.
                    readonly = '', -- Text to show when the file is non-modifiable or readonly.
                    unnamed = '', -- Text to show for unnamed buffers.
                    newfile = '', -- Text to show for new created file before first writting
                }
            } },
            lualine_x = { 'location' },
            lualine_y = {},
            lualine_z = {}
        },
        winbar = {
            -- This is the line at the top of each window/pane
            lualine_a = {},
            lualine_b = { 'diff', 'diagnostics' },
            lualine_c = { {
                'filename',
                file_status = true, -- Displays file status (readonly status, modified status)
                newfile_status = false, -- Display new file status (new file means no write after created)
                path = 1,           -- 0: Just the filename
                -- 1: Relative path
                -- 2: Absolute path
                -- 3: Absolute path, with tilde as the home directory
                shorting_target = 40, -- Shortens path to leave 40 spaces in the window
                -- for other components. (terrible name, any suggestions?)
                symbols = {
                    modified = '', -- Text to show when the file is modified.
                    readonly = '', -- Text to show when the file is non-modifiable or readonly.
                    unnamed = '', -- Text to show for unnamed buffers.
                    newfile = '', -- Text to show for new created file before first writting
                }
            } },
            lualine_x = {},
            lualine_y = { 'progress' },
            lualine_z = { 'location' }
        },
        inactive_winbar = {
            lualine_a = {},
            lualine_b = {'diff', 'diagnostics'},
            lualine_c = { {
                'filename',
                file_status = true, -- Displays file status (readonly status, modified status)
                newfile_status = false, -- Display new file status (new file means no write after created)
                path = 1,           -- 0: Just the filename
                -- 1: Relative path
                -- 2: Absolute path
                -- 3: Absolute path, with tilde as the home directory
                shorting_target = 40, -- Shortens path to leave 40 spaces in the window
                -- for other components. (terrible name, any suggestions?)
                symbols = {
                    modified = '', -- Text to show when the file is modified.
                    readonly = '', -- Text to show when the file is non-modifiable or readonly.
                    unnamed = '', -- Text to show for unnamed buffers.
                    newfile = '', -- Text to show for new created file before first writting
                }
            } },
            lualine_x = {},
            lualine_y = {},
            lualine_z = { 'location' }
        },
        extensions = { 'toggleterm', 'oil' ,'avante'}
    },
    config = function(_, opts)
        vim.o.showtabline = 0
        require('lualine').setup(opts)
    end,


}
