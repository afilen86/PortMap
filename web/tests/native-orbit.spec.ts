import { test, expect, type Page } from "@playwright/test";
import { readFile } from "node:fs/promises";

async function openNative(page: Page) {
  const html = await readFile("native/dist/index.html", "utf8");
  await page.addInitScript(() => {
    (window as any).nativeMessages = [];
    window.webkit = {
      messageHandlers: {
        portMap: {
          postMessage: (message) =>
            (window as any).nativeMessages.push(message),
        },
      },
    };
  });
  await page.route("http://native.local/", (route) =>
    route.fulfill({ contentType: "text/html", body: html }),
  );
  await page.goto("http://native.local/");
  await expect
    .poll(() =>
      page.evaluate(() =>
        (window as any).nativeMessages.some((m: any) => m.type === "ready"),
      ),
    )
    .toBe(true);
}
type NativeFixture = {
  nodes: {
    id: string;
    name: string;
    parent?: string;
    image: string;
    kind: string;
    wire: string;
    speed: string;
    slot?: string;
    generic?: boolean;
  }[];
  source: string;
  connectedPorts: number;
  totalPorts: number;
  capturedAt: string;
};
async function fixture(page: Page) {
  return page.evaluate<NativeFixture>(
    `({nodes:savedScene.nodes.map(n=>({...n,id:'live-'+n.id,parent:n.parent?'live-'+n.parent:undefined,slot:n.id})),source:'WhatCable test',connectedPorts:5,totalPorts:6,capturedAt:'2026-11-15T12:00:00Z'})`,
  );
}
async function state(page: Page, event: object) {
  await page.evaluate(
    (event) =>
      window.portMap!.receive({ type: "state", schemaVersion: 1, ...event }),
    event,
  );
}

test("native boot never presents saved peripherals as detected hardware", async ({
  page,
}) => {
  await openNative(page);
  await expect(page.locator(".device")).toHaveCount(1);
  await expect(page.locator(".native-status")).toContainText(
    "Reading this Mac",
  );
  await state(page, {
    refreshing: false,
    error: "Install WhatCable in Applications, then click Refresh.",
  });
  await expect(page.locator(".native-status.error")).toContainText(
    "Install WhatCable",
  );
  await page.getByRole("button", { name: "Show demo setup" }).click();
  expect(
    await page.evaluate(() => (window as any).nativeMessages.at(-1).type),
  ).toBe("demo");
  await state(page, { demo: true, refreshing: false });
  await expect(page.locator(".device")).toHaveCount(19);
  await expect(page.locator(".native-status")).toContainText("Demo setup");
});

test("live topology routes correctly and survives appearance, refresh errors, and reconnects", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await openNative(page);
  const snapshot = await fixture(page);
  await state(page, { snapshot, refreshing: false });
  await expect(page.locator(".device")).toHaveCount(19);
  await expect(page.locator(".native-status")).toContainText(
    "5 of 6 ports connected",
  );
  await page.locator(".device[data-id=live-scarlett]").click();
  await expect(page.locator(".edge.traced")).toHaveCount(4);
  await expect(page.locator("#route")).toContainText("CalDigit Element Hub");
  await expect(page.locator("#route")).toContainText("MaestroDMX");
  for (const appearance of ["Light", "Dark"]) {
    await page
      .getByRole("group", { name: "Appearance" })
      .getByRole("button", { name: appearance, exact: true })
      .click();
    await expect(
      page.locator(".device[data-id=live-scarlett]"),
    ).toHaveAttribute("aria-pressed", "true");
    for (const viewport of [
      { width: 1440, height: 900 },
      { width: 1280, height: 800 },
    ]) {
      await page.setViewportSize(viewport);
      await expect
        .poll(() =>
          page.locator(".device").evaluateAll((cards) =>
            cards.every((card) => {
              const r = card.getBoundingClientRect();
              return (
                r.left >= 0 &&
                r.right <= innerWidth &&
                r.top >= 0 &&
                r.bottom <= innerHeight
              );
            }),
          ),
        )
        .toBe(true);
    }
  }
  await page
    .getByRole("button", { name: "Refresh connections", exact: true })
    .click();
  expect(
    await page.evaluate(() => (window as any).nativeMessages.at(-1).type),
  ).toBe("refresh");
  await state(page, {
    snapshot,
    refreshing: false,
    error: "WhatCable could not complete the scan.",
  });
  await expect(page.locator(".native-status.error")).toContainText(
    "could not complete",
  );
  await expect(page.locator(".device")).toHaveCount(19);
  await state(page, {
    snapshot: {
      ...snapshot,
      nodes: snapshot.nodes.filter((n: any) => n.id !== "live-scarlett"),
    },
    refreshing: false,
  });
  await expect(page.locator(".device")).toHaveCount(18);
  await expect(page.locator(".native-status.error")).toHaveCount(0);
  await expect(page.locator(".device[aria-pressed=true]")).toHaveCount(1);
  expect(errors).toEqual([]);
});

