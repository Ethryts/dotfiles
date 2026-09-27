# Quickshell Config

This config is structured around a small root app that composes focused modules,
widgets, and services.

## Entry Points

- `shell.qml`: Quickshell entrypoint.
- `src/App.qml`: application composition root.

## Structure

- `src/components/`
  Reusable presentation primitives such as `Chip`, `OverlayPopup`, and shared
  quick-control rows.

- `src/widgets/`
  Concrete feature blocks that can be placed inside bars, popups, or overlays.
  Examples: `Volume`, `Wifi`, `NotificationToast`, `HyprwhisperStatusBar`.

- `src/services/`
  Shared state and control logic. These handle polling, IPC, script execution,
  and controller state for UI surfaces.

- `src/modules/`
  Top-level composed surfaces. These own screen/window placement and assemble
  widgets into complete interfaces such as the bar, launcher, quick controls,
  notification overlay, and Hyprwhisper overlay.

- `src/theme/`
  Theme tokens exposed through `Theme.qml` and backed by `ThemeService`.

- `scripts/`
  External shell helpers used by services for system integration.

## Runtime Model

`src/App.qml` instantiates long-lived services first, then passes them into
modules:

- `Bar`
- `CalendarMenu`
- `LauncherMenu`
- `NotificationOverlay`
- `OverlayModule`
- `HyprwhisperOverlay`
- `QuickControlsMenu`

Services are the shared logic layer. Widgets should prefer binding to services
instead of duplicating polling or process management locally.

## Current Boundaries

The codebase generally follows the intended split in `AGENTS.md`:

- Generic visual primitives live in `components`.
- Movable feature blocks live in `widgets`.
- Cross-widget logic lives in `services`.
- Full-screen or screen-anchored surfaces live in `modules`.

## Known Refactor Targets

These files are the main complexity hotspots and are the best candidates for
future extraction:

- `src/modules/LauncherMenu.qml`
  Split search state/process handling from the surface layout.

- `src/services/NotificationService.qml`
  Split notification grouping/presentation helpers from lifecycle tracking.

- `src/modules/QuickControlsMenu.qml`
  Reasonable as-is, but could eventually share popup-window scaffolding with
  other overlay modules.

## Practical Rule

- If it is generic UI chrome, put it in `components`.
- If it is a concrete movable feature block, put it in `widgets`.
- If multiple widgets need the same state or actions, put it in `services`.
- If it is a full assembled surface, put it in `modules`.
