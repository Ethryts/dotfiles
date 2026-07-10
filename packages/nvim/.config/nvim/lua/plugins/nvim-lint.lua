return {
  "mfussenegger/nvim-lint",
  enabled=false,
  opts = {
    linters_by_ft={
      javascript = {"eslint"},
      python = {"mypy"}
    }
  },
  config=function(_,opts)
    require('lint').linters_by_ft=opts.linters_by_ft
  end
}
