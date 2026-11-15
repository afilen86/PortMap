# Workspace Orbit: three iterations

Open `index.html` directly on your Mac, or visit `/mockups/orbit/index.html` in the development server. The HTML file contains its artwork and needs no installation or internet connection.

| Iteration   | Palette                                    | Spacing                             | Device imagery                                     |
| ----------- | ------------------------------------------ | ----------------------------------- | -------------------------------------------------- |
| Glacier     | Porcelain white, glacial blue, muted lilac | An airy, stretched ellipse          | Medium peripheral portraits; a slightly larger Mac |
| After Hours | Deep aubergine, rose, lilac                | Closer rows and tactile photo tiles | Oversized portraits, including the hubs            |
| Clay Studio | Warm chalk, terracotta, olive              | Small peripheral constellations     | Compact satellites around a much larger Mac        |

At the design canvas's native scale, standard peripheral portraits are 100, 132, and 74 pixels respectively. The Mac portraits are 136, 166, and 164 pixels. The whole canvas scales to fit a desktop window. Photo sizes, card dimensions, positions, and cable routes all change between studies; these are more than palette swaps.

All three preserve the original Orbit interaction model:

- All 19 image cards remain on screen at desktop sizes; no photo is hidden or faded when selecting a route.
- Click any device, or choose it from **Locate a device**, to highlight its complete ancestry.
- **Trace only** emphasizes that route's cables while retaining all images.
- **Pause flow** stops the illustrative movement. System reduced motion preferences are respected.
- Arrow keys switch between the three tabs, keeping the selection and pause state.

The original setup, photo provenance, representative images (`≈`), manual connections (`M`), and display-identity ambiguity remain documented in [the parent guide](../README.md). Flow direction is illustrative, not live telemetry. The original three concepts are preserved at `../index.html`.

## Develop

From the repository root:

```bash
python3 web/design-tools/build-orbit-variants.py
```

- Edit `web/design-tools/orbit-variants.css` for the themes and portrait presentation.
- Edit `web/design-tools/build-orbit-variants.py` for dimensions, positions, text, and scene metadata.
- The builder reuses the first mockup lab's renderer, source artwork, connection data, and cable router. Importing that library doesn't overwrite the original gallery.

Capture PNG previews and run the checks:

```bash
cd web
node design-tools/capture-mockups.mjs --orbit
npm test -- orbit-variants
```

`CHROMIUM_PATH` can override the default `/usr/bin/chromium` executable. Browser checks verify all images fit at 1440 × 900 and 1280 × 800, no cards overlap, routes remain selectable, themes differ in geometry and scale, keyboard navigation works, and the standalone file needs no external artwork.
