# aligned-inline-diagnostic.nvim

Aligned, always-visible diagnostic previews with an expanded hover float for
Neovim.

Nearby previews share a display column and, by default, a width. Counts occupy
a stable right-hand column, so a cluster reads like a compact table instead of
ragged end-of-line text. Resting on a diagnostic expands it into a message-first
float that wraps beside the code when possible and moves below or above when a
right-hand float would cover the diagnosed expression.

## Behavior

- Block, whole-buffer, or unaligned preview placement
- Compact, block-width previews with right-aligned `+N` counts
- Distinct default glyphs for errors, warnings, information, and hints
- Message-first expansion with dim, deduplicated source/rule metadata
- Balanced wrapping, stable glyph lanes, and highlighted quoted identifiers
- Source-safe `right`, `below`, then `above` placement within the current split
- Active diagnostic-range highlighting and dimmed inactive previews
- Range-aware cursor hover and optional mouse hover
- Pale severity palettes, automatic contrast, and role-level highlight overrides
- No runtime dependencies or virtual lines

## Requirements

- Neovim 0.10+
- A font containing the configured glyphs. The default rounded caps use
  Nerd Font/Powerline glyphs; set `icons.left/right = ""` if needed.

## Installation

```lua
-- lazy.nvim
{
  "your-name/aligned-inline-diagnostic.nvim",
  main = "aligned-inline-diagnostic",
  event = "VeryLazy",
  opts = {},
}
```

For a local checkout, replace the repository name with:

```lua
dir = vim.fn.expand("~/src/aligned-inline-diagnostic.nvim")
```

## Configuration

These are the defaults:

```lua
require("aligned-inline-diagnostic").setup({
  enabled = true,
  disable_default_virtual_text = true,
  throttle_ms = 20,
  priority = 2048,
  disabled_filetypes = {},

  diagnostics = {
    severity = nil, -- severity name, number, list, or nil for every severity
    sources = nil, -- source allow-list
    exclude_sources = {},
    namespaces = nil, -- namespace-ID allow-list
    -- function(diagnostic, bufnr) -> boolean
    filter = nil,
    deduplicate = false,
  },

  alignment = {
    mode = "block", -- "block", "buffer", or "none"
    min_col = 36,
    padding = 3,
    include_range_width = true,
    max_range_lines = 50,
    max_gap = 4,
    max_col = nil,
  },

  preview = {
    max_width = 52,
    ellipsis = "…",
    show_count = true,
    width_mode = "block", -- "fit", "block", or "fixed"
    count_align = "right", -- "inline" or "right"
    padding_left = 1,
    padding_right = 1,
    inactive = {
      enabled = true,
      scope = "block", -- "block" or "buffer"
    },
    -- function(diagnostic, context) -> string|nil
    format = nil,
    -- function(extra_count, total_count) -> string|nil
    count_format = nil,
  },

  hover = {
    enabled = true,
    delay_ms = nil, -- nil reads 'updatetime'; a number is plugin-local
    sticky = true,
    input_mode = "both", -- "cursor", "mouse", or "both"
    use_mouse = false, -- deprecated compatibility option
    mouse_scope = "diagnostic", -- "diagnostic", "code", "preview", or "line"
    cursor_scope = "line", -- "line" or "diagnostic"
    group_by = "line", -- "line", "range", or "block"
    hide_preview = true,
    border = "none",
    min_width = 30,
    max_width = 72,
    preferred_width = 54,
    width_mode = "preferred", -- "fit", "preferred", or "fixed"
    match_preview_width = true,
    max_height = 18,
    row_offset = 0,
    col_offset = 0,
    zindex = 60,
    winblend = 0,

    show_source = true,
    show_code = true,
    show_severity = false,
    deduplicate_source = true,
    message_first = true,
    metadata_position = "below", -- "below", "inline", or "hidden"
    metadata_separator = " · ",
    item_spacing = 0,
    padding_left = 1,
    padding_right = 1,
    wrap_mode = "balanced", -- "balanced" or "greedy"
    highlight_tokens = true,
    cap_style = "ends", -- "ends", "all", or "none"

    placement = {
      order = { "right", "below", "above" },
      gap = 0,
      edge_margin = 1,
      avoid_source = true,
      preserve_anchor = true,
    },

    dim_inactive = true,
    highlight_target = "all", -- false, "primary", or "all"
    show_related = true,

    -- function(diagnostic) -> string|string[]|nil
    details = nil,
    -- function(diagnostic, context) -> string|string[]|nil
    format_message = nil,
    format_metadata = nil,
  },

  appearance = {
    preview_blend = 0.14,
    hover_blend = 0.12,
    preview_tints = {
      error = "DiagnosticError",
      warn = "DiagnosticWarn",
      info = "DiagnosticInfo",
      hint = "DiagnosticHint",
    },
    hover_tints = {
      error = "DiagnosticError",
      warn = "DiagnosticWarn",
      info = "DiagnosticInfo",
      hint = "DiagnosticHint",
    },
    preview_backgrounds = {},
    hover_backgrounds = {},
    hover_tint = nil,
    hover_background = nil,
    inactive_blend = 0.55,
    active_blend = 0.10,
    metadata_blend = 0.58,
    ensure_contrast = true,
    minimum_contrast = 3.0,
    edge_underlay = {
      combine = true,
      normal = "Normal",
      colorcolumn = "ColorColumn",
      overflow = "PastColorColumn",
      overflow_column = nil, -- infer the greatest configured colorcolumn
      respect_colorcolumn = true,
      resolve = nil,
    },
  },

  -- Applied last. Strings are treated as highlight links.
  highlights = {},

  icons = {
    error = "●",
    warn = "▲",
    info = "◆",
    hint = "○",
    branch = "├",
    continuation = "│",
    last = "╰",
    related = "↳",
    left = "",
    right = "",
  },
})
```

