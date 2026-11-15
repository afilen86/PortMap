import { useLayoutEffect, useRef, useState } from "react";
import {
  ArrowRight,
  Cable,
  Check,
  ChevronDown,
  ChevronRight,
  Info,
  Monitor,
  Plug,
} from "lucide-react";
import { flatten, type Device, type Port, type Snapshot } from "./model";
import { DeviceIcon, Status } from "./components";

export function Overview({
  scan,
  ports,
  selectedPort,
  selected,
  select,
  allPaths,
}: {
  scan: Snapshot;
  ports: Port[];
  selectedPort?: Port;
  selected: string;
  select: (id: string) => void;
  allPaths: boolean;
}) {
  const canvas = useRef<HTMLDivElement>(null);
  const [wires, setWires] = useState<{ id: string; path: string }[]>([]);
  useLayoutEffect(() => {
    const element = canvas.current;
    if (!element) return;
    function measure() {
      const box = element!.getBoundingClientRect();
      const host = element!
        .querySelector(".host-card")!
        .getBoundingClientRect();
      const x = host.left + host.width / 2 - box.left;
      const y = host.bottom - box.top;
      setWires(
        Array.from(element!.querySelectorAll<HTMLElement>(".map-port")).map(
          (card) => {
            const rect = card.getBoundingClientRect();
            const tx = rect.left + rect.width / 2 - box.left;
            const ty = rect.top - box.top;
            const firstRow = ty - y < 100;
            return {
              id: card.dataset.port!,
              path: firstRow
                ? `M ${x} ${y} V ${ty - 18} H ${tx} V ${ty}`
                : `M ${x} ${y} V ${y + 16} H 7 V ${ty - 16} H ${tx} V ${ty}`,
            };
          },
        ),
      );
    }
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    element
      .querySelectorAll(".map-port")
      .forEach((card) => observer.observe(card));
    return () => observer.disconnect();
  }, [ports.map((p) => p.id).join("|")]);
  return (
    <div className="overview" ref={canvas}>
      <svg className="map-wires" aria-hidden="true">
        {wires.map((w) => (
          <path
            key={w.id}
            d={w.path}
            className={
              selectedPort?.id === w.id
                ? "traced"
                : allPaths
                  ? ""
                  : "hidden-wire"
            }
          />
        ))}
      </svg>
      <div className="canvas-label">HOST COMPUTER</div>
      <div className="host-card">
        <div className="mac-art">
          <div className="mac-top">
            <span>●</span>
          </div>
          <div className="mac-front">
            <i />
            <i />
            <b />
          </div>
        </div>
        <div>
          <strong>{scan.host}</strong>
          <span>Your workspace starts here</span>
        </div>
        <span className="host-pill">HOST</span>
      </div>
      <div className="host-stem" />
      <div className="port-grid">
        {ports.map((p, index) => (
          <article
            key={p.id}
            data-port={p.id}
            className={`map-port ${selectedPort?.id === p.id ? "traced" : ""} ${!allPaths && selectedPort?.id !== p.id ? "dimmed" : ""}`}
          >
            <div className="port-branch" />
            <button
              className="map-port-head"
              onClick={() => select(p.id)}
              aria-pressed={selected === p.id}
            >
              <span className="port-number">
                {String(index + 1).padStart(2, "0")}
              </span>
              <span>
                <strong>{p.name}</strong>
                <span>{p.speed}</span>
              </span>
              <span
                className={`connection-dot ${p.connected ? "connected" : ""}`}
                title={p.connected ? "Connected" : "Available"}
              />
            </button>
            <div className="map-devices">
              {p.children.length ? (
                p.children.map((d) => (
                  <button
                    key={d.id}
                    className={`map-device ${selected === d.id ? "selected" : ""}`}
                    onClick={() => select(d.id)}
                    aria-pressed={selected === d.id}
                  >
                    <span className={`device-symbol ${d.kind}`}>
                      <DeviceIcon kind={d.kind} />
                    </span>
                    <span>
                      <strong>{d.name}</strong>
                      <span>
                        {flatten(d.children).length
                          ? `${flatten(d.children).length} downstream devices`
                          : d.detail}
                      </span>
                    </span>
                    <ChevronRight size={14} />
                  </button>
                ))
              ) : (
                <div className="available-port">
                  <Plug size={22} />
                  <span>Open for possibilities</span>
                  <small>No device connected</small>
                </div>
              )}
            </div>
            <div className="map-port-footer">
              <Status connected={p.connected} />
              <span>{flatten(p.children).length} devices</span>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
export function DeviceTree({
  device,
  selected,
  select,
}: {
  device: Device;
  selected: string;
  select: (id: string) => void;
}) {
  const [open, setOpen] = useState(true);
  return (
    <div className="device-tree">
      <div
        className={`tree-device-row ${selected === device.id ? "selected" : ""}`}
      >
        {device.children.length ? (
          <button
            className="tree-toggle"
            aria-label={`${open ? "Collapse" : "Expand"} ${device.name}`}
            aria-expanded={open}
            onClick={() => setOpen(!open)}
          >
            {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
          </button>
        ) : (
          <span className="tree-leaf" />
        )}
        <button
          className="tree-device"
          onClick={() => select(device.id)}
          aria-pressed={selected === device.id}
        >
          <DeviceIcon kind={device.kind} />
          <span>
            <strong>{device.name}</strong>
            <span>{device.detail}</span>
          </span>
          <small>{device.speed}</small>
        </button>
      </div>
      {open && device.children.length > 0 && (
        <div className="tree-children">
          {device.children.map((child) => (
            <DeviceTree
              key={child.id}
              device={child}
              selected={selected}
              select={select}
            />
          ))}
        </div>
      )}
    </div>
  );
}
export function Inspector({
  port,
  device,
  route,
  host,
  selected,
  select,
}: {
  port: Port;
  device?: Device;
  route: Device[];
  host: string;
  selected: string;
  select: (id: string) => void;
}) {
  const children = device?.children ?? port.children;
  return (
    <aside className="inspector" aria-label="Connection details">
      <div className="inspector-label">
        CONNECTION DETAILS <Info size={14} />
      </div>
      <div className={`inspector-art ${device?.kind ?? "device"}`}>
        {device ? (
          <DeviceIcon kind={device.kind} size={39} />
        ) : (
          <Plug size={39} />
        )}
      </div>
      <h2>{device?.name ?? port.name}</h2>
      <p className="inspector-subtitle">{device?.detail ?? port.group}</p>
      <Status connected={port.connected} />
      <div className="detail-divider" />
      <h3>Connection path</h3>
      <ol className="route-list">
        <li>
          <span className="route-dot">
            <Monitor size={13} />
          </span>
          <span>
            {host}
            <small>Host computer</small>
          </span>
        </li>
        <li>
          <span className="route-dot">
            <Plug size={13} />
          </span>
          <button onClick={() => select(port.id)}>
            {port.name}
            <small>{port.speed}</small>
          </button>
        </li>
        {route.map((d) => (
          <li key={d.id}>
            <span className="route-dot">
              <DeviceIcon kind={d.kind} size={13} />
            </span>
            <button onClick={() => select(d.id)}>
              {d.name}
              <small>{d.speed ?? d.detail}</small>
            </button>
          </li>
        ))}
      </ol>
      <div className="detail-divider" />
      <h3>At a glance</h3>
      <dl className="detail-list">
        <div>
          <dt>Status</dt>
          <dd>
            {port.connected ? (
              <>
                <Check size={13} />
                Connected
              </>
            ) : (
              "Available"
            )}
          </dd>
        </div>
        <div>
          <dt>Reported link</dt>
          <dd>{device?.speed ?? port.speed}</dd>
        </div>
        <div>
          <dt>Downstream</dt>
          <dd>{flatten(children).length} devices</dd>
        </div>
      </dl>
      {port.cable && (
        <div className="cable-note">
          <Cable size={16} />
          <div>
            <strong>Reported cable capability</strong>
            <p>{port.cable}</p>
          </div>
        </div>
      )}
      {children.length > 0 && (
        <>
          <div className="detail-divider" />
          <h3>
            Connected devices{" "}
            <span className="count-badge">{children.length}</span>
          </h3>
          <div className="inspector-children">
            {children.map((d) => (
              <button
                key={d.id}
                onClick={() => select(d.id)}
                aria-pressed={selected === d.id}
              >
                <DeviceIcon kind={d.kind} size={16} />
                <span>{d.name}</span>
                <ArrowRight size={13} />
              </button>
            ))}
          </div>
        </>
      )}
      {!port.connected && (
        <div className="cable-note">
          <Cable size={16} />
          <p>Connect a device to see its details and cable path here.</p>
        </div>
      )}
    </aside>
  );
}
