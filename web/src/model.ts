import { z } from "zod";
export type Device = {
  id: string;
  name: string;
  detail: string;
  speed?: string;
  kind: "hub" | "drive" | "display" | "device";
  children: Device[];
};
const deviceSchema: z.ZodType<Device> = z.lazy(() =>
  z.object({
    id: z.string(),
    name: z.string(),
    detail: z.string(),
    speed: z.string().optional(),
    kind: z.enum(["hub", "drive", "display", "device"]),
    children: z.array(deviceSchema),
  }),
);
export const snapshotSchema = z
  .object({
    schemaVersion: z.literal(1),
    host: z.string(),
    source: z.string(),
    capturedAt: z.string().datetime(),
    ports: z.array(
      z.object({
        id: z.string(),
        name: z.string(),
        group: z.string(),
        connected: z.boolean(),
        speed: z.string(),
        cable: z.string().optional(),
        description: z.string(),
        children: z.array(deviceSchema),
      }),
    ),
  })
  .superRefine((scan, ctx) => {
    const ids = new Set<string>();
    const check = (id: string) => {
      if (ids.has(id))
        ctx.addIssue({ code: "custom", message: `Duplicate ID: ${id}` });
      ids.add(id);
    };
    const walk = (device: Device) => {
      check(device.id);
      device.children.forEach(walk);
    };
    scan.ports.forEach((port) => {
      check(port.id);
      port.children.forEach(walk);
    });
  });
export type Snapshot = z.infer<typeof snapshotSchema>;
export type Port = Snapshot["ports"][number];
export function flatten(devices: Device[]): Device[] {
  return devices.flatMap((device) => [device, ...flatten(device.children)]);
}
export function findRoute(port: Port, id: string): Device[] {
  function walk(devices: Device[]): Device[] {
    for (const device of devices) {
      if (device.id === id) return [device];
      const path = walk(device.children);
      if (path.length) return [device, ...path];
    }
    return [];
  }
  return walk(port.children);
}
const usbSchema = z.object({
  name: z.string().optional(),
  vendorName: z.string().optional(),
  speed: z.string().optional(),
  locationID: z.string().optional(),
  children: z.array(z.unknown()).optional(),
});
const reportSchema = z.object({
  version: z.string().optional(),
  ports: z.array(
    z.object({
      name: z.string(),
      connectionActive: z.boolean(),
      headline: z.string().optional(),
      devices: z.array(z.unknown()).optional(),
      thunderboltSwitchIndex: z.number().optional(),
      transports: z
        .object({
          usb3Speed: z.string().optional(),
          active: z.array(z.string()).optional(),
        })
        .optional(),
      cable: z.object({ speed: z.string().optional() }).optional(),
      dataLink: z.object({ detail: z.string().optional() }).optional(),
    }),
  ),
  builtInDisplayPorts: z
    .array(
      z.object({
        name: z.string(),
        displays: z
          .array(
            z.object({
              monitorName: z.string(),
              currentMode: z
                .object({
                  width: z.number(),
                  height: z.number(),
                  refreshHz: z.number(),
                })
                .optional(),
            }),
          )
          .optional(),
      }),
    )
    .optional(),
  thunderboltSwitches: z
    .array(
      z.object({
        index: z.number(),
        parentSwitchIndex: z.number().optional(),
        modelName: z.string().optional(),
        vendorName: z.string().optional(),
      }),
    )
    .optional(),
});
export function fromWhatCable(input: unknown): Snapshot {
  const raw = reportSchema.parse(input);
  function device(
    input: unknown,
    prefix: string,
    index: number,
    depth = 0,
  ): Device {
    if (depth > 32) throw new Error("Device tree is too deep");
    const d = usbSchema.parse(input);
    const id = `${prefix}/${d.locationID ?? index}`;
    const children = (d.children ?? []).map((child, i) =>
      device(child, id, i, depth + 1),
    );
    const name = d.name || "Unnamed USB device";
    return {
      id,
      name,
      detail: d.vendorName ?? "USB device",
      speed: d.speed,
      kind: children.length
        ? "hub"
        : /disk|storage|hdd|ssd|slim|246x/i.test(name)
          ? "drive"
          : "device",
      children,
    };
  }
  const ports: Port[] = raw.ports.map((p, i) => {
    const children = (p.devices ?? []).map((d, j) => device(d, p.name, j));
    const downstream = (raw.thunderboltSwitches ?? []).filter(
      (s) =>
        s.parentSwitchIndex === p.thunderboltSwitchIndex &&
        p.thunderboltSwitchIndex !== undefined,
    );
    const switchNode = (
      s: NonNullable<typeof raw.thunderboltSwitches>[number],
      seen: Set<number>,
    ): Device => {
      if (seen.has(s.index)) throw new Error("Cyclic Thunderbolt topology");
      const next = new Set([...seen, s.index]);
      return {
        id: `${p.name}/switch-${s.index}`,
        name: s.modelName || "Thunderbolt device",
        detail: s.vendorName || "Thunderbolt / USB4",
        kind: /246x|ssd/i.test(s.modelName || "") ? "drive" : "hub",
        children: (raw.thunderboltSwitches ?? [])
          .filter((child) => child.parentSwitchIndex === s.index)
          .map((child) => switchNode(child, next)),
      };
    };
    const switches = downstream.map((s) => switchNode(s, new Set()));
    if (switches.length === 1) switches[0].children.push(...children);
    else switches.push(...children);
    return {
      id: p.name,
      name: `USB-C ${p.name.split("@")[1] ?? i + 1}`,
      group: "USB-C & Thunderbolt",
      connected: p.connectionActive,
      speed:
        p.transports?.usb3Speed ||
        (p.transports?.active?.includes("CIO")
          ? "Thunderbolt / USB4"
          : p.transports?.active?.includes("USB2")
            ? "USB 2 · 480 Mb/s"
            : "USB-C"),
      cable: p.cable?.speed,
      description: p.dataLink?.detail || p.headline || "",
      children: switches,
    };
  });
  for (const p of raw.builtInDisplayPorts ?? [])
    ports.push({
      id: p.name,
      name: "HDMI",
      group: "Display",
      connected: !!p.displays?.length,
      speed: "HDMI",
      description: "Built-in display connection",
      children: (p.displays ?? []).map((d, i) => ({
        id: `${p.name}/display-${i}`,
        name: d.monitorName,
        detail: d.currentMode
          ? `${d.currentMode.width} × ${d.currentMode.height} · ${d.currentMode.refreshHz} Hz`
          : "Display",
        kind: "display",
        children: [],
      })),
    });
  return snapshotSchema.parse({
    schemaVersion: 1,
    host: "This Mac",
    source: `WhatCable ${raw.version ?? ""}`.trim(),
    capturedAt: new Date().toISOString(),
    ports,
  });
}
