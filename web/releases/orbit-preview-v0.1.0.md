# Workspace Orbit Preview 0.1.0

A downloadable, offline browser preview of Port Map's selected photo-led interface.

- **Light Mode:** Clay Studio, with warm terracotta/olive colors, compact peripherals, and a larger central Mac mini.
- **Dark Mode:** After Hours, with plum/rose colors and larger device portraits.
- **System:** follows macOS/browser appearance; explicit preferences persist locally.
- All 19 image cards remain visible while selecting and tracing device routes.
- Directional cable paths, illustrative flow animation, pause controls, and reduced motion support.

## Download and open

Download **PortMap-Orbit-Preview-0.1.0.zip**, extract it in Finder, then open **Port Map Orbit.html** in Safari or Chrome. No installation, server, or developer tools are needed.

The `.zip.sha256` file verifies the download. From the folder containing the ZIP and checksum:

```bash
shasum -a 256 -c PortMap-Orbit-Preview-0.1.0.zip.sha256
```

## Scope

This is a **preview prerelease**, not a signed or notarized macOS app installer. It uses the saved WhatCable report and manual connection list. Animation illustrates flow direction, not measured traffic. Generic artwork and manual links are labeled. The same `ingnok` display name is reported on two paths and is not deduplicated into a verified physical-screen count.

The native SwiftUI app and its build instructions remain in the repository. This release doesn't embed the web UI into the Mac app or provide live hardware access.

Validation: TypeScript/production build, browser interaction and responsive checks, standalone package opening, and checksums. Original artwork attribution is included in the package.
