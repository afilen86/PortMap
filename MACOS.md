# Port Map for macOS: Workspace Orbit

Port Map now includes a native `WKWebView` window for the selected Orbit interface:

- **Light:** Clay Studio, with terracotta/olive colors and compact peripherals.
- **Dark:** After Hours, with plum/rose colors and larger photos.
- **System:** follows macOS appearance. The title bar follows the selected mode too.

Swift continues to scan hardware with WhatCable, monitor device changes, condense internal interfaces, and attach the existing manual audio links. The browser interface renders those device relationships and routes. Photos stay visible when selecting a route. Unknown devices get a clearly representative placeholder; larger setups receive an expanded layout. Animated data flow illustrates direction, not measured traffic.

## Download the app

[Download Port Map 1.5 (build 9), universal Mac app](https://github.com/afilen86/PortMap/releases/download/macos-orbit-v1.5-build9/PortMap-1.5-build9.zip) · [Release details](https://github.com/afilen86/PortMap/releases/tag/macos-orbit-v1.5-build9)

Extract the ZIP in Finder, then move **Port Map.app** to Applications. No developer tools or build step are needed for this download. The beta is ad-hoc signed rather than notarized; macOS may require **Open Anyway** in **System Settings → Privacy & Security**.

## Build on your Mac

Requires macOS 14+, Xcode Command Line Tools (Swift 6 toolchain), and Python 3. The selected interface bundles locally; Node and a running web server are not needed to build or use the Mac app.

1. Extract the Mac build kit, or clone the repository's `macos-orbit-app` branch.
2. Double-click **Build Port Map.command** in Finder. Alternatively, run this in Terminal from the project directory:

   ```bash
   ./build.sh --zip --run
   ```

3. The script creates and opens **build/Port Map.app**, plus **build/PortMap-1.5-build10.zip**. You can move the app to Applications.

If the free Xcode tools aren't installed, run `xcode-select --install`, finish the system installer, and run the build again. If macOS doesn't preserve the scripts' executable permissions after downloading, run `bash build.sh --zip --run` from Terminal.

The app is ad-hoc signed for local testing. Downloaded builds are not Developer ID signed or notarized; broader distribution needs a signing identity and notarization. No signing certificates are required for a local source build.

## Live hardware and demo mode

Install WhatCable in Applications, or its `whatcable` Homebrew helper, for live device data. The app reuses the existing helper discovery and automatic reconnect watcher.

If WhatCable is missing or a scan fails, the native interface shows the error and a **Show demo setup** button. Demo mode is explicitly labeled as saved data. **Refresh connections** (or **⌘R**) switches back to live scanning. A failed refresh preserves the last valid report. The app never treats the saved preview setup as detected hardware.

The **Appearance & View** menu can switch to the original SwiftUI view. Existing WhatCable Pro power readings remain available there; Orbit's first native integration displays device topology and link information rather than live power telemetry.

## Validate on macOS

```bash
./build.sh --debug --smoke-test --zip
./build.sh --universal --smoke-test --zip
```

The smoke check launches the real bundled app in demo mode, waits for `WKWebView` to load, verifies all 19 demo images, switches both approved appearances, and verifies the bridge. It exits with an error if WebKit/JavaScript fails. The universal build contains Apple silicon and Intel binaries. `Build macOS Orbit app` in GitHub Actions runs this on a macOS runner and uploads the app ZIP when successful.

The universal app was compiled and smoke-tested on a real macOS runner in [successful build 43745262359](https://github.com/afilen86/PortMap/actions/runs/43745262359). The published ZIP was downloaded again and verified against its SHA-256 checksum, Info.plist version, universal Mach-O header, bundled Orbit HTML, and code-signature resources. Browser production builds and all 27 browser tests also pass. Live WhatCable discovery still depends on the helper and devices installed on the user's Mac.

## Edit the interface

- `web/design-tools/orbit-variants.css`: the shared Clay Studio and After Hours styles.
- `web/design-tools/build-orbit-appearance.py`: selected appearance controls and base scene.
- `web/native/orbit-host.js`: live report validation, placement, cable routing, and native message adapter.
- `web/design-tools/build-native-orbit.py`: bundles the selected UI and artwork for the Mac app.
- `port-map-source/OrbitWebView.swift`: native window, navigation boundary, and structured JavaScript messages.
- `orbitSnapshot(scan:)` in `SetupView.swift`: exports the same physical-device inventory used by the native overview.

Rebuild with `./build.sh --run` after visual edits. The offline preview and its published 0.1.0 package remain unchanged.

The native bridge accepts only version 1 messages from the bundled main frame: `ready`, `refresh`, `demo`, and `appearance`. The host sends a `state` object with refresh/error status and the live inventory or an explicit demo flag. JavaScript receives structured objects; device names and error strings are never interpolated into executable code. Navigation is restricted to the bundled entry file.
