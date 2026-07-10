return {
  {
    'echasnovski/mini.nvim',
    event = "VeryLazy",
    opts = {
      ['mini.surround'] = {},
      ['mini.ai'] = {},
      ['mini.pairs'] = {},
      ['mini.comment'] = {},
    },
    config = function(_, opts)
      for plugin, plugin_opts in pairs(opts) do
        require(plugin).setup(plugin_opts)
      end
    end
  }
}
