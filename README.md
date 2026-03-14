# MyScreen

MyScreen is a native macOS monitoring wall for displays and app windows. It lets you build a single-window "control room" view that keeps live previews of selected screens and app windows, automatically arranges them, and preserves your wall state between launches.

## What v1 does

- Requests Screen Recording permission up front and blocks the wall until permission is granted.
- Discovers shareable displays and on-screen app windows with `ScreenCaptureKit`, `NSWorkspace`, and `CGWindowList`.
- Lets you manually add displays and windows into one monitoring wall.
- Streams live preview tiles for selected sources and automatically downgrades frame delivery when the wall grows beyond 12 sources.
- Supports focus mode, auto-grid layout, offline detection, and persisted wall state.

## Project structure

```text
Sources/MyScreen/
  App/
  Features/
    Permissions/
    SourcePicker/
    Wall/
  Infrastructure/Persistence/
  Models/
  Services/
    Capture/
    Permissions/
    SourceCatalog/
Tests/MyScreenTests/
```

## Requirements

- macOS 14 or newer
- Swift 6.2 toolchain
- Full Xcode is recommended for running and debugging the GUI app

The current repository builds with `swift build`, but for normal app development and signing you should open the package in Xcode.

## Run

```bash
swift build
swift run
```

When the app launches for the first time, macOS will ask for Screen Recording permission. If the prompt does not reappear, re-enable access in:

`System Settings > Privacy & Security > Screen & System Audio Recording`

## Current limitations

- v1 is monitoring-only. It does not move or control real macOS windows.
- The wall is a single app window. It does not yet split into multiple app windows across displays.
- Recording, alerts, and historical playback are intentionally out of scope.

## Testing

```bash
swift test
```

The test suite covers stable source identity, persistence round-trips, wall grid calculation, capture budget planning, and offline reconciliation.
