import { test, expect } from "@playwright/test";

test("saved report, selection, search, tree navigation and themes", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Your setup, connected." }),
  ).toBeVisible();
  await expect(page.locator(".summary-stat").first()).toContainText("5");
  await page
    .locator(".map-device")
    .filter({ hasText: "Mac Mini Stand & Hub" })
    .click();
  await expect(
    page
      .getByRole("complementary", { name: "Connection details" })
      .getByRole("heading", { name: "Mac Mini Stand & Hub", exact: true }),
  ).toBeVisible();
  await page.getByRole("textbox", { name: "Search devices" }).fill("P9227");
  await expect(page.locator(".map-port")).toHaveCount(1);
  await page
    .getByRole("textbox", { name: "Search devices" })
    .fill("not a real device");
  await expect(
    page.getByRole("heading", { name: "No matching connections" }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Clear search", exact: true })
    .last()
    .click();
  await page
    .getByRole("button", { name: "Connection tree", exact: true })
    .click();
  await page
    .locator(".tree-device")
    .filter({ hasText: "Expansion HDD" })
    .click();
  await expect(page.locator(".route-list")).toContainText("Expansion HDD");
  await expect(page.locator(".route-list")).toContainText("USB 2.0 Hub");
  await page
    .getByRole("button", { name: "Collapse USB2.0 Hub", exact: true })
    .first()
    .click();
  await expect(
    page.locator(".tree-device").filter({ hasText: "Expansion HDD" }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "Ports", exact: true }).click();
  await page.locator(".port-list-row").filter({ hasText: "USB-C 6" }).click();
  await expect(
    page.getByRole("complementary", { name: "Connection details" }),
  ).toContainText("Available");
  await page.getByRole("button", { name: "Dark appearance" }).click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await expect(
    page.getByRole("heading", { name: "A place for everything." }),
  ).toBeVisible();
  expect(errors).toEqual([]);
});

test("empty, large and error preview states", async ({ page }) => {
  await page.goto("/");
  await page.getByLabel("Preview state", { exact: true }).selectOption("empty");
  await expect(page.locator(".map-device")).toHaveCount(0);
  await expect(page.locator(".available-port")).toHaveCount(6);
  await page.getByLabel("Preview state", { exact: true }).selectOption("large");
  await page
    .getByRole("button", { name: "Connection tree", exact: true })
    .click();
  await expect(
    page.locator(".tree-device").filter({ hasText: "Studio SSD 20" }),
  ).toBeVisible();
  await page.getByLabel("Preview state", { exact: true }).selectOption("error");
  await expect(page.getByRole("alert")).toContainText(
    "WhatCable couldn’t complete",
  );
  await page.getByRole("button", { name: "Try again" }).click();
  await expect(
    page.getByRole("button", { name: "Refreshing…" }),
  ).toBeDisabled();
  await expect(page.getByRole("alert")).toBeVisible();
  await page.getByLabel("Preview state", { exact: true }).selectOption("saved");
  await expect(page.getByRole("alert")).toHaveCount(0);
});

test("imports raw WhatCable JSON and rejects malformed reports", async ({
  page,
}) => {
  await page.goto("/");
  await page.locator("input[type=file]").setInputFiles("../overview-scan.json");
  await expect(page.locator(".computer")).toContainText("This Mac");
  await page.locator("input[type=file]").setInputFiles({
    name: "invalid.json",
    mimeType: "application/json",
    buffer: Buffer.from('{"ports":null}'),
  });
  await expect(page.getByRole("alert")).toContainText(
    "isn’t a supported connection report",
  );
  await expect(page.locator(".computer")).toContainText("This Mac");
});

test("native bridge validates reports and handles refresh without sample controls", async ({
  page,
}) => {
  await page.addInitScript(() => {
    (window as any).nativeMessages = [];
    window.webkit = {
      messageHandlers: {
        portMap: {
          postMessage: (message) => {
            (window as any).nativeMessages.push(message);
          },
        },
      },
    };
  });
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Reading your connections" }),
  ).toBeVisible();
  const snapshot = {
    schemaVersion: 1,
    host: "Test Mac",
    source: "WhatCable test",
    capturedAt: "2026-11-15T12:00:00.000Z",
    ports: [
      {
        id: "test-port",
        name: "Test USB-C",
        group: "USB-C",
        connected: true,
        speed: "10 Gb/s",
        description: "Test",
        children: [],
      },
    ],
  };
  await page.evaluate(
    (data) => window.portMap!.receive({ type: "snapshot", snapshot: data }),
    snapshot,
  );
  await expect(page.locator(".computer")).toContainText("Test Mac");
  await expect(page.getByLabel("Preview state", { exact: true })).toHaveCount(
    0,
  );
  await page.getByRole("button", { name: "Refresh connections" }).click();
  expect(
    await page.evaluate(() =>
      (window as any).nativeMessages.some((m: any) => m.type === "refresh"),
    ),
  ).toBe(true);
  await page.evaluate(() =>
    window.portMap!.receive({ type: "snapshot", snapshot: {} }),
  );
  await expect(page.getByRole("alert")).toContainText("could not be read");
  await expect(page.locator(".computer")).toContainText("Test Mac");
  await page.evaluate(
    (data) => window.portMap!.receive({ type: "snapshot", snapshot: data }),
    { ...snapshot, ports: [] },
  );
  await expect(page.getByRole("alert")).toHaveCount(0);
});

for (const width of [1440, 920, 390])
  test(`fits ${width}px and captures preview`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.goto("/");
    await expect(
      page.getByRole("heading", { name: "Connection map", exact: true }),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      path: `test-results/overview-${width}.png`,
      fullPage: true,
    });
    await page
      .getByRole("button", { name: "Connection tree", exact: true })
      .click();
    await page
      .getByLabel("Preview state", { exact: true })
      .selectOption("large");
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  });

test("native timeout offers retry and duplicate IDs preserve the last snapshot", async ({
  page,
}) => {
  await page.clock.install();
  await page.addInitScript(() => {
    window.webkit = { messageHandlers: { portMap: { postMessage: () => {} } } };
  });
  await page.goto("/");
  await page.clock.fastForward(16000);
  await expect(page.getByRole("alert")).toContainText(
    "hasn’t sent a connection report",
  );
  await expect(
    page.getByRole("heading", { name: "No connection report yet" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Try again" }).click();
  await expect(
    page.getByRole("button", { name: "Refreshing…" }),
  ).toBeDisabled();
  const port = {
    id: "same-id",
    name: "USB-C",
    group: "USB",
    connected: false,
    speed: "10 Gb/s",
    description: "",
    children: [],
  };
  const scan = {
    schemaVersion: 1,
    host: "Retained Mac",
    source: "test",
    capturedAt: "2026-11-15T12:00:00.000Z",
    ports: [port],
  };
  await page.evaluate(
    (snapshot) => window.portMap!.receive({ type: "snapshot", snapshot }),
    scan,
  );
  await page.evaluate(
    (snapshot) => window.portMap!.receive({ type: "snapshot", snapshot }),
    { ...scan, host: "Invalid Mac", ports: [port, port] },
  );
  await expect(page.getByRole("alert")).toContainText("could not be read");
  await expect(page.locator(".computer")).toContainText("Retained Mac");
});
