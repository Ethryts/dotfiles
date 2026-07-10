local ts = vim.treesitter
local parsers = require("nvim-treesitter.parsers")


local fixes = {}

function FixTabs()
    vim.cmd([[%s/^\s*/&&&&/g]])
    vim.cmd([[noh]])
end

function fixes.retab(opts)
    local line1 = opts.line1
    local line2 = opts.line2
    if line1 and line2 then
        vim.cmd("silent! " .. line1 .. "," .. line2 .. [[s/^\s*/&&&&/g]])
        vim.cmd([[noh]])
    else
        FixTabs()
    end
end

function setup_ts()
    local bufnr = vim.api.nvim_get_current_buf()
    local lang = parsers.get_buf_lang(bufnr)
    local parser = parsers.get_parser(bufnr, lang)
    local tree = parser:parse()[1]
    local root = tree:root()
    return bufnr, lang, parser, tree, root
end

function fixes.fix_prints(opts)
    bufnr, lang, parser, tree, root = setup_ts()
    local query = ts.query.parse("python",
        [[(expression_statement
            (identifier) @identifier
            (_) @print_content
            (#eq? @identifier "print")
        )]]
    )

    local edits = {}
    for id, node, metadata in query:iter_captures(root, bufnr, 0, -1) do
        local name = query.captures[id]
        if name == "print_content" then
            local msg                                    = vim.treesitter.get_node_text(node, bufnr)
            local start_row, start_col, end_row, end_col = node:parent():range()
            local new_text                               = "print(" .. msg .. ")"
            edits[#edits + 1]                            = { bufnr, start_row, start_col, end_row, end_col, { new_text } }
            vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, { new_text })
        end
    end
    -- vim.print("Fixing '".. #edits .."' Raise statments")
    -- for args in edits do
    --     -- local bufnr, start_row, start_col, end_row, end_col, new_text = unpack()
    --     vim.api.nvim_buf_set_text(unpack(args) )
    -- end
end

function fixes.bool(opts)
    vim.cmd([[silent! s/true/True/g]])
    vim.cmd([[silent! s/false/False/g]])
    vim.print("Replaced true/false with True/False")
end

function fixes.fix_contains(opts)
    bufnr, lang, parser, tree, root = setup_ts()
    local query = ts.query.parse("python",
        [[(call
              (attribute
                object: (identifier) @obj (#eq? @obj "Rstring")
                attribute: (identifier) @obj_f (#eq? @obj_f "contains")
                )
               arguments: (argument_list
                            (_) @arg1
                            (_) @arg2
                            )
          ) @func
        ]]
    )
    local edits = {}
    for _, match in query:iter_matches(root, bufnr, 0, -1) do
        local captures = {}

        for id, node in pairs(match) do
            local name = query.captures[id]
            captures[name] = node[1]
        end

        local new_text, start_row, start_col, end_row, end_col
        if captures["func"]:parent():type() == "not_operator" then
            start_row, start_col, end_row, end_col = captures["func"]:parent():range()
            new_text = "" ..
            ts.get_node_text(captures["arg2"], bufnr) .. " not in " .. ts.get_node_text(captures["arg1"], bufnr)
        else
            start_row, start_col, end_row, end_col = captures["func"]:range()
            new_text = "" .. ts.get_node_text(captures["arg2"], bufnr) ..
            " in " .. ts.get_node_text(captures["arg1"], bufnr)
        end

        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, { new_text })
        -- edits[#edits+1] = {bufnr, start_row, start_col, end_row, end_col, {new_text}}
    end
    -- vim.print("Fixing '".. #edits .."' contain statements")
    -- for _, args in pairs(edits) do
    --     local bufnr, start_row, start_col, end_row, end_col, new_text = unpack(args)
    --     -- vim.api.nvim_buf_set_text(unpack(args))
    --     vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, new_text )
    -- end
end

function fixes.fix_raise(opts)
    bufnr, lang, parser, tree, root = setup_ts()
    local query = ts.query.parse("python",
        [[(raise_statement
          (expression_list
            (identifier) @error
            (_) @msg
          )
        )]]
    )
    local raise_edits = {}
    for id, node, metadata in query:iter_captures(root, bufnr, 0, -1) do
        local name = query.captures[id]
        raise_edits[name] = node
        if raise_edits["error"] and raise_edits["msg"] then
            local error = vim.treesitter.get_node_text(raise_edits["error"], bufnr)
            local msg = vim.treesitter.get_node_text(raise_edits["msg"], bufnr)
            local raise_node = raise_edits["error"]:parent():parent()
            local start_row, start_col, end_row, end_col = raise_node:range()

            local new_text = "raise " .. error .. "(" .. msg .. ")"
            vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, { new_text })
            raise_edits = {}
        end
    end
end

function fixes.fix_all(opts)
    fixes.fix_raise(opts)
    fixes.fix_prints(opts)
    fixes.retab(opts)
end

function short_hand(fn1, fn2, short)
    bufnr, lang, parser, tree, root = setup_ts()

    local query = ts.query.parse("python", [[
    (
        (call
            function: (attribute
                object: (call
                    function: (attribute
                    object: (_) @base
                    attribute: (identifier) @first_method)
                    (#eq? @first_method "]] .. fn1 .. [[")
                    arguments: (argument_list ) @first_args
                )
                attribute: (identifier) @second_method
                (#eq? @second_method "]] .. fn2 .. [[")
            )
            arguments: (argument_list) @second_args
        ) @all
    )]]
    )
    for _, match in query:iter_matches(root, bufnr, 0, -1) do
        local captures = {}
        for id, node in pairs(match) do
            local name = query.captures[id]
            captures[name] = node[1]
        end
        local new_text, start_row, start_col, end_row
        local second_end_col

        start_row, start_col, end_row = captures["first_method"]:range()
        _, _, _, second_end_col       = captures["second_args"]:range()
        vim.print(ts.get_node_text(captures['first_args'], bufnr))
        new_text = short .. ts.get_node_text(captures['first_args'], bufnr)
        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, second_end_col, { new_text })
    end
end

function fixes.getValue(opts)
    short_hand("getField", "getValue", "getFieldValue")
end

function fixes.getText(opts)
    short_hand("getField", "getText", "getFieldText")
end

function fixes.getValues(opts)
    short_hand("getField", "getValues", "getFieldValues")
end

return fixes
