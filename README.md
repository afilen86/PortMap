# Port Map

A SwiftUI Mac app that maps what is plugged into this Mac: each port, the hubs and devices behind it, and the cable path between them. Port data comes from the WhatCable helper, which must be installed (the app in /Applications, or `whatcable` from Homebrew).

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
  - `Info.plist`, `Resources/`: bundle metadata, artwork and icon. `CalDigit*.jpg` and `Satechi*.jpg` are product photos from Adorama's listings (CalDigit Element Hub `cd500934`, Satechi ST-GNMMES `satstgnmmes`), trimmed for the hub ports panel. `Scarlett4i4.jpg` is from Focusrite's product page and `KlipschFives.jpg` from Klipsch's; they're for personal use in this app
- `OverviewCheck.swift`, `HubOverviewCheck.swift`, `port-map-verify/`: standalone layout check programs from the Codex sessions
- `MakePortMapIcon.swift`, `PortMap.iconset/`: icon generation
- `*.py`: one-off scripts Codex used to patch the source (history only)