### Alignment and preview width

`alignment.mode = "block"` groups diagnostic lines separated by at most
`max_gap` clean lines. A block shares the anchor chosen from its widest code
line. `"buffer"` uses one anchor for the entire buffer, while `"none"` puts
each preview directly after its own line plus `padding`.

`padding` is the explicit blank space after Neovim's end-of-line cell; increase
it to `4` for a looser layout. With `include_range_width = true`, short
multiline diagnostics also reserve the width of their widest covered line, so
an import-block diagnostic stays beside the block. Ranges longer than
`max_range_lines` retain start-line alignment to keep rendering bounded.

`preview.width_mode` controls the pill body independently:

| Value | Result |
| --- | --- |
| `"fit"` | Each preview hugs its own content. |
| `"block"` | A block uses its widest preview width. |
| `"fixed"` | Every preview uses `preview.max_width`. |

When `hover.match_preview_width` is enabled, this chooses the starting body
width; matching may then grow or shrink that body within the configured preview
and hover limits.

With `count_align = "right"`, the block reserves a shared count slot. A custom
formatter receives the extra and total counts:

```lua
preview = {
  count_format = function(extra, total)
    return ("%d/%d"):format(extra, total)
  end,
}
```

`preview.format(diagnostic, context)` can replace the persistent one-line
message. Its context contains `bufnr`, `row`, the line's diagnostics, `count`,
and `group_id`. Newlines in callback output are collapsed so the preview
remains a single aligned row. A callback error is reported once and falls back
to the provider message.

### Diagnostic selection and grouping

The `diagnostics` table filters the shared input used by previews, hovers, and
query APIs. `severity` accepts `"error"`, `"warn"`, `"info"`, `"hint"`, the
matching Neovim severity number, or a list of either. `sources` and
`namespaces` are allow-lists; `exclude_sources` is applied afterward. The final
`filter(diagnostic, bufnr)` predicate is useful for project-specific rules. A
predicate error is reported once and fails open so diagnostics do not silently
disappear.

Some language servers publish the same issue through multiple namespaces. Set
`deduplicate = true` to collapse entries with matching range, severity, source,
code, and message. It defaults to `false` so the plugin does not change
Neovim's diagnostic set unexpectedly.

Selection and presentation are independent:

