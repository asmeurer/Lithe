# Lithe

Native macOS menu bar battery meter (Swift 6, AppKit + SwiftUI). A from-scratch
replacement for the Intel-only SlimBatteryMonitor: a small, configurable battery
icon and/or text in the menu bar, with per-state display modes, colors, shapes,
and a low-battery warning panel.

## Build

```
make            # Debug build into build/DerivedData (default target)
make run        # Build and launch the debug app
make test       # Run the Swift Testing suite (xcodebuild test)
make release    # Universal Release build, zipped into dist/
make install    # Release build copied to /Applications/Lithe.app
make lint       # SwiftLint (strict, same as CI)
make project    # Regenerate Lithe.xcodeproj from project.yml
make icon       # Regenerate the app icon PNGs from Scripts/make-icon.swift
make hooks      # Install the SwiftLint pre-commit hook
make clean      # Remove build/, dist/ and the generated project
```

- `Lithe.xcodeproj` is generated from `project.yml` by xcodegen and is gitignored.
  Edit `project.yml`, not the project. `make` regenerates it when `project.yml`
  changes; new Swift files under `Lithe/` or `LitheTests/` are picked up on the
  next `make project` (run it after adding files).
- The Makefile runs xcodebuild with the conda/pixi compiler environment variables
  (`LD`, `CC`, `SDKROOT`, …) unset; a conda-activated shell otherwise makes
  Xcode's link step fail. Use the Makefile rather than calling xcodebuild directly.
- Builds are ad-hoc signed (`CODE_SIGN_IDENTITY=-`). There is no Developer ID on
  this machine.

## Architecture

- **Xcode project via xcodegen**, macOS 14+, Swift 6 language mode with strict
  concurrency. No sandbox (not needed; IOKit and SMAppService work without it).
- **AppKit** app lifecycle (`NSApplicationDelegate`, `LSUIElement`), `NSStatusItem`
  with a custom-drawn image plus title. No `MenuBarExtra`: the point of the app is
  pixel-level control of the menu bar item.
- **SwiftUI** only for window content: the preferences window (hosted in an
  `NSWindow` via `NSHostingController`) and the low-battery panel.
- **IOKit power sources** (`IOPSCopyPowerSourcesInfo` + `IOPSNotificationCreateRunLoopSource`)
  for charge, state and time estimates; `AppleSmartBattery` in the I/O Registry for
  cycle count and capacity health.
- **SMAppService.mainApp** for launch at login. The toggle always reflects
  `SMAppService.mainApp.status`; the app never registers itself automatically.
- **Private API, one place only:** `SmartCharge` mirrors Control Center's
  "Charge to Full Now" (`temporarilyEnableCharging:` for Optimized Battery
  Charging, `temporarilyDisableMCL:` for the charge limit). Keep private API use
  confined to that file and fail soft.
- Preferences are one `Codable` struct (`DisplaySettings`) stored as JSON in
  `UserDefaults` under `DisplaySettings`. SlimBatteryMonitor's preferences
  (`org.orange-carb.SlimBatteryMonitor`) are imported once on first launch.

## Key files

- `Lithe/App.swift` - `@main`, `AppDelegate`, the hidden main menu for key equivalents
- `Lithe/Model/PowerSource.swift` - value types describing power sources and snapshots
- `Lithe/Model/PowerSourceParser.swift` - IOKit dictionary -> `PowerSource`
- `Lithe/Model/PowerMonitor.swift` - live IOKit reader and change notifications
- `Lithe/Model/BatteryHealth.swift` - I/O Registry battery health
- `Lithe/Preferences/DisplaySettings.swift` - all user settings, enums, colors
- `Lithe/Preferences/Preferences.swift` - persistence (`ObservableObject`)
- `Lithe/Preferences/LegacyImport.swift` - SlimBatteryMonitor preference import
- `Lithe/Rendering/StatusPresentation.swift` - pure logic: snapshot + settings -> what to show
- `Lithe/Rendering/BatteryIconRenderer.swift` - draws the icon shapes and composes images
- `Lithe/UI/StatusItemController.swift` - the status item, its menu, warnings, removal
- `Lithe/UI/SettingsView.swift` - the SwiftUI preferences UI
- `Lithe/UI/LowBatteryAlert.swift` - the floating low-battery panel
- `Lithe/Services/LoginItem.swift` - `SMAppService` wrapper
- `Lithe/Services/SmartCharge.swift` - "Charge to Full Now" via the private PowerUI
  `PowerUISmartChargeClient` (the class Control Center uses); loaded with `dlopen`,
  every selector checked, feature hidden if unavailable
