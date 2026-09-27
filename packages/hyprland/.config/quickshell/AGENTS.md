# Quickshell Schema Guide

This file documents the intended architecture for this config.

## Purpose

The goal is to keep UI structure easy to read in `App.qml`, while keeping reusable pieces and logic separated by responsibility.

## Directory Roles

### `src/components/`
Reusable, generic UI primitives.

- Components in this directory should be presentation-focused and broadly reusable.
- They should avoid app-specific behavior whenever possible.
- Example: `src/components/Chip.qml` (a generic wrapper/styled container that can wrap arbitrary content).

### `src/widgets/`
Functional, movable UI pieces.

- Widgets represent concrete bar pieces/features.
- Each widget should be independently placeable in any shell surface.
- Widgets can include local behavior needed for that feature.
- Examples: `Bluetooth`, `Volume`, `Brightness`, `HyprlandWorkspaces`, `LeftBarSection`, `RightBarSection`.

### `src/services/` (planned)
Shared logic/state layer for cross-widget reuse.

- Add this when multiple widgets need the same logic/data source.
- Services should centralize data fetching, polling, transformations, and shared actions.
- Widgets should bind to services rather than duplicating shared logic.

### `src/modules/` (planned)
Large UI surfaces/compositions.

- Modules are top-level assembled interfaces made from widgets/components.
- Examples: top bar, side bar, notification center, dashboard.
- Modules should focus on layout/composition, not low-level reusable primitives.

## Practical Rule of Thumb

- If it is generic UI chrome: put it in `components`.
- If it is a concrete feature block you can move around: put it in `widgets`.
- If logic is shared across widgets: extract it into `services`.
- If it is a large composed surface: put it in `modules`.

## Shell UX Rules

- Prioritize glanceability first and detail second.
- Bar widgets should expose only the most important state or action; deeper controls belong in overlays or menus.

- Keep interaction patterns consistent across all surfaces.
- Overlays should open in predictable positions, close the same way in similar contexts, and follow shared focus and backdrop conventions unless there is a clear reason not to.

- Respect active input modality.
- Keyboard-driven interaction must not be overridden by hover behavior, pointer position, or background refreshes.
- Pointer hover should aid discovery, not steal selection or focus from active typing or navigation.

- Keep widgets placement-agnostic.
- A widget should work in any shell surface without assuming one specific bar location, monitor, or layout.

- Reuse visual primitives and theme tokens.
- Spacing, sizing, radii, typography, colors, and state styling should come from shared theme values rather than one-off constants.
- Generic interaction chrome should be built from shared components before introducing widget-specific styling.

- Prefer immediate, restrained feedback.
- Hover, pressed, selected, active, warning, and error states should be obvious and readable without feeling noisy or over-animated.
- Motion should clarify state changes, not decorate them.

- Separate shared logic from UI composition.
- If multiple widgets need the same data, action, or transformation, move it into a service instead of duplicating behavior.
- Modules should compose widgets and components; they should not become the place where reusable interaction logic is reimplemented ad hoc.

- Make multi-screen behavior intentional.
- Menus, overlays, and transient UI should appear on the relevant screen and avoid surprising cross-monitor behavior.

- Optimize for failure tolerance.
- Missing data, empty states, and unavailable integrations should degrade cleanly, remain readable, and avoid breaking layout or trapping focus.

- When making UX changes, prefer preserving existing shell patterns over introducing a better-looking but inconsistent interaction model.
