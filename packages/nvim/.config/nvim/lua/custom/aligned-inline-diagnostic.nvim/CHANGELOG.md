# Changelog

## Unreleased

### Added

- Simultaneous keyboard-cursor and mouse hover, with independent hit scopes.
- Line, exact-range, and aligned-block expansion groups.
- Severity, source, namespace, predicate, and optional duplicate filtering.
- Custom persistent-preview formatting and richer hover formatter context.
- Focusable, scrollable pinned diagnostics with `pin` and `unpin` actions.
- Per-buffer enable, disable, toggle, and status APIs.
- `:checkhealth aligned-inline-diagnostic` diagnostics.
- CI coverage for Neovim 0.10.4, stable, and nightly.

### Improved

- Persistent previews and expanded surfaces now share their rendered width by
  default when configured limits allow it; the behavior is configurable with
  `hover.match_preview_width`.
- In-place expansion now accounts for Neovim's end-of-line display cell, so
  hovering no longer shifts the surface one column to the left.
- Short multiline ranges contribute their widest source line to alignment and
  use side placement when they do not actually overlap the expanded surface.
- Scroll-driven refreshes preserve an open surface's column and width, avoiding
  cursor-click resizing while the split dimensions remain unchanged.
- Clicks passing through a mouse-held float no longer replace it with a
  differently sized diagnostic from the covered source row.
- Hidden previews retain their measured pill width across diagnostic layout
  rebuilds, keeping cursor and mouse expansions the same size.
- Default source-to-preview padding increased from two to three cells.
- Expanded floats are updated in place whenever their target and surface are
  still valid, reducing visual jumps.
- Render and mouse events are coalesced; stale timer callbacks are cancelled
  across setup, enable, disable, close, and buffer lifecycle transitions.
- Hover creation is transactional and handles invalid buffers, windows,
  diagnostics, namespaces, callback failures, and unavailable geometry safely.
- Preview calculations handle tabs, wide UTF-8 glyphs, overflow regions, and
  color-column edge underlays with fewer window-option queries.
- Highlight overrides now validate stable `nvim_set_hl()` fields while keeping
  unknown fields available for future Neovim versions.

### Compatibility

- No command or public API was removed. `hover.use_mouse` remains supported;
  `hover.input_mode` takes precedence when both are present.
- Existing line-grouped keyboard behavior remains the default. Set
  `cursor_scope = "diagnostic"` and `group_by = "range"` for exact selection.
- Diagnostic deduplication is opt-in, preserving Neovim's original set by
  default.
- The README contains a classic visual recipe for the earlier metadata-first,
  compact-width presentation.
