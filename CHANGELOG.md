# Changelog

All notable changes to Lithe will be documented in this file.

## [0.1.0] - 2026-09-16

Initial release.

- Menu bar battery meter with a separate display mode for each state (on battery,
  charging, charged): hidden, icon, icon and percent, icon and time remaining,
  percent only, or time only
- Five icon shapes (rectangular, rounded with terminal, thin, rounded, horizontal)
- Per-state fill colors, outline and text color, each either automatic (follows
  the light or dark menu bar) or custom; a warning color below a chosen charge
- Low-battery warning panel with sound
- Menu showing the current state, time estimate, cycle count, maximum capacity,
  and power adapter wattage
- Support for removed batteries, multiple batteries, and UPS units
- Launch at login through `SMAppService`
- Remove from the menu bar for the session or forever (also by Cmd-dragging)
- Imports SlimBatteryMonitor's display preferences on first launch
- Universal (Apple silicon and Intel) build, macOS 14 or later
