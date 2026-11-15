// Verify the actual ZIP contents and open the bundled document without asset access.
import { chromium } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
const web = new URL("../", import.meta.url);
const version = JSON.parse(
  readFileSync(new URL("package.json", web), "utf8"),
).version;
const archive = fileURLToPath(
  new URL(`release/PortMap-Orbit-Preview-${version}.zip`, web),
);
const checksum = readFileSync(`${archive}.sha256`, "utf8").split(/\s+/)[0];
if (
  createHash("sha256").update(readFileSync(archive)).digest("hex") !== checksum
)
  throw new Error("ZIP checksum mismatch");
const extracted = JSON.parse(
  execFileSync(
    "python3",
    [
      "-c",
      `
import hashlib, json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    assert z.testzip() is None
    prefix = 'PortMap-Orbit-Preview-' + sys.argv[2] + '/'
    assert set(z.namelist()) == {prefix + name for name in ['Port Map Orbit.html', 'README.txt', 'IMAGERY-NOTICES.txt', 'release.json']}
    manifest = json.loads(z.read(prefix + 'release.json'))
    html = z.read(prefix + manifest['entryPoint'])
    assert hashlib.sha256(html).hexdigest() == manifest['entryPointSha256']
    assert manifest['version'] == sys.argv[2]
    print(json.dumps({'html': html.decode(), 'manifest': manifest}))
`,
      archive,
      version,
    ],
    { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 },
  ),
);
if (process.env.CI && extracted.manifest.sourceDirty)
  throw new Error("Release source has uncommitted changes");
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || "/usr/bin/chromium",
  args: ["--no-sandbox"],
});
try {
  const page = await browser.newPage({
    viewport: { width: 1440, height: 900 },
    colorScheme: "light",
    reducedMotion: "reduce",
  });
  const errors = [],
    requests = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.route("**/*", (route) => {
    if (route.request().url() === "http://offline-preview.local/")
      return route.fulfill({ contentType: "text/html", body: extracted.html });
    requests.push(route.request().url());
    return route.abort();
  });
  await page.goto("http://offline-preview.local/");
  await page.locator("body[data-variant=clay] .device").first().waitFor();
  if ((await page.locator(".device:visible").count()) !== 19)
    throw new Error("Missing device images");
  await page
    .getByRole("combobox", { name: "Locate a device" })
    .selectOption("x1");
  await page
    .getByRole("group", { name: "Appearance" })
    .getByRole("button", { name: "Dark", exact: true })
    .click();
  await page
    .locator(
      "body[data-variant=afterhours] .device[data-id=x1][aria-pressed=true]",
    )
    .waitFor();
  if (requests.length || errors.length)
    throw new Error(JSON.stringify({ requests, errors }));
  console.log(
    `Verified package ${version}: checksum, manifest, 19 images, light/dark, selection, no external assets.`,
  );
} finally {
  await browser.close();
}