- `LitheTests/` - Swift Testing suites; the parser, presentation, settings and
  renderer are pure and tested against fixtures (a real IOKit dictionary and a
  real SlimBatteryMonitor defaults export live in the tests)

## Development

- Run the tests with `make test`. CI (`.github/workflows/ci.yml`) runs them plus a
  universal Release build and SwiftLint on pushes and PRs to `main`, on the
  `macos-26` runner pinned to Xcode 26.6. Locally Xcode 27 is used; avoid macOS
  27-only APIs and Swift 6.4-only syntax so CI keeps compiling.
- To check the menu bar rendering, `make run`, then screenshot the menu bar
  (`screencapture -x -R 0,0,1728,44 file.png`). On this notch MacBook the item
  can be tucked into the overflow chevron at the notch. Accessibility works for
  inspection: `osascript -e 'tell application "System Events" to tell process
  "Lithe" to get {position, size, help} of every menu bar item of menu bar 2'`.
- Quit a running dev copy (`pkill -x Lithe`) before rebuilding; xcodebuild
  replaces the app bundle in place.
- Do not touch the user's login items while testing (`SMAppService.register()`
  is only ever called from the toggle).

## roborev reviews

Every commit in this repo is automatically reviewed in the background by
[roborev](https://www.roborev.io/index.md) (a post-commit hook that runs Codex). After
committing, check for findings and address open reviews before finishing:

- `roborev list --open` lists open reviews on the current branch; `roborev show <job_id>`
  shows the full review, and `roborev wait` blocks until a pending review completes.
- The reviews use a weaker model, so judge each finding yourself. If a review is invalid,
  close it with `roborev close <job_id>`.
- If the fix is simple, run `roborev fix <job_id>` — it applies the fix with Codex and
  closes the job when done.
- If the fix is too complicated for Codex, or it's something you were going to do anyway,
  fix it yourself, then `roborev close <job_id>`.

## Releasing

When significant changes have been made (new features, important bug fixes, UI changes),
create a release:

1. Add the changes to `CHANGELOG.md` under a `## [x.y.z] - YYYY-MM-DD` heading
2. Bump `MARKETING_VERSION` in `project.yml` (semver: major.minor.patch); the app's
   `CFBundleShortVersionString` is single-sourced from it
3. Commit the changelog and version bump
4. Tag with `git tag v<version>` and push the tag with `git push origin v<version>`
5. The GitHub Actions release workflow (`.github/workflows/release.yml`) builds a
   universal app, signs it (Developer ID + notarization when the secrets exist,
   ad-hoc otherwise), and attaches `Lithe-<version>.zip` to the GitHub release

## Conventions

- Always commit changes as soon as they are made. Do not batch up multiple unrelated
  changes. Do not ask before committing. Push once the GitHub remote exists.
- The pre-commit hook (`make hooks`) runs SwiftLint on staged Swift files; CI runs it
  in strict mode, so fix warnings too.
- Swift 6 strict concurrency: `@MainActor` for UI/state classes; C callbacks and
  `@Sendable` notification closures hop back with `MainActor.assumeIsolated` (the
  sources are scheduled on the main run loop) or go through a `WeakBox`.
- Avoid silencing exceptions — log loudly (`NSLog`) and degrade to "unknown" only where
  a missing IOKit key is expected.
- Keep `StatusPresentation` and the parsers pure so they stay unit-testable; put
  AppKit side effects in the controllers.
- American English spelling in code, comments and UI text.
- When working in a git worktree, always merge the worktree branch into `main` and push
  once the work is complete. Use `git checkout main && git merge <worktree-branch> && git push origin main`.
- Always use `git merge`, never `git rebase`. When pulling remote changes, use `git pull`
  (not `git pull --rebase`).