test("unknown devices use a representative fallback; extra devices all remain in the layout", async ({
  page,
}) => {
  await openNative(page);
  const snapshot = await fixture(page);
  snapshot.nodes.push({
    id: "unknown",
    name: "<img src=x onerror=alert(1)>",
    image: "unknown",
    kind: "device",
    wire: "USB",
    speed: "",
    parent: "live-element",
    generic: true,
  });
  for (let i = 0; i < 8; i++)
    snapshot.nodes.push({
      id: `extra-${i}`,
      name: `Extra drive ${i + 1}`,
      image: "nvme",
      kind: "storage",
      wire: "USB",
      speed: "10 Gb/s",
      parent: "live-satechi",
      generic: true,
    });
  await state(page, { snapshot, refreshing: false });
  await expect(page.locator(".device")).toHaveCount(28);
  await expect(page.locator(".photo")).toHaveCount(28);
  await expect(page.locator(".edge")).toHaveCount(27);
  await expect(page.locator(".device[data-id=unknown] .photo svg")).toHaveCount(
    1,
  );
  await expect(page.locator(".device[data-id=unknown] img")).toHaveCount(0);
  await page.locator(".device[data-id=extra-7]").click();
  await expect(page.locator("#route")).toContainText("Extra drive 8");
});

test("invalid cyclic reports preserve the last valid live setup", async ({
  page,
}) => {
  await openNative(page);
  const snapshot = await fixture(page);
  await state(page, { snapshot, refreshing: false });
  const broken = JSON.parse(JSON.stringify(snapshot));
  broken.nodes[1].parent = broken.nodes[1].id;
  await state(page, { snapshot: broken, refreshing: false });
  await expect(page.locator(".native-status.error")).toContainText(
    "Invalid cable topology",
  );
  await expect(page.locator(".device")).toHaveCount(19);
});

for (const count of [19, 20, 21, 28, 40]) {
  test(`${count} live devices preserve the demo orbit with the Mac centered in both themes`, async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await openNative(page);
    const snapshot = await fixture(page);
    while (snapshot.nodes.length < count)
      snapshot.nodes.push({
        id: `additional-${snapshot.nodes.length}`,
        name: `Additional device ${snapshot.nodes.length}`,
        image: "nvme",
        kind: "storage",
        wire: "USB",
        speed: "10 Gb/s",
        parent: "live-element",
        generic: true,
      });
    // Live reports need not list their host first.
    snapshot.nodes.reverse();
    await state(page, { snapshot, refreshing: false });
    for (const name of ["Light", "Dark"]) {
      await page
        .getByRole("group", { name: "Appearance" })
        .getByRole("button", { name, exact: true })
        .click();
      await expect(page.locator(".device")).toHaveCount(count);
      const shape = await page.evaluate(() => {
        const stage = document
          .querySelector(".stage-wrap")!
          .getBoundingClientRect();
        const host = document
          .querySelector(".device[data-id=live-mac]")!
          .getBoundingClientRect();
        const rings = document
          .querySelector(".orbit-rings")!
          .getBoundingClientRect();
        return {
          dx: host.left + host.width / 2 - stage.left - stage.width / 2,
          dy: host.top + host.height / 2 - stage.top - stage.height / 2,
          ringDx: rings.left + rings.width / 2 - host.left - host.width / 2,
          ringDy: rings.top + rings.height / 2 - host.top - host.height / 2,
        };
      });
      expect(Math.abs(shape.dx)).toBeLessThan(1);
      expect(Math.abs(shape.dy)).toBeLessThan(1);
      expect(Math.abs(shape.ringDx)).toBeLessThan(1);
      expect(Math.abs(shape.ringDy)).toBeLessThan(1);
      const relativeToDemo = await page.evaluate(`(() => {
        const host=DATA.layouts[design]['live-mac'];
        return ['satechi','element','s4','display12','speakers'].map(slot=>({
          actual:DATA.layouts[design]['live-'+slot][0]-host[0],
          expected:savedScene.layouts[design][slot][0]-(1560-savedScene.sizes[design].mac.width)/2
        }));
      })()`);
      for (const point of relativeToDemo as {
        actual: number;
        expected: number;
      }[])
        expect(point.actual).toBe(point.expected);
      await expect(page.locator(".edge")).toHaveCount(count - 1);
      expect(
        await page.locator(".device").evaluateAll((cards) =>
          cards.every((card) => {
            const r = card.getBoundingClientRect();
            return (
              r.left >= 0 &&
              r.right <= innerWidth &&
              r.top >= 0 &&
              r.bottom <= innerHeight
            );
          }),
        ),
      ).toBe(true);
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
            .map((other) => other.getAttribute("data-id"));
        }),
      );
      expect(overlaps).toEqual([]);
    }
    if (count === 21)
      await page.screenshot({
        path: "test-results/live-centered-orbit.png",
        fullPage: true,
      });
  });
}