| Option | Values | Effect |
| --- | --- | --- |
| `hover.cursor_scope` | `"line"`, `"diagnostic"` | Open from any diagnostic line, or only while the keyboard cursor is inside a diagnostic range. |
| `hover.mouse_scope` | `"diagnostic"`, `"code"`, `"preview"`, `"line"` | Choose the exact mouse hit areas. `"diagnostic"` means diagnosed code or its preview pill. |
| `hover.group_by` | `"line"`, `"range"`, `"block"` | Expand all issues beginning on the selected line, only the selected range, or the entire aligned block. |

The defaults keep keyboard cursor hover convenient on a diagnostic line while
restricting mouse hover to diagnosed code and the rendered diagnostic itself.
For exact range-to-range navigation, use:

```lua
hover = {
  cursor_scope = "diagnostic",
  mouse_scope = "diagnostic",
  group_by = "range",
}
```

### Hover content and wrapping

The default expansion leads with the useful message. Source and diagnostic
code appear as quieter metadata below it; severity is carried by the glyph and
surface instead of a repeated `Error` label. Repeated sources are shown only
once within one float. All of this is configurable through `message_first`,
`metadata_position`, `show_source`, `show_code`, `show_severity`, and
`deduplicate_source`.

Explicit newlines from a provider become structured child lines. Lines created
by wrapping use the continuation glyph and a stable hanging indent.
`wrap_mode = "balanced"` rebalances the final pair of lines to avoid a short
orphan where possible; `"greedy"` uses ordinary word wrapping. Quoted strings,
backticked names, and quoted identifiers receive the `FloatCode` role when
`highlight_tokens` is enabled.

`match_preview_width = true` makes the persistent pill and expanded surface
share the pill's rendered width when their configured limits allow it. The
preview grows toward `min_width` without exceeding `preview.max_width`, keeping
both edges stable during ordinary expansion. Explicit width limits remain
authoritative: a smaller `preview.max_width` or constrained screen can make the
float differ, and preserving the left anchor may narrow it rather than jump.
Matching compares the preview with the float's content grid; a configured
`border` adds its own cells outside that width. Keep `border = "none"` for
identical visible outer edges.

Set `match_preview_width = false` to size the float independently:
`width_mode = "preferred"` requests the stable `preferred_width`; `"fit"` hugs
content between the limits, and `"fixed"` always requests `max_width`.
`max_width` remains a ceiling in every mode. Setup rejects widths too narrow
for the selected caps, padding, glyph lane, and a minimal message; reduce those
visual elements or increase the ceiling.

Provider details and complete content overrides use callbacks:

```lua
hover = {
  details = function(diagnostic)
    local data = diagnostic.user_data and diagnostic.user_data.my_linter
    return data and { "Rule: " .. data.rule, data.suggestion } or nil
  end,

  format_metadata = function(diagnostic, context)
    local parts = {}
    if context.show_source and diagnostic.source then
      table.insert(parts, diagnostic.source)
    end
    local code = diagnostic.code
    if type(code) == "table" then
      code = code.value or code.code
    end
    if code then
      table.insert(parts, tostring(code))
    end
    return table.concat(parts, " · ")
  end,
}
```

Formatter context contains `index`, `count`, `show_source`, `bufnr`, `winid`,
the cursor/mouse `row`, the preview's `layout_row`, `input`, `group_by`, and the
selected diagnostic as `target`. Returning a list joins its items as
provider-supplied lines. `relatedInformation` is added automatically while
`show_related` is enabled. Returning `nil` from an installed formatter
suppresses that role; an error falls back to the built-in formatter.

### Timing, placement, and focus

The plugin owns a target-aware timer. `delay_ms = nil` reads the current
`updatetime`; setting a number changes only this plugin. With `sticky = true`,
moving inside the same diagnostic line or multiline range neither restarts the
timer nor closes the float.

`input_mode` accepts `"cursor"`, `"mouse"`, or `"both"` (the default). When
both inputs are enabled, either can open or retain the same diagnostic without
restarting its timer. `mouse_scope = "diagnostic"` responds over diagnosed
source ranges and the rendered preview pill. `"code"` accepts only diagnosed
source ranges, `"preview"` accepts only the pill, and `"line"` accepts the
entire diagnostic screen line. Moving the pointer over an open float preserves
its target. A click that passes through that non-focusable float cannot select
a different diagnostic hidden underneath it; normal cursor ownership resumes
after the pointer leaves. The plugin restores the previous `mousemoveevent`
setting when disabled.

