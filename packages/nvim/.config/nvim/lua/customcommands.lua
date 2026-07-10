vim.cmd([[
	command -nargs=1 PyToDict :'<,'>s/^ *\(.*\) =\(.*\)/'\1': \2,
]])


vim.api.nvim_create_autocmd({ "VimEnter" }, {
  pattern = { '*' },
  callback = function()
    vim.api.nvim_command([[unmenu *]])
    vim.api.nvim_command [[anoremenu PopUp.Go\ to\ definition      <Cmd>lua vim.lsp.buf.definition()<CR>]]
    vim.api.nvim_command [[amenu     PopUp.Open\ in\ web\ browser  gx]]
    -- vim.api.nvim_command[[anoremenu PopUp.Inspect                 <Cmd>Inspect<CR>]]
    vim.api.nvim_command [[anoremenu PopUp.-1-                     <Nop>]]
    vim.api.nvim_command [[vnoremenu PopUp.Cut                     "+x]]
    vim.api.nvim_command [[vnoremenu PopUp.Copy                    "+y]]
    vim.api.nvim_command [[anoremenu PopUp.Paste                   "+gP]]
    vim.api.nvim_command [[vnoremenu PopUp.Paste                   "+P]]
    vim.api.nvim_command [[vnoremenu PopUp.Delete                  "_x]]
    vim.api.nvim_command [[nnoremenu PopUp.Select\ All             ggVG]]
    vim.api.nvim_command [[vnoremenu PopUp.Select\ All             gg0oG$]]
    vim.api.nvim_command [[inoremenu PopUp.Select\ All             <C-Home><C-O>VG]]
    vim.api.nvim_command [[anoremenu PopUp.-2-                     <Nop>]]
    -- vim.api.nvim_command([[aunmenu PopUp.How-to\ disable\ mouse]])
    -- vim.api.nvim_command([[menu PopUp.Toggle\ \Breakpoint <cmd>:lua require('dap').toggle_breakpoint()<CR>]])
    vim.api.nvim_command([[menu PopUp.-2- <Nop>]])
    -- vim.api.nvim_command([[menu PopUp.Start\ \Compiler <cmd>:CompilerOpen<CR>]])
    -- vim.api.nvim_command([[menu PopUp.Start\ \Debugger <cmd>:DapContinue<CR>]])
    -- vim.api.nvim_command([[menu PopUp.Run\ \Test <cmd>:Neotest run<CR>]])
    -- vim.api.nvim_command([[menu PopUp.Definition  <cmd>lua vim.lsp.buf.definition()<CR>]])
    -- vim.api.nvim_command([[menu PopUp.Back <c-t>]])
  end
})


-- replace single tabs with 4 tabs
vim.api.nvim_create_user_command(
  'CopyAll',
  function(opts)
    local save_cursor = vim.fn.getcurpos()
    vim.cmd('normal! ggVG"+y')
    vim.fn.setpos('.', save_cursor)
  end,
  { nargs = 0 }
)

vim.api.nvim_create_user_command(
  "W",
  function(opts)
    vim.cmd("w")
    vim.cmd('CopyAll')
  end,
  { nargs = 0 }
)


vim.api.nvim_create_user_command(
  "Scratch",
  function(opts)
    local file_type = ".py"
    if opts.args then
      file_type = opts.args
      if not string.find(file_type, ".") then
        file_type = "." .. file_type
      end
    end
    vim.cmd('edit ' .. '~/Code/Scratch/Scratch-' .. os.date("%Y%m%d%H%M%S") .. file_type)
    vim.cmd('write ++p')
  end,
  { nargs = '?' }

)
