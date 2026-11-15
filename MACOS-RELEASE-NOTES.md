# Port Map 1.5 — Workspace Orbit beta

A native macOS window for the selected Workspace Orbit interface.

- Clay Studio in Light Mode; After Hours in Dark Mode; System appearance follows macOS.
- Live WhatCable hardware discovery and automatic refresh when devices change.
- Device images stay visible while tracing cable routes; larger setups receive an expanded layout.
- Manual audio connections and representative images remain labeled.
- Explicit demo mode when the helper is unavailable; refresh returns to live scanning.
- Original SwiftUI view available in the Appearance & View menu.

## Install

Download the app ZIP, extract it in Finder, and move **Port Map.app** into Applications. Requires macOS 14+. The universal build supports Apple silicon and Intel Macs.

This testing build is ad-hoc signed and not notarized. macOS may require **Open Anyway** under **System Settings → Privacy & Security** when opening the downloaded app.

For live data, install WhatCable in Applications or its Homebrew helper. Without it, use **Show demo setup**. Animated flow illustrates direction, not measured traffic.

## Validation

The macOS build compiles both architectures, verifies the app signature, and launches the real bundled WebKit interface. The smoke check exercises both appearances, all 19 demo images, and a native Swift inventory fixture. Browser tests also cover live updates, errors, reconnects, unknown devices, and layout overflow.
