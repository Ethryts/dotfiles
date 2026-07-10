-- lazy.nvim
return {
    "olimorris/codecompanion.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
    },
    enabled = false,
    opts = function()
        vim.cmd [[cab chat CodeCompanionChat]]
        return {
            display = {
                chat = {
                    window = {
                        width = 0.3,
                    }
                }
            },
            prompt_library = {
                ["Fix Notes"] = {
                    strategy = "chat",
                    description = "Fix the following notes to be more clear and concise.",
                    opts = {
                        default_memory = "domain",
                        auto_submit = true,
                    },
                    prompts = {
                        {
                            role = "system",
                            content =
                            "You are a autocorrect system for grammer and spelling. You transform rough notes into clear consise notes, without changing the meaning. Add filler words such as 'the' and 'a', and expand shorthand words, you can add punctuation such as commas and periods. You should not change the meaning of the notes, only make them more clear and consise. Formatting in markdown is allowed. putting items in a bulleted list is allowed. Clearly locate any follow up actions needed at the end of the notes as check boxes. Wrap the notes in a markdown code block. Do not include any other text outside of the code block."
                        },
                        {
                            role = "user",
                            content = "<user_prompt>Can you format these notes</user_prompt>"
                        }

                    }


                }
            },
            memory = {
                opts = {
                    chat = {
                        enabled = true,
                    }
                },
                scripting = {
                    description = "Python 2.7 development",
                    files = {
                        "~/.config/codecompanion/memories/python27.md",
                        "~/.config/codecompanion/memories/domain.md"
                    },
                },
                domain = {
                    description = "Domain specific knowledge",
                    files = {
                        "~/.config/codecompanion/memories/domain.md",
                    },
                }

                -- opts = { chat = true }
            },
            -- NOTE: The log_level is in `opts.opts`
            opts = {
                log_level = "DEBUG", -- or "TRACE"
            },
        }
    end
}
