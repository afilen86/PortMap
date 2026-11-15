import raw from "../../overview-scan.json";
import { fromWhatCable, type Snapshot } from "./model";
export type Scenario = "saved" | "empty" | "large" | "error";
export const scenarioLabels: Record<Scenario, string> = {
  saved: "Saved setup",
  empty: "Empty ports",
  large: "Large setup",
  error: "Scan error",
};
export function sample(scenario: Scenario): Snapshot {
  const scan = fromWhatCable(raw);
  // Host identity and physical positions aren't included in WhatCable's report.
  scan.host = "Mac mini";
  scan.capturedAt = "2026-11-15T12:00:00.000Z";
  if (scenario === "empty")
    scan.ports = scan.ports.map((p) => ({
      ...p,
      connected: false,
      description: "",
      children: [],
    }));
  if (scenario === "large")
    scan.ports[0].children.push({
      id: "sample-hub",
      name: "Studio expansion hub",
      detail: "Sample device · large setup",
      speed: "10 Gb/s",
      kind: "hub",
      children: Array.from({ length: 20 }, (_, i) => ({
        id: `sample-drive-${i}`,
        name: `Studio SSD ${i + 1}`,
        detail: "Sample device",
        speed: "10 Gb/s",
        kind: "drive" as const,
        children: [],
      })),
    });
  return scan;
}
