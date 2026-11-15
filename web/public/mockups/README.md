# Port Map: three visual directions

Open `index.html` directly in Safari or Chrome. It is self-contained, including all images, fonts (system), styles, and scripts; no installation or server is required. In the development server, use `/mockups/index.html`.

1. **Connection Atlas:** a light hierarchical map, with devices arranged by connection depth.
2. **Signal Desk:** a dark studio patchbay, with separate storage, control, and display shelves.
3. **Workspace Orbit:** a warm spatial view centered on the Mac, with peripheral photos around it.

All three use the same 19 image cards and 18 connections. Choosing a device highlights its ancestry without hiding or fading any photos. **Trace only** reduces the emphasis on unrelated cables. **Locate a device** selects without filtering the map. **Pause flow** stops the illustrative motion; reduced motion settings are respected. Arrow keys switch between the design tabs.

The canvas fits a desktop window so every image remains visible. A wide window is recommended for readable names and cable details. On a phone, the entire canvas is still visible, but labels are small.

## What the imagery and flow mean

- Photos and existing illustrations come from `port-map-source/Resources/`. Exact hardware photos are used where available; `≈` marks representative artwork (generic screens, Ethernet adapters, and SSD enclosures).
- Topology and reported link rates follow the saved `overview-scan.json`, with internal USB interfaces condensed into dotted paths. Cards correspond to reported physical-device paths, not a count of unique verified enclosures.
- Klipsch The Fives, MaestroDMX, and Scarlett 4i4 follow the manually entered connections in `ManualConnections.json` and have an `M` badge. Manual routes are dashed.
- USB and Thunderbolt arrows show bidirectional data capability. Display and analog audio arrows point toward the receiving device. Dots illustrate these directions; they do not measure actual traffic, utilization, or throughput.
- The saved scan reports the same `ingnok` display name on two paths (USB-C and HDMI). Both are shown and labeled by path; this mockup doesn't assume they are distinct physical screens.
- These mockups don't scan the Mac or replace the production app. The currently saved scan doesn't include a MIDI Fighter Twister, so its artwork is not added as a connected device.

## Rebuild

From the repository root:

```bash
python3 web/design-tools/build-mockups.py
```

Edit `web/design-tools/mockups.template.html` for visual design and interactions, or `build-mockups.py` for card positions and connection data. The generator embeds the original artwork, routes cables around image cards, and writes `web/public/mockups/index.html`. It requires only Python's standard library and doesn't alter source images.

To regenerate the three PNG previews after installing the web dependencies:

```bash
cd web
node design-tools/capture-mockups.mjs
npm test -- mockups
```

Set `CHROMIUM_PATH` if Chromium is installed somewhere other than `/usr/bin/chromium`.
