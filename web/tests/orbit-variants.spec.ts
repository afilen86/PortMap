import { test, expect } from "@playwright/test";

const variants = ["glacier", "afterhours", "clay"] as const;
for (const variant of variants) {
  test(`${variant} keeps every portrait visible with trace and flow controls`, async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(`/mockups/orbit/index.html#${variant}`);
    await expect(page.locator("body")).toHaveAttribute("data-variant", variant);
    await expect(page.locator(".device")).toHaveCount(19);
    await expect(page.locator(".photo[role=img]")).toHaveCount(19);
    await expect(page.locator(".edge")).toHaveCount(18);
    for (const viewport of [
      { width: 1440, height: 900 },
      { width: 1280, height: 800 },
    ]) {
      await page.setViewportSize(viewport);
      await expect
        .poll(async () =>
          page.locator(".device").evaluateAll((cards) =>
            cards.every((card) => {
              const rect = card.getBoundingClientRect();
              return (
                rect.left >= 0 &&
                rect.right <= innerWidth &&
                rect.top >= 0 &&
                rect.bottom <= innerHeight
              );
            }),
          ),
        )
        .toBe(true);
    }
    const overlaps = await page.locator(".device").evaluateAll((cards) =>
      cards.flatMap((card, i) => {
        const a = card.getBoundingClientRect();
        return cards
          .slice(i + 1)
          .filter((other) => {
            const b = other.getBoundingClientRect();
            return (
              a.left < b.right &&
              b.left < a.right &&
              a.top < b.bottom &&
              b.top < a.bottom
            );
          })
          .map(
            (other) =>
              `${card.getAttribute("data-id")}/${other.getAttribute("data-id")}`,
          );
      }),
    );
    expect(overlaps).toEqual([]);
    await page.locator(".device[data-id=scarlett]").click();
    await expect(page.locator("#route")).toContainText("Mac mini");
    await expect(page.locator("#route")).toContainText("Traktor S4 MK3");
    await expect(page.locator("#route")).toContainText("MaestroDMX");
    await expect(page.locator(".edge.traced")).toHaveCount(4);
    await page.getByRole("button", { name: "Trace only" }).click();
    expect(
      await page
        .locator(".device")
        .evaluateAll((cards) =>
          cards.every((card) => getComputedStyle(card).opacity === "1"),
        ),
    ).toBe(true);
    await page.getByRole("button", { name: "Pause flow" }).click();
    await expect(page.locator("body")).toHaveClass(/paused/);
    await page
      .getByRole("combobox", { name: "Locate a device" })
      .selectOption("x1");
    await expect(page.locator(".device[data-id=x1]")).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    expect(errors).toEqual([]);
  });
}

test("themes differ in palette, device spacing, and portrait scale", async ({
  page,
}) => {
  const metrics: {
    background: string;
    portrait: number;
    hostPortrait: number;
    width: number;
    x: number;
    y: number;
  }[] = [];
  for (const variant of variants) {
    await page.goto(`/mockups/orbit/index.html#${variant}`);
    await expect(page.locator("body")).toHaveAttribute("data-variant", variant);
    metrics.push(
      await page.evaluate(() => {
        const card = document.querySelector<HTMLElement>(
          ".device[data-id=expansion]",
        )!;
        const host = document.querySelector<HTMLElement>(
          ".device[data-id=mac]",
        )!;
        return {
          background: getComputedStyle(document.body).backgroundColor,
          portrait: parseFloat(card.style.getPropertyValue("--portrait-size")),
          hostPortrait: parseFloat(
            host.style.getPropertyValue("--portrait-size"),
          ),
          width: parseFloat(card.style.width),
          x: parseFloat(card.style.left),
          y: parseFloat(card.style.top),
        };
      }),
    );
  }
  expect(new Set(metrics.map((m) => m.background)).size).toBe(3);
  expect(metrics[1].portrait).toBeGreaterThan(metrics[0].portrait);
  expect(metrics[0].portrait).toBeGreaterThan(metrics[2].portrait);
  expect(metrics[2].hostPortrait / metrics[2].portrait).toBeGreaterThan(2);
  expect(new Set(metrics.map((m) => `${m.x},${m.y}`)).size).toBe(3);
});

test("keyboard switches themes while preserving selection and paused flow", async ({
  page,
}) => {
  await page.goto("/mockups/orbit/index.html");
  await page
    .getByRole("combobox", { name: "Locate a device" })
    .selectOption("s4");
  await page.getByRole("button", { name: "Pause flow" }).click();
  await page.getByRole("tab", { name: "01 · Glacier" }).focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.locator("body")).toHaveAttribute(
    "data-variant",
    "afterhours",
  );
  await expect(page.locator(".device[data-id=s4]")).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await expect(
    page.getByRole("button", { name: "Animate flow" }),
  ).toHaveAttribute("aria-pressed", "false");
  await page.keyboard.press("End");
  await expect(page.locator("body")).toHaveAttribute("data-variant", "clay");
});

test("Orbit standalone gallery bundles its artwork and respects reduced motion", async ({
  browser,
}) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  const { readFile } = await import("node:fs/promises");
  const html = await readFile("public/mockups/orbit/index.html", "utf8");
  const external: string[] = [];
  await page.route("**/*", (route) => {
    if (route.request().url() === "http://orbit.local/")
      return route.fulfill({ contentType: "text/html", body: html });
    external.push(route.request().url());
    return route.abort();
  });
  await page.goto("http://orbit.local/");
  await expect(page.locator(".device")).toHaveCount(19);
  expect(
    await page
      .locator(".pulse")
      .first()
      .evaluate((dot) => getComputedStyle(dot).display),
  ).toBe("none");
  await page.getByRole("tab", { name: "02 · After Hours" }).click();
  expect(
    await page
      .locator(".photo img")
      .evaluateAll((images) =>
        images.every(
          (image) =>
            (image as HTMLImageElement).complete &&
            (image as HTMLImageElement).naturalWidth > 0,
        ),
      ),
  ).toBe(true);
  expect(external).toEqual([]);
  await context.close();
});
