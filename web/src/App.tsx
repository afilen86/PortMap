import { useEffect, useRef, useState, type ChangeEvent } from "react";
import {
  Cable,
  ChevronRight,
  CircleHelp,
  Info,
  LayoutDashboard,
  LoaderCircle,
  Monitor,
  Moon,
  Network,
  Plug,
  RefreshCw,
  Search,
  SlidersHorizontal,
  Sun,
  Upload,
  Usb,
  X,
} from "lucide-react";
import { connectNative, isNative, requestNative } from "./bridge";
import { sample, scenarioLabels, type Scenario } from "./data";
import {
  findRoute,
  flatten,
  fromWhatCable,
  snapshotSchema,
  type Port,
  type Snapshot,
} from "./model";

import { Status, Summary } from "./components";
import { Overview, DeviceTree, Inspector } from "./ConnectionViews";

type Mode = "overview" | "setup" | "ports";
function stored(key: string, fallback: string) {
  try {
    return localStorage.getItem(key) ?? fallback;
  } catch {
    return fallback;
  }
}
function remember(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* Private webviews may disable storage. */
  }
}
const viewInfo: Record<Mode, { title: string; description: string }> = {
  overview: {
    title: "Your setup, connected.",
    description: "A clear view of your devices and the paths between them.",
  },
  setup: {
    title: "Every connection, in order.",
    description:
      "Follow your devices from the Mac to the end of each cable path.",
  },
  ports: {
    title: "A place for everything.",
    description: "Explore each port, its capabilities, and what’s plugged in.",
  },
};

