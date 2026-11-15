import type { ReactNode } from "react";
import { HardDrive, Monitor, Network, Usb } from "lucide-react";
import type { Device } from "./model";

export function DeviceIcon({
  kind,
  size = 19,
}: {
  kind: Device["kind"];
  size?: number;
}) {
  const Icon =
    kind === "hub"
      ? Network
      : kind === "drive"
        ? HardDrive
        : kind === "display"
          ? Monitor
          : Usb;
  return <Icon size={size} aria-hidden="true" />;
}
export function Status({ connected }: { connected: boolean }) {
  return (
    <span className={`status ${connected ? "" : "available"}`}>
      <i />
      {connected ? "Connected" : "Available"}
    </span>
  );
}
export function Summary({
  label,
  value,
  suffix,
  icon,
}: {
  label: string;
  value: string;
  suffix?: string;
  icon: ReactNode;
}) {
  return (
    <div className="summary-stat">
      <span className="stat-icon">{icon}</span>
      <div>
        <span>{label}</span>
        <strong>
          {value} <small>{suffix}</small>
        </strong>
      </div>
    </div>
  );
}
