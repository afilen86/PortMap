import { test, expect } from "@playwright/test";

const designs = ["atlas", "signal", "orbit"] as const;

for (const design of designs) {
  test(`${design}: all images stay visible and every endpoint has a route`, async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(`/mockups/index.html#${design}`);
    await expect(page.locator("body")).toHaveAttribute("data-design", design);
    await expect(page.locator(".device")).toHaveCount(19);
    await expect(page.locator(".photo[role=img]")).toHaveCount(19);
    await expect(page.locator(".edge")).toHaveCount(18);
    const clipped = await page.locator(".device").evaluateAll((cards) =>
      cards
        .filter((card) => {
          const rect = card.getBoundingClientRect();
          return (
            rect.left < 0 ||
            rect.right > innerWidth ||
            rect.top < 0 ||
            rect.bottom > innerHeight
          );
        })
        .map((card) => card.getAttribute("data-id")),
    );
    expect(clipped).toEqual([]);
    const brokenImages = await page
      .locator(".photo img")
      .evaluateAll(
        (images) =>
          images.filter(
            (image) =>
              !(image as HTMLImageElement).complete ||
              !(image as HTMLImageElement).naturalWidth,
          ).length,
      );
    expect(brokenImages).toBe(0);
    await page.locator(".device[data-id=scarlett]").click();
    await expect(page.locator("#route")).toContainText("Mac mini");
    await expect(page.locator("#route")).toContainText("CalDigit Element Hub");
    await expect(page.locator("#route")).toContainText("Traktor S4 MK3");
    await expect(page.locator("#route")).toContainText("MaestroDMX");
    await expect(page.locator("#route")).toContainText("Scarlett 4i4");
    await expect(page.locator(".edge.traced")).toHaveCount(4);
    await page.getByRole("button", { name: "Trace only" }).click();
    await expect(page.locator("body")).toHaveClass(/focus-route/);
    await expect(page.locator(".device:visible")).toHaveCount(19);
    const minOpacity = await page
      .locator(".device")
      .evaluateAll((cards) =>
        Math.min(
          ...cards.map((card) => Number(getComputedStyle(card).opacity)),
        ),
      );
    expect(minOpacity).toBe(1);
    await page.getByRole("button", { name: "Pause flow" }).click();
    await expect(
      page.getByRole("button", { name: "Animate flow" }),
    ).toHaveAttribute("aria-pressed", "false");
    await page.getByRole("button", { name: "Animate flow" }).click();
    await expect(
      page.getByRole("button", { name: "Pause flow" }),
    ).toHaveAttribute("aria-pressed", "true");
    await page
      .getByRole("combobox", { name: "Locate a device" })
      .selectOption("x1");
    await expect(page.locator(".device[data-id=x1]")).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(page.locator("#route")).toContainText("Traktor X1 MK3");
    await page.setViewportSize({ width: 1280, height: 800 });
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
    expect(errors).toEqual([]);
  });
}

test("design tabs work with keyboard and preserve selected device", async ({
  page,
}) => {
  await page.goto("/mockups/index.html");
  await page.locator(".device[data-id=nvme]").click();
  await page.getByRole("tab", { name: "01 · Connection Atlas" }).focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.locator("body")).toHaveAttribute("data-design", "signal");
  await expect(page.locator(".device[data-id=nvme]")).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await expect(
    page.getByRole("tab", { name: "02 · Signal Desk" }),
  ).toBeFocused();
  await page.keyboard.press("End");
  await expect(page.locator("body")).toHaveAttribute("data-design", "orbit");
  await page.keyboard.press("Home");
  await expect(page.locator("body")).toHaveAttribute("data-design", "atlas");
});

test("reduced motion and standalone document have no asset dependencies", async ({
  browser,
}) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  const { readFile } = await import("node:fs/promises");
  const html = await readFile("public/mockups/index.html", "utf8");
  const extraRequests: string[] = [];
  await page.route("**/*", (route) => {
    if (route.request().url() === "http://mockups.local/")
      return route.fulfill({ contentType: "text/html", body: html });
    extraRequests.push(route.request().url());
    return route.abort();
  });
  await page.goto("http://mockups.local/");
  await expect(page.locator(".device")).toHaveCount(19);
  await expect(page.locator("body")).toHaveClass(/no-animation/);
  expect(
    await page
      .locator(".pulse")
      .first()
      .evaluate((dot) => getComputedStyle(dot).display),
  ).toBe("none");
  await page.getByRole("tab", { name: "03 · Workspace Orbit" }).click();
  await expect(page.locator(".device")).toHaveCount(19);
  expect(extraRequests).toEqual([]);
  await context.close();
});
