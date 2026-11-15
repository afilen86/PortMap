import { test, expect } from "@playwright/test";

const path = "/orbit/index.html";

test("approved light and dark themes preserve route, flow, and device visibility", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.emulateMedia({ colorScheme: "light" });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(path);
  await expect(page.locator("body")).toHaveAttribute("data-variant", "clay");
  await expect(
    page
      .getByRole("group", { name: "Appearance" })
      .getByRole("button", { name: "System" }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator("[role=tab]")).toHaveCount(0);
  await page
    .getByRole("combobox", { name: "Locate a device" })
    .selectOption("s4");
  await page.getByRole("button", { name: "Pause flow" }).click();
  await page.getByRole("button", { name: "Trace only" }).click();
  await page
    .getByRole("group", { name: "Appearance" })
    .getByRole("button", { name: "Dark", exact: true })
    .click();
  await expect(page.locator("body")).toHaveAttribute(
    "data-variant",
    "afterhours",
  );
  await expect(page.locator("#imagery-badge")).toHaveText("After Hours");
  await expect(page.locator(".device[data-id=s4]")).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await expect(
    page.getByRole("button", { name: "Animate flow" }),
  ).toHaveAttribute("aria-pressed", "false");
  await expect(page.locator("body")).toHaveClass(/focus-route/);
  await expect(page.locator(".edge.traced")).toHaveCount(2);
  for (const [appearance, variant] of [
    ["Light", "clay"],
    ["Dark", "afterhours"],
  ] as const) {
    await page
      .getByRole("group", { name: "Appearance" })
      .getByRole("button", { name: appearance, exact: true })
      .click();
    await expect(page.locator("body")).toHaveAttribute("data-variant", variant);
    await expect(page.locator(".device:visible")).toHaveCount(19);
    expect(
      await page
        .locator(".device")
        .evaluateAll((cards) =>
          cards.every((card) => getComputedStyle(card).opacity === "1"),
        ),
    ).toBe(true);
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
  }
  expect(errors).toEqual([]);
});

test("appearance preference survives reload and overrides system changes", async ({
  page,
}) => {
  await page.emulateMedia({ colorScheme: "light" });
  await page.goto(path);
  await page
    .getByRole("group", { name: "Appearance" })
    .getByRole("button", { name: "Dark", exact: true })
    .click();
  await page.reload();
  await expect(page.locator("body")).toHaveAttribute(
    "data-variant",
    "afterhours",
  );
  await expect(
    page
      .getByRole("group", { name: "Appearance" })
      .getByRole("button", { name: "Dark", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.emulateMedia({ colorScheme: "dark" });
  await page.emulateMedia({ colorScheme: "light" });
  await expect(page.locator("body")).toHaveAttribute(
    "data-variant",
    "afterhours",
  );
  await page
    .getByRole("group", { name: "Appearance" })
    .getByRole("button", { name: "Light", exact: true })
    .click();
  await page.reload();
  await expect(page.locator("body")).toHaveAttribute("data-variant", "clay");
});

test("System follows Mac appearance changes without losing the route", async ({
  page,
}) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await page.goto(path);
  await expect(page.locator("body")).toHaveAttribute(
    "data-variant",
    "afterhours",
  );
  await page
    .getByRole("combobox", { name: "Locate a device" })
    .selectOption("x1");
  await page.emulateMedia({ colorScheme: "light" });
  await expect(page.locator("body")).toHaveAttribute("data-variant", "clay");
  await expect(page.locator(".device[data-id=x1]")).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(page.locator("body")).toHaveAttribute(
    "data-variant",
    "afterhours",
  );
  await expect(page.locator("#route")).toContainText("Traktor X1 MK3");
});

test("standalone preview works with storage blocked and reduced motion", async ({
  browser,
}) => {
  const context = await browser.newContext({
    reducedMotion: "reduce",
    colorScheme: "light",
  });
  const page = await context.newPage();
  await page.addInitScript(() =>
    Object.defineProperty(window, "localStorage", {
      get() {
        throw new Error("Storage blocked");
      },
    }),
  );
  const { readFile } = await import("node:fs/promises");
  const html = await readFile("public/orbit/index.html", "utf8");
  const external: string[] = [];
  await page.route("**/*", (route) => {
    if (route.request().url() === "http://orbit.local/")
      return route.fulfill({ contentType: "text/html", body: html });
    external.push(route.request().url());
    return route.abort();
  });
  await page.goto("http://orbit.local/");
  await expect(page.locator(".device")).toHaveCount(19);
  await page
    .getByRole("group", { name: "Appearance" })
    .getByRole("button", { name: "Dark", exact: true })
    .click();
  await expect(page.locator("body")).toHaveAttribute(
    "data-variant",
    "afterhours",
  );
  expect(
    await page
      .locator(".pulse")
      .first()
      .evaluate((dot) => getComputedStyle(dot).display),
  ).toBe("none");
  expect(external).toEqual([]);
  await context.close();
});
