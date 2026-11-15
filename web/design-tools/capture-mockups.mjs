// Capture the standalone document without requiring a development server.
import { chromium } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
const orbit = process.argv.includes("--orbit");
const appearance = process.argv.includes("--appearance");
const output = new URL(
  appearance
    ? "../public/orbit/"
    : orbit
      ? "../public/mockups/orbit/"
      : "../public/mockups/",
  import.meta.url,
);
const document = await readFile(new URL("index.html", output), "utf8");
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || "/usr/bin/chromium",
  args: ["--no-sandbox"],
});
try {
  const page = await browser.newPage({
    viewport: { width: 1600, height: 1050 },
    reducedMotion: "reduce",
  });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.route("**/*", (route) =>
    route.fulfill({ contentType: "text/html", body: document }),
  );
  for (const design of appearance
    ? ["light", "dark"]
    : orbit
      ? ["glacier", "afterhours", "clay"]
      : ["atlas", "signal", "orbit"]) {
    await page.goto(`http://portmap-design.local/#${design}`);
    if (appearance) {
      await page
        .getByRole("group", { name: "Appearance" })
        .getByRole("button", {
          name: design === "light" ? "Light" : "Dark",
          exact: true,
        })
        .click();
      await page
        .locator(
          `body[data-variant=${design === "light" ? "clay" : "afterhours"}] .device.selected`,
        )
        .waitFor();
    } else {
      await page
        .locator(
          `body[${orbit ? "data-variant" : "data-design"}=${design}] .device.selected`,
        )
        .waitFor();
    }
    await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() =>
      [...document.images].every(
        (image) => image.complete && image.naturalWidth,
      ),
    );
    await page.screenshot({
      path: fileURLToPath(new URL(`${design}.png`, output)),
      fullPage: true,
    });
    console.log(`Captured ${design}`);
  }
  if (errors.length) throw new Error(errors.join("\n"));
} finally {
  await browser.close();
}
