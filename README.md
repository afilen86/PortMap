# Port Map

A SwiftUI Mac app that maps what is plugged into this Mac: each port, the hubs and devices behind it, and the cable path between them. Port data comes from the WhatCable helper, which must be installed (the app in /Applications, or `whatcable` from Homebrew).

## Workspace Orbit preview release

The selected interface is available as an offline browser package: **Clay Studio in Light Mode**, **After Hours in Dark Mode**, and a **System** appearance option. All device images remain visible while tracing routes.

[Download the offline preview ZIP](https://github.com/afilen86/PortMap/raw/refs/heads/main/packages/orbit-preview-v0.1.0/PortMap-Orbit-Preview-0.1.0.zip) · [Package and checksum](packages/orbit-preview-v0.1.0/README.md) · [Selected preview guide](web/public/orbit/README.md)

Extract the release ZIP, then double-click **Port Map Orbit.html** on your Mac. No server or developer tools are needed. This preview uses saved data; it isn't a native Mac installer or a live hardware scanner.

To build the offline ZIP and SHA-256 checksum from source (Python 3.10+):

```bash
python3 web/design-tools/package-orbit.py
```

Build output is written to `web/release/`; the verified 0.1.0 download is also retained in the versioned `packages/` folder. Tags named `orbit-preview-v<web/package.json version>` run the GitHub release workflow, which builds, tests, and publishes a preview prerelease. Release notes live in `web/releases/`.

## Browser UI development

A browser-based React + TypeScript UI now lives in [`web/`](web/README.md). It uses the saved WhatCable report, includes Overview, Connection tree, and Ports views, and supports light/dark themes, search, JSON import, and preview scenarios.

```bash
cd web
npm ci
npm run dev        # http://localhost:5173
npm run build
npm test          # Chromium browser checks
```

Visual changes can be developed and checked on Linux, Windows, or macOS. The web UI includes a validated, versioned `WKWebView` bridge contract; embedding it into the Mac app is a separate next step. The existing SwiftUI app still builds as before. See [the web UI guide](web/README.md) for the data format, limitations, and integration instructions.

## Build

```bash
./build.sh          # builds build/Port Map.app
./build.sh --run    # build and open
./build.sh --zip    # build and zip to build/PortMap-<version>-build<n>.zip
```

Requires the Xcode command-line tools (Swift 6, macOS 14+, Apple silicon).

The version and build number come from `port-map-source/Info.plist`. Bump them there before a release.

## Layout

- `port-map-source/`: the app
  - `PortMapApp.swift`: the app entry point, window and main map view
  - `PortScan.swift`: runs WhatCable and parses its JSON into ports and connections
  - `DeviceWatcher.swift`: rescans automatically when a USB or Thunderbolt device is plugged in or removed, or displays change
  - `PowerMonitor.swift`: streams `whatcable --monitor-json` (WhatCable Pro) for live power per Mac port; the power readouts hide themselves without Pro
  - `SetupView.swift`: the setup and overview diagrams, the device artwork and the routing
  - `Resources/ManualConnections.json`: connections macOS can't detect (analog audio, or USB between two other devices). Each entry names its `parent` device by title, the `cable`, and a `photo`; edit this file to add more
  - `Info.plist`, `Resources/`: bundle metadata, artwork and icon. `CalDigit*.jpg` and `Satechi*.jpg` are product photos from Adorama's listings (CalDigit Element Hub `cd500934`, Satechi ST-GNMMES `satstgnmmes`), trimmed for the hub ports panel. `Scarlett4i4.jpg` is from Focusrite's product page and `KlipschFives.jpg` from Klipsch's and `MaestroDMX.jpg` from maestrodmx.com; they're for personal use in this app
- `OverviewCheck.swift`, `HubOverviewCheck.swift`, `port-map-verify/`: standalone layout check programs from the Codex sessions
- `MakePortMapIcon.swift`, `PortMap.iconset/`: icon generation
- `*.py`: one-off scripts Codex used to patch the source (history only)
