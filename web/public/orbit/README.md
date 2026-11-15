# Workspace Orbit: approved appearance pairing

Open `index.html` directly on your Mac, or visit `/orbit/index.html` in the development server.

- **Light:** Clay Studio (option 3), including its terracotta and olive palette, compact device images, and larger central Mac.
- **Dark:** After Hours (option 2), including its plum and rose palette and larger device portraits.
- **System:** follows the Mac/browser appearance. This is the default until an explicit preference is chosen.

The Light / Dark / System controls replace the design-study tabs. The selected preference persists locally where browser storage is available. Switching appearance keeps the selected route, trace setting, and flow-pause state. All 19 image cards remain visible in either mode at desktop sizes.

This is the selected **browser design preview**. It uses the saved setup and manual connection list; it does not scan hardware or replace the Mac app's SwiftUI window. Animation illustrates direction rather than measured traffic. Representative artwork is marked `≈`, manual links `M`; full provenance and topology notes are in [the mockup guide](../mockups/README.md).

The original [three iterations](../mockups/orbit/index.html) remain available for comparison.

## Rebuild

From the repository root:

```bash
python3 web/design-tools/build-orbit-appearance.py
```

The builder shares the approved study geometry and CSS. It bundles the two chosen layouts and original artwork into one HTML file, without overwriting the earlier galleries.

Capture previews and test:

```bash
cd web
node design-tools/capture-mockups.mjs --appearance
npm test -- orbit-appearance
```

Appearance tests cover persistence, system changes, selection and pause preservation, all images fitting at desktop sizes, reduced motion, and blocked local storage. `CHROMIUM_PATH` overrides the default `/usr/bin/chromium` for captures and tests.