`use_mouse` remains as a deprecated compatibility option. When `input_mode`
is omitted, an explicitly configured `use_mouse = true` maps to `"mouse"` and
`false` maps to `"cursor"`. `input_mode` takes precedence when both are set.

Placement candidates are tried in `placement.order`. `"right"` expands from
the aligned preview anchor. With `preserve_anchor = true`, the float keeps the
preview's exact top-left cell and shrinks or truncates before relocating. If it
still cannot fit without covering the visible diagnostic range, `"below"` and
then `"above"` overlay unrelated screen rows instead. `edge_margin` keeps the
float away from split edges; `gap` separates relocated placements from the
source. No placement inserts buffer lines. Set a shorter order to disable
fallbacks, or set `preserve_anchor = false` for the previous repositioning
behavior.

While the same target remains open, scroll-driven refreshes retain the existing
screen column and width when the split width is unchanged. This prevents a
mouse click that moves the buffer cursor to end-of-line from narrowing the
surface. A real resize or content/configuration refresh still recomputes it.

While open, the active inline preview is hidden by default, other previews in
the same block are dimmed, and all diagnostic ranges represented by the float
are softly highlighted. Use `preview.inactive.scope = "buffer"` to dim every
other preview, or disable these effects with `hover.dim_inactive = false`,
`preview.inactive.enabled = false`, and `hover.highlight_target = false`.

`cap_style = "ends"` places the left cap only on the first row and the right
cap only on the last; intermediate edges stay flat. `"all"` caps every row and
`"none"` removes both cap lanes. The `border`, padding, cap glyphs, offsets,
and placement order can all be changed independently.

Use `:AlignedDiagnostic pin` when a message is too long to read passively. A
pinned surface becomes focusable, stops following cursor and mouse movement,
and keeps the complete formatted content in a scrollable scratch buffer while
the visible window remains bounded by `max_height`. Press `q` to close it or
`<Esc>` to unpin it and return to the source window. Refreshes reuse the same
float whenever possible, so expanding or updating a target does not introduce
an avoidable positional jump.

### Palette and highlights

Preview and float surfaces are blended from the editor background and their
severity tint. Blend values range from `0` (editor background) to `1` (full
tint). `preview_backgrounds` and `hover_backgrounds` accept exact per-severity
colors or highlight-group names and take priority over generated colors.
`hover_tint` and `hover_background` are shared hover overrides.

Automatic foreground selection meets `minimum_contrast` when possible. Turn
it off with `ensure_contrast = false` when supplying a complete palette.
`metadata_blend` quiets metadata, `inactive_blend` moves inactive previews
toward the editor canvas, and `active_blend` controls range highlighting.
`winblend > 0` further mixes the completed float with the screen beneath it.

Edge cells have a separate underlay from the diagnostic surface. This includes
preview caps and alignment padding plus every cap or flat reserved edge cell in
the expanded float. With `edge_underlay.combine = true`, preview edge groups
omit `bg`, allowing native highlights such as `ColorColumn` to flow through
the existing extmark `hl_mode = "combine"`. Floats are separate grids, so their
edge lanes resolve the configured background explicitly.

`overflow_column = nil` uses the greatest positive value in the source
window's `colorcolumn`. Set it explicitly when the overflow region is managed
by a match or another plugin:

```lua
vim.api.nvim_set_hl(0, "PastColorColumn", { bg = dark_bg })

require("aligned-inline-diagnostic").setup({
  appearance = {
    edge_underlay = {
      overflow_column = 100,
      overflow = "PastColorColumn",
    },
  },
})
```

`edge_underlay.resolve(context)` can return `"inherit"`, `"normal"`,
`"colorcolumn"`, `"overflow"`, a highlight-group name, `#RRGGBB`, an integer
colour, or `nil` for the default. Context contains `view` (`"preview"` or
`"hover"`), `side`, `virtual_column`, `screen_column` where available,
`severity`, `inactive`, `source_win`, `bufnr`, and row information. Set
`combine = false` when exact configured backgrounds should override native
preview-cell highlights as well.

Highlight names use a role plus `{Error,Warn,Info,Hint}`:

