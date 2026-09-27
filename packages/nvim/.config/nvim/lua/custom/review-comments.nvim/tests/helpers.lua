local M = {}

function M.fail(message)
  error(message, 2)
end

function M.equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    M.fail(
      string.format(
        '%s\nexpected: %s\nactual:   %s',
        message,
        vim.inspect(expected),
        vim.inspect(actual)
      )
    )
  end
end

function M.truthy(value, message)
  if not value then
    M.fail(message)
  end
end

function M.write_file(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  M.equal(vim.fn.writefile(lines, path), 0, 'could not write ' .. path)
end

function M.read_file(path)
  local file = assert(io.open(path, 'rb'))
  local content = file:read('*a')
  file:close()
  return content
end

function M.read_json(path)
  return vim.json.decode(M.read_file(path))
end

function M.git(repo, args)
  local command = { 'git', '-C', repo }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    M.fail('git failed: ' .. (result.stderr or ''))
  end
  return vim.trim(result.stdout or '')
end

function M.repo()
  local repo = vim.fn.tempname()
  vim.fn.mkdir(repo, 'p')
  M.git(repo, { 'init', '--quiet' })
  M.git(repo, { 'config', 'user.email', 'review-comments@example.invalid' })
  M.git(repo, { 'config', 'user.name', 'Review Comments Tests' })
  return repo
end

function M.run(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  pcall(function()
    require('review_comments')._reset_for_tests()
  end)
  if not ok then
    io.stderr:write(string.format('%s failed:\n%s\n', name, err))
    vim.cmd('cquit 1')
  else
    print(name .. ' passed')
    vim.cmd('quitall!')
  end
end

return M
