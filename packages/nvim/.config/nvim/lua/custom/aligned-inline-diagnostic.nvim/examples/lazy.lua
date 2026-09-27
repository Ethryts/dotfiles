return {
  dir = vim.fn.expand("~/src/aligned-inline-diagnostic.nvim"),
  name = "aligned-inline-diagnostic.nvim",
  main = "aligned-inline-diagnostic",
  event = "VeryLazy",
  opts = {
    alignment = {
      mode = "block",
      min_col = 40,
      max_gap = 5,
    },
    preview = {
      max_width = 48,
      width_mode = "block",
      count_align = "right",
    },
    hover = {
      delay_ms = 180,
      sticky = true,
      input_mode = "both", -- "cursor", "mouse", or "both"
      mouse_scope = "diagnostic",
      cursor_scope = "line", -- use "diagnostic" for exact range hits
      group_by = "line", -- "line", "range", or "block"
      match_preview_width = true,
      preferred_width = 52,
      max_width = 68,
      max_height = 16,
      placement = {
        order = { "right", "below", "above" },
        edge_margin = 1,
        avoid_source = true,
        preserve_anchor = true,
      },
    },
    appearance = {
      preview_blend = 0.12,
      hover_blend = 0.12,
      inactive_blend = 0.55,
    },
  },
}
