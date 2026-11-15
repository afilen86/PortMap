# Port Map web UI

Edit and preview Port Map without Swift or macOS. React + TypeScript components use a versioned data model, shared CSS tokens, and an adapter for the saved WhatCable report. All fonts, icons, scripts, and styles are bundled locally; the UI makes no network requests at runtime.

## Start

Requires Node.js 22+ and npm.

```bash
cd web
npm ci
npm run dev
```

Open http://localhost:5173. Changes to `src/App.tsx` and `src/styles.css` appear immediately. The Overview, Connection tree, and Ports views share selection, search, and connection details. Appearance and view preferences persist locally.

Use **Preview state** at the bottom to explore the saved setup, empty ports, a large setup, or a scan error. Browser reload simulates loading; it does not scan hardware. The upload button accepts a WhatCable `--json` report or the normalized Port Map format. Imported files stay in memory and are never uploaded. Reloading the page restores the sample. The sample's host is explicitly identified as Mac mini, but raw report imports use “This Mac,” because WhatCable JSON doesn't identify the computer or physical port positions.

## Selected Workspace Orbit preview

Open [`/orbit/index.html`](public/orbit/index.html) for the chosen pairing: **Clay Studio in Light Mode** and **After Hours in Dark Mode**. A Light / Dark / System appearance control saves the preference and follows system changes in System mode. The HTML also opens directly on a Mac without a server. See [the selected preview guide](public/orbit/README.md).

## Three photo-led design mockups

Open [the design lab](public/mockups/index.html) as a standalone HTML file, or visit `http://localhost:5173/mockups/index.html` while the server is running. Switch between **Connection Atlas**, **Signal Desk**, and **Workspace Orbit**. Each preserves all device images while tracing data and audio paths. The file works offline and can be downloaded to a Mac without Node or Swift.

Three further **Workspace Orbit** iterations—Glacier, After Hours, and Clay Studio—are available at [`/mockups/orbit/index.html`](public/mockups/orbit/index.html). They vary the palettes, card spacing, and device image sizes. See [the Orbit iteration guide](public/mockups/orbit/README.md).

See [the mockup guide](public/mockups/README.md) for image provenance, flow semantics, limitations, and rebuild instructions. These are design explorations; the React app remains available at `/`.

## Where to make changes

- `src/styles.css`: theme tokens, typography, responsive layout, and component styles. Light and dark palettes are defined at the top.
- `src/App.tsx`: application state, navigation, report import, and source selection.
- `src/ConnectionViews.tsx`: map cards, connection tree, and route inspector.
- `src/components.tsx`: shared device icons, status indicators, and summary statistics.
- `src/model.ts`: normalized schema, runtime validation, route traversal, and the WhatCable adapter.
- `src/data.ts`: preview scenarios derived from `../overview-scan.json`. The recorded time is fixture metadata, not a live scan time. Large-setup devices are synthetic.
- `src/bridge.ts`: native transport; UI components don't call native hardware APIs.
- `tests/app.spec.ts`: real Chromium tests, including selection, import, device routes, themes, native messages, and responsive layouts.

Counts include the USB and Thunderbolt interfaces actually reported by WhatCable. The web preview doesn't yet reproduce the native app's physical-device deduplication, mounted volume enrichment, manual analog connections, or live power readings. No guesses about physical port positions or storage warnings are made.

## Build and verify

```bash
npm run build
npm test
npm run format:check
```

`dist/` contains the production UI, with relative asset paths for embedding. Tests use `/usr/bin/chromium` by default; set `CHROMIUM_PATH` to your Chromium executable on another machine. Screenshots at 1440, 920, and 390 pixels are written into ignored `test-results/`.

## Native bridge contract (version 1)

This contract describes the React explorer. The native Mac app embeds the selected Orbit page using the separate `state` adapter documented in [the macOS guide](../MACOS.md); the React explorer remains independent.

Register a `WKScriptMessageHandler` named `portMap` before loading the page. When the handler exists, the web UI starts in a loading state, hides preview scenarios, and requests data:

```ts
// Web → native, via window.webkit.messageHandlers.portMap.postMessage
{ type: 'ready', schemaVersion: 1 }
{ type: 'refresh', schemaVersion: 1 }
```

Send the normalized snapshot after `ready`, after a successful refresh, and when devices change:

```ts
// Native → web
window.portMap.receive({
  type: "snapshot",
  snapshot: {
    schemaVersion: 1,
    host: "Mac mini",
    source: "WhatCable 1.5.0 + macOS",
    capturedAt: "2026-11-15T12:00:00.000Z",
    ports: [
      {
        id: "Port-USB-C@1",
        name: "Rear left",
        group: "Rear Thunderbolt",
        connected: true,
        speed: "40 Gb/s",
        description: "Running at full speed",
        cable: "Thunderbolt 4", // optional
        children: [
          {
            id: "Port-USB-C@1/hub",
            name: "Element Hub",
            detail: "CalDigit",
            speed: "40 Gb/s", // optional
            kind: "hub", // hub | drive | display | device
            children: [],
          },
        ],
      },
    ],
  },
});
window.portMap.receive({
  type: "error",
  message: "WhatCable could not complete the scan.",
});
```

IDs must be unique across the entire snapshot and stable between scans. Every field shown is required except `speed` on devices and `cable` on ports. Snapshot messages are validated before replacing data. Errors preserve the last valid snapshot. A native scan timeout shows a retry message after 15 seconds.

For the Mac integration:

1. Keep `PortScan`, `DeviceWatcher`, and `PowerMonitor` in Swift. Serialize `PortScan` into the version 1 schema, supplying the host name and physical port labels from macOS.
2. Bundle `dist/` as web resources and load its `index.html` using `loadFileURL(_:allowingReadAccessTo:)`, allowing access only to the bundled web directory. Test module loading on the target macOS version before switching the main window.
3. Handle `ready` with the current snapshot; handle `refresh` by calling the existing scan pipeline. Push updated snapshots from the device watcher. Expose only these defined messages.
4. Use WebKit's structured JavaScript arguments (`callAsyncJavaScript`) to send snapshot objects. Do not interpolate JSON or device names into JavaScript source strings.
5. Verify the native integration on macOS, including reconnects, refresh errors, keyboard access, and offline asset loading. The current browser tests simulate the message handler, but do not compile or launch a Mac host.

Live power and native menu commands can be added as versioned bridge events later. Once embedded, visual changes are made in the web components and CSS; rebuilding the web bundle updates the Mac interface without rewriting SwiftUI layouts.

## Offline release package

```bash
npm run package:orbit
```

This uses Python 3.10+ to regenerate and package the selected Orbit preview into `release/PortMap-Orbit-Preview-<version>.zip`, with opening instructions, image notices, a source manifest, and a SHA-256 sidecar. The HTML opens directly without a server. Node is needed for development and browser tests, but the packager itself has no Node dependency.

The `Publish Orbit preview` GitHub Actions workflow checks tags against `package.json`, runs the production build and browser suite, then publishes the ZIP and checksum as a prerelease. It uses GitHub's repository-scoped workflow token; no personal release token is committed. See [release notes](releases/orbit-preview-v0.1.0.md).

## Native Mac app integration

The chosen Orbit interface is now bundled into a `WKWebView` by `build.sh`. The native adapter uses the existing Swift device inventory and watcher, with a separate versioned `state` message for physical nodes, errors, demo status, and refresh state. The earlier React schema remains available for that browser UI. See [the macOS guide](../MACOS.md).

`npm test` regenerates the native bundle with Python before the browser checks. The native adapter tests simulate host messages; the macOS workflow separately compiles and smoke-tests the real app.