export default function App() {
  const native = isNative();
  const [mode, setMode] = useState<Mode>(() => {
    const value = stored("portmap-view", "overview");
    return value === "setup" || value === "ports" ? value : "overview";
  });
  const [scenario, setScenario] = useState<Scenario>("saved");
  const [imported, setImported] = useState(false);
  const [scan, setScan] = useState<Snapshot | null>(() =>
    native ? null : sample("saved"),
  );
  const [selected, setSelected] = useState("Port-USB-C@2");
  const [query, setQuery] = useState("");
  const [allPaths, setAllPaths] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(native);
  const [theme, setTheme] = useState(() => stored("portmap-theme", "light"));
  const file = useRef<HTMLInputElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    remember("portmap-theme", theme);
  }, [theme]);
  useEffect(() => {
    remember("portmap-view", mode);
  }, [mode]);
  useEffect(() => {
    const disconnect = connectNative((event) => {
      clearTimeout(timer.current);
      setBusy(false);
      if (event.type === "snapshot") {
        setScan(event.snapshot);
        setError(null);
      } else setError(event.message);
    });
    return () => {
      disconnect();
      clearTimeout(timer.current);
    };
  }, []);
  useEffect(() => {
    if (!busy || !native) return;
    const timeout = setTimeout(() => {
      setBusy(false);
      setError("The Mac hasn’t sent a connection report yet. Try refreshing.");
    }, 15000);
    return () => clearTimeout(timeout);
  }, [busy, native]);
  const allDevices = scan ? scan.ports.flatMap((p) => flatten(p.children)) : [];
  const selectedPort =
    scan?.ports.find(
      (p) =>
        p.id === selected || flatten(p.children).some((d) => d.id === selected),
    ) ??
    scan?.ports.find((p) => p.connected) ??
    scan?.ports[0];
  const selectedDevice = allDevices.find((d) => d.id === selected);
  const route = selectedPort ? findRoute(selectedPort, selected) : [];
  const matches = (p: Port) =>
    `${p.name} ${p.id} ${p.speed} ${flatten(p.children)
      .map((d) => `${d.name} ${d.detail}`)
      .join(" ")}`
      .toLowerCase()
      .includes(query.toLowerCase());
  const visiblePorts = scan?.ports.filter(matches) ?? [];
  const connected = scan?.ports.filter((p) => p.connected).length ?? 0;
  function changeScenario(next: Scenario) {
    clearTimeout(timer.current);
    setScenario(next);
    setImported(false);
    setScan(sample(next));
    setError(
      next === "error"
        ? "WhatCable couldn’t complete the scan. Check that the helper is installed, then try again."
        : null,
    );
    setBusy(false);
    setQuery("");
    setSelected("Port-USB-C@2");
  }
  function refresh() {
    setBusy(true);
    setError(null);
    if (native) requestNative("refresh");
    else
      timer.current = setTimeout(() => {
        if (scenario === "error")
          setError(
            "WhatCable couldn’t complete the scan. Choose another sample state to continue exploring.",
          );
        setBusy(false);
      }, 550);
  }
  async function importReport(event: ChangeEvent<HTMLInputElement>) {
    const upload = event.target.files?.[0];
    if (!upload) return;
    try {
      if (upload.size > 5 * 1024 * 1024)
        throw new Error("Choose a report smaller than 5 MB.");
      const raw: unknown = JSON.parse(await upload.text());
      const normalized = snapshotSchema.safeParse(raw);
      const imported = normalized.success
        ? normalized.data
        : fromWhatCable(raw);
      clearTimeout(timer.current);
      setBusy(false);
      setScan(imported);
      setImported(true);
      setSelected(imported.ports[0]?.id ?? "");
      setError(null);
      setQuery("");
    } catch (reason) {
      setError(
        reason instanceof Error && reason.message.includes("5 MB")
          ? reason.message
          : "This file isn’t a supported connection report. Import WhatCable JSON or a Port Map snapshot.",
      );
    }
    event.target.value = "";
  }
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <a
          className="brand"
          href="#"
          onClick={(event) => {
            event.preventDefault();
            setMode("overview");
          }}
        >
          <span className="brand-icon">
            <Cable size={24} />
          </span>
          <span>
            Port Map
            <span className="brand-subtitle">Everything in its place.</span>
          </span>
        </a>
        <div className="section-label">WORKSPACE</div>
        <nav aria-label="Main navigation">
          {(["overview", "setup", "ports"] as const).map((view) => {
            const Icon =
              view === "overview"
                ? LayoutDashboard
                : view === "setup"
                  ? Network
                  : Plug;
            return (
              <button
                key={view}
                className={`nav-item ${mode === view ? "active" : ""}`}
                aria-current={mode === view ? "page" : undefined}
                onClick={() => setMode(view)}
              >
                <Icon size={19} />
                <span>
                  {view === "overview"
                    ? "Overview"
                    : view === "setup"
                      ? "Connection tree"
                      : "Ports"}
                </span>
                {mode === view && <span className="nav-indicator" />}
              </button>
            );
          })}
        </nav>
        <div className="sidebar-device">
          <div className="section-label">YOUR COMPUTER</div>
          <div className="computer">
            <span className="computer-icon">
              <Monitor size={20} />
            </span>
            <div>
              <strong>{scan?.host ?? "This Mac"}</strong>
              <span>
                {native
                  ? "Live connection data"
                  : imported
                    ? "Imported connection report"
                    : "Saved connection report"}
              </span>
            </div>
          </div>
          <div
            className="port-meter"
            aria-label={`${connected} of ${scan?.ports.length ?? 0} ports connected`}
          >
            {scan?.ports.map((p) => (
              <span key={p.id} className={p.connected ? "used" : ""} />
            ))}
          </div>
          <p>
            {connected} of {scan?.ports.length ?? 0} ports connected
          </p>
        </div>
        <div className="sidebar-bottom">
          <div className="tip">
            <CircleHelp size={18} />
            <div>
              <strong>Follow the connection</strong>
              <p>Select a device to see its route back to your Mac.</p>
            </div>
          </div>
          <button
            className="theme-button"
            onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
          >
            {theme === "dark" ? <Sun size={17} /> : <Moon size={17} />}
            <span>
              {theme === "dark" ? "Light appearance" : "Dark appearance"}
            </span>
          </button>
        </div>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <div className="breadcrumbs">
            Workspace <ChevronRight size={14} />
            <strong>
              {mode === "setup"
                ? "Connection tree"
                : mode[0].toUpperCase() + mode.slice(1)}
            </strong>
          </div>
          <div className="topbar-actions">
            <span className="preview-badge">
              {native ? "Mac connected" : "Browser preview"}
            </span>
            <button
              className="icon-button"
              aria-label="Import connection report"
              title="Import connection report"
              onClick={() => file.current?.click()}
            >
              <Upload size={18} />
            </button>
            <input
              ref={file}
              type="file"
              accept=".json,application/json"
              hidden
              onChange={importReport}
            />
          </div>
        </header>
        <main>
          <div className="page-heading">
            <div>
              <div className="eyebrow">YOUR CONNECTED WORKSPACE</div>
              <h1>{viewInfo[mode].title}</h1>
              <p>{viewInfo[mode].description}</p>
            </div>
            <button
              className="button refresh"
              onClick={refresh}
              disabled={busy}
            >
              <RefreshCw size={16} className={busy ? "spin" : ""} />
              {busy
                ? "Refreshing…"
                : native
                  ? "Refresh connections"
                  : "Reload preview"}
            </button>
          </div>
          <div className="summary">
            <Summary
              label="Ports connected"
              value={`${connected}`}
              suffix={`/ ${scan?.ports.length ?? 0}`}
              icon={<Plug size={20} />}
            />
            <Summary
              label="Devices detected"
              value={`${allDevices.length}`}
              icon={<Usb size={20} />}
            />
            <Summary
              label="Ports available"
              value={`${(scan?.ports.length ?? 0) - connected}`}
              icon={<Cable size={20} />}
            />
            <div className="summary-note">
              <span className="live-dot" />
              <div>
                <strong>
                  {native ? "Listening for changes" : "Explore your setup"}
                </strong>
                <span>
                  {native
                    ? "Connections update automatically"
                    : "Select any port or device for details"}
                </span>
              </div>
            </div>
          </div>
          {error && (
            <div className="error-banner" role="alert">
              <Info size={20} />
              <div>
                <strong>Couldn’t read connections</strong>
                <p>{error}</p>
              </div>
              <button className="text-button" onClick={refresh} disabled={busy}>
                Try again
              </button>
              <button
                className="icon-button"
                aria-label="Dismiss error"
                onClick={() => setError(null)}
              >
                <X size={17} />
              </button>
            </div>
          )}
          <section className="map-panel" aria-label="Connection explorer">
            <div className="panel-toolbar">
              <div className="panel-title">
                <span className="small-icon">
                  <Network size={17} />
                </span>
                <h2>
                  {mode === "overview"
                    ? "Connection map"
                    : mode === "setup"
                      ? "Connection tree"
                      : "Your ports"}
                </h2>
              </div>
              <div className="panel-controls">
                <label className="search">
                  <Search size={15} />
                  <input
                    aria-label="Search devices"
                    placeholder="Find a device or port…"
                    value={query}
                    onChange={(event) => setQuery(event.target.value)}
                  />
                  {query && (
                    <button
                      aria-label="Clear search"
                      onClick={() => setQuery("")}
                    >
                      <X size={14} />
                    </button>
                  )}
                </label>
                {mode === "overview" && (
                  <label className="switch-label">
                    <input
                      type="checkbox"
                      checked={allPaths}
                      onChange={(event) => setAllPaths(event.target.checked)}
                    />
                    <span className="switch" />
                    All paths
                  </label>
                )}
              </div>
            </div>
            {!scan ? (
              <div className="empty-state">
                <LoaderCircle className={busy ? "spin" : ""} />
                <h3>
                  {busy
                    ? "Reading your connections"
                    : "No connection report yet"}
                </h3>
                <p>
                  {busy
                    ? "Your ports and devices will appear here."
                    : "Refresh to request a report from your Mac."}
                </p>
              </div>
            ) : !visiblePorts.length ? (
              <div className="empty-state">
                <Search />
                <h3>
                  {scan.ports.length
                    ? "No matching connections"
                    : "No ports reported"}
                </h3>
                <p>
                  {scan.ports.length
                    ? "Try a different device name or port."
                    : "Refresh or import another report to see your ports."}
                </p>
                {scan.ports.length > 0 && (
                  <button className="button" onClick={() => setQuery("")}>
                    Clear search
                  </button>
                )}
              </div>
            ) : (
              <div className="explorer">
                <div className="explorer-content">
                  {mode === "overview" ? (
                    <Overview
                      scan={scan}
                      ports={visiblePorts}
                      selectedPort={selectedPort}
                      selected={selected}
                      select={setSelected}
                      allPaths={allPaths}
                    />
                  ) : mode === "setup" ? (
                    <div className="tree-view">
                      <div className="tree-host">
                        <Monitor />
                        <strong>{scan.host}</strong>
                        <span>Host computer</span>
                      </div>
                      {visiblePorts.map((p) => (
                        <section className="tree-port" key={p.id}>
                          <button
                            className={`tree-port-heading ${selected === p.id ? "selected" : ""}`}
                            onClick={() => setSelected(p.id)}
                          >
                            <Plug size={17} />
                            <strong>{p.name}</strong>
                            <Status connected={p.connected} />
                          </button>
                          {p.children.length ? (
                            p.children.map((d) => (
                              <DeviceTree
                                key={d.id}
                                device={d}
                                selected={selected}
                                select={setSelected}
                              />
                            ))
                          ) : (
                            <p className="tree-empty">
                              Ready for your next device.
                            </p>
                          )}
                        </section>
                      ))}
                    </div>
                  ) : (
                    <div className="ports-view">
                      {Array.from(
                        new Set(visiblePorts.map((p) => p.group)),
                      ).map((group) => (
                        <section key={group}>
                          <h3 className="section-label">{group}</h3>
                          {visiblePorts
                            .filter((p) => p.group === group)
                            .map((p) => (
                              <button
                                key={p.id}
                                className={`port-list-row ${selectedPort?.id === p.id ? "selected" : ""}`}
                                onClick={() => setSelected(p.id)}
                              >
                                <span className="device-symbol">
                                  <Plug size={21} />
                                </span>
                                <span className="port-list-name">
                                  <strong>{p.name}</strong>
                                  <span>
                                    {p.children[0]?.name ?? "Ready to connect"}
                                  </span>
                                </span>
                                <span className="port-list-speed">
                                  {p.speed}
                                </span>
                                <Status connected={p.connected} />
                                <ChevronRight size={16} />
                              </button>
                            ))}
                        </section>
                      ))}
                    </div>
                  )}
                </div>
                {selectedPort && (
                  <Inspector
                    port={selectedPort}
                    device={selectedDevice}
                    route={route}
                    host={scan.host}
                    selected={selected}
                    select={setSelected}
                  />
                )}
              </div>
            )}
            <div className="map-legend">
              <span>
                <i className="legend-line" />
                Selected connection
              </span>
              <span>
                <i className="legend-line muted" />
                Other connections
              </span>
              <span className="legend-note">
                {mode === "overview"
                  ? "Routes are schematic"
                  : "Reported device topology"}
              </span>
            </div>
          </section>
          <footer className="workspace-footer">
            <span>
              <span className="live-dot" />
              {native
                ? (scan?.source ?? "Waiting for Mac")
                : imported
                  ? "Imported report · no hardware access"
                  : "Sample data · no hardware access"}
              {scan && (
                <span className="snapshot-date">
                  {" "}
                  · {native || imported ? "Scanned" : "Fixture"}{" "}
                  {new Date(scan.capturedAt).toLocaleString(undefined, {
                    month: "short",
                    day: "numeric",
                    hour: "numeric",
                    minute: "2-digit",
                  })}
                </span>
              )}
            </span>
            {!native && (
              <label className="scenario-control">
                <SlidersHorizontal size={14} />
                <span>Preview state</span>
                <select
                  aria-label="Preview state"
                  value={imported ? "imported" : scenario}
                  onChange={(event) =>
                    changeScenario(event.target.value as Scenario)
                  }
                >
                  {imported && (
                    <option value="imported" disabled>
                      Imported report
                    </option>
                  )}
                  {Object.entries(scenarioLabels).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
            )}
          </footer>
        </main>
      </div>
    </div>
  );
}