| Role pattern | Purpose |
| --- | --- |
| `AlignedDiagnosticPreview{Body,Icon,Count}…` | Active preview roles |
| `AlignedDiagnosticInactive{Body,Icon,Count,Cap}…` | Dimmed previews and edge foreground |
| `AlignedDiagnosticCap…` | Active preview edge foreground; background normally combines |
| `AlignedDiagnosticFloat{Body,Message,Metadata,Detail,Code,Cap}…` | Float roles |
| `AlignedDiagnosticHover…` | Float glyph lane |
| `AlignedDiagnosticActiveRange…` | Diagnosed source range |

Generic role groups without a severity suffix propagate to their four
per-severity groups unless a specific group is supplied. Published
`AlignedDiagnostic{Error,Warn,Info,Hint}` overrides remain compatible and feed
the new active preview roles.

```lua
appearance = {
  preview_blend = 0.10,
  hover_backgrounds = {
    error = "#4b353d",
    warn = "#4a4232",
    info = "#334653",
    hint = "#354a45",
  },
}

highlights = {
  AlignedDiagnosticFloatMetadata = { fg = "#a9b7c0", italic = true },
  AlignedDiagnosticFloatCodeInfo = { fg = "#b8d7e8", bold = true },
}
```

Inside `highlights`, `fg`, `bg`, and `sp` follow `nvim_set_hl()` and accept
hex, integer, and named colors; use a string value or `{ link = "Group" }` to
link an entire role to another highlight group. Appearance palette entries and
edge underlays additionally accept highlight-group names as color sources.

### Classic, metadata-first recipe

This recipe restores the denser hierarchy and less coordinated previews used
by earlier versions while retaining the current rendering fixes:

```lua
preview = {
  width_mode = "fit",
  count_align = "inline",
  inactive = { enabled = false },
}
hover = {
  match_preview_width = false,
  width_mode = "fit",
  message_first = false,
  show_severity = true,
  deduplicate_source = false,
  wrap_mode = "greedy",
  highlight_tokens = false,
  dim_inactive = false,
  highlight_target = false,
  placement = { order = { "right" } },
}
icons = {
  error = "●",
  warn = "●",
  info = "●",
  hint = "●",
}
appearance = { hover_blend = 0.16 }
```

## Commands and API

```vim
:AlignedDiagnostic enable
:AlignedDiagnostic disable
:AlignedDiagnostic toggle
:AlignedDiagnostic refresh
:AlignedDiagnostic open
:AlignedDiagnostic close
:AlignedDiagnostic pin
:AlignedDiagnostic unpin
:AlignedDiagnostic enable-buffer
:AlignedDiagnostic disable-buffer
:AlignedDiagnostic toggle-buffer
```

```lua
local diagnostics = require("aligned-inline-diagnostic")
diagnostics.enable()
diagnostics.disable()
diagnostics.toggle()
diagnostics.refresh(0)
diagnostics.open()
diagnostics.close()
diagnostics.pin()
diagnostics.unpin()
diagnostics.enable_buffer(0)
diagnostics.disable_buffer(0)
diagnostics.toggle_buffer(0)
diagnostics.is_enabled() -- global state
diagnostics.is_enabled(0) -- global and current-buffer state
diagnostics.get_diagnostics_under_cursor()
diagnostics.get_diagnostics_on_line()
```

Run `:checkhealth aligned-inline-diagnostic` to verify the Neovim version,
mouse support, palette background, cap widths, and same-buffer split state.

## Notes

Alignment is calculated from buffer-text display width, including tabs and
wide UTF-8 characters. Concealment and inline virtual text from other plugins
are not part of that measurement.

Extmarks are buffer-global in Neovim, so one preview layout and its active,
hidden, or dimmed state are shared when the same buffer is visible in multiple
windows. The plugin prefers the current/first visible source window for
window-local `colorcolumn`, horizontal-scroll, and preview-edge calculations.
For predictable overflow styling across such splits, give them matching
window options or set `appearance.edge_underlay.overflow_column` explicitly.

## Test

```sh
nvim --headless -u NONE -l tests/run.lua
```

CI additionally checks formatting and runs the suite on Neovim 0.10.4, stable,
and nightly.

## License

MIT
