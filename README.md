# MyScreen

<p align="center">
  A native macOS monitoring wall for live displays and app windows.
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#permissions">Permissions</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="#limitations">Limitations</a> •
  <a href="#contributing">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-111111?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.2-F05138?style=flat-square" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/status-experimental-8A8A8A?style=flat-square" alt="Experimental">
</p>

MyScreen turns your Mac into a small control room for windows and screens. You pick the displays and app windows you care about, and MyScreen keeps them in a single monitoring wall with live previews, automatic layout, and persistent state between launches.

This project is source-first and open development focused. There is no notarized installer or packaged release yet; the current workflow is to build and run it locally from source.

## Features

- Live previews for physical displays and selected app windows
- One wall for both display sources and window sources
- Automatic grid layout with optional fixed column counts
- Focus mode for a single enlarged source
- Drag-to-reorder in the standard grid view
- Offline detection for closed windows and disconnected sources
- Session persistence for selected sources, layout, and focus state
- Source picker with live previews before adding sources
- Click-to-activate for window tiles
- Adaptive capture budget for larger walls

## Why MyScreen

MyScreen is useful when you want a lightweight monitoring wall for your own Mac rather than a remote desktop product or a recording system. It is designed for:

- Multi-app workflows where several windows need to stay visible at once
- Multi-display setups that need a compact “overview wall”
- Builders, operators, traders, streamers, and power users who want a quick glance view

It is not trying to be:

- A remote access tool
- A screen recorder
- A historical playback system
- A window manager that rearranges real app windows on your behalf

## Installation

MyScreen currently ships as source code.

### Requirements

- macOS 14 or newer
- Swift 6.2 toolchain
- Full Xcode recommended for running, debugging, and producing a normal `.app`

### Build From Source

```bash
git clone https://github.com/caopulan/MyScreen.git
cd MyScreen
swift build
```

You can also open the Swift package directly in Xcode.

## Quick Start

Run the app:

```bash
swift run MyScreen
```

First launch flow:

1. Grant `Screen Recording` when macOS prompts.
2. Click the floating `Add` button.
3. Add one or more displays or windows.
4. Drag tiles to reorder the wall.
5. Click a window tile to activate the underlying app window.

If the permission dialog does not appear again, re-enable access in:

`System Settings > Privacy & Security > Screen & System Audio Recording`

## Permissions

MyScreen depends on standard macOS privacy permissions:

- `Screen Recording`
  Required for display capture and window preview capture.
- `Accessibility`
  Optional. Only needed if you want MyScreen to raise and focus a window when clicking its tile.

Without `Screen Recording`, the monitoring wall does not start. Without `Accessibility`, the wall still works, but click-to-activate may be incomplete.

## Usage

### Add monitoring sources

MyScreen supports two kinds of sources:

- `Displays`
  Each physical display becomes one source and shows whatever is currently visible on that display, including a full-screen app.
- `Windows`
  Specific app windows selected manually from the source picker.

### Reorder the wall

- In the standard grid view, drag a tile to a new position.
- The rest of the wall shifts to preview the new order before you release.
- The new order is saved when the drag finishes.

### Change layout

- Use the `Layout` button in the bottom-right controls.
- Choose `Auto` or a fixed column count from `1` to `6`.

### Focus one source

- Use the focus button in a tile header to enlarge one source.
- Exit focus to return to the full grid wall.

## How It Works

The current implementation is a native SwiftUI/AppKit macOS app.

- `SourceCatalogService`
  Enumerates displays with `NSScreen` and windows with `CGWindowList`, then enriches app metadata with `NSWorkspace`.
- `CaptureCoordinator`
  Captures preview frames from displays and windows using `CoreGraphics` snapshots and scales them based on the active capture budget.
- `AppState`
  Holds selected sources, tile states, wall layout, persistence, and permission flow.
- `WallSessionSnapshotStore`
  Persists wall configuration between launches.

Relevant entry points:

- [Sources/MyScreen/MyScreen.swift](Sources/MyScreen/MyScreen.swift)
- [Sources/MyScreen/App/AppState.swift](Sources/MyScreen/App/AppState.swift)
- [Sources/MyScreen/Features/Wall/MonitorWallView.swift](Sources/MyScreen/Features/Wall/MonitorWallView.swift)
- [Sources/MyScreen/Services/SourceCatalog/SourceCatalogService.swift](Sources/MyScreen/Services/SourceCatalog/SourceCatalogService.swift)
- [Sources/MyScreen/Services/Capture/CaptureCoordinator.swift](Sources/MyScreen/Services/Capture/CaptureCoordinator.swift)

## Project Structure

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
    SourcePreview/
    WindowActivation/
  Views/
Tests/MyScreenTests/
```

## Development

Build:

```bash
swift build
```

Run tests:

```bash
swift test
```

The current test suite covers:

- Stable source identity
- Wall snapshot persistence
- Grid calculation
- Capture budget planning
- Source reconciliation
- Reorder helper behavior

## Limitations

Current trade-offs in this repository:

- No notarized installer or packaged `.app` release yet
- No recording, alerting, or playback
- No remote machine monitoring
- No true multi-window control-room UI across multiple MyScreen app windows
- Hidden or other-Space windows are less reliable than visible windows because capture is constrained by macOS behavior

If you need packaged distribution, remote access, or full recording workflows, this repository is not there yet.

## Documentation

This README is the primary project documentation today.

If you are exploring the codebase, start with:

- [Sources/MyScreen/MyScreen.swift](Sources/MyScreen/MyScreen.swift)
- [Sources/MyScreen/App/AppState.swift](Sources/MyScreen/App/AppState.swift)
- [Sources/MyScreen/Features/SourcePicker/SourcePickerView.swift](Sources/MyScreen/Features/SourcePicker/SourcePickerView.swift)
- [Sources/MyScreen/Features/Wall/MonitorTileView.swift](Sources/MyScreen/Features/Wall/MonitorTileView.swift)

## Contributing

Contributions are welcome.

- Open an issue for bugs, edge cases, or UX problems
- Open a PR for focused improvements
- Keep changes scoped and testable
- Run `swift build` and `swift test` before sending a PR

## License

This repository does not currently include a `LICENSE` file.

If you plan to make the project publicly reusable as open source, adding a license should be one of the next changes.
