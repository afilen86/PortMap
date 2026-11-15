// Host adapter for the bundled macOS UI. The offline preview remains independent.
const nativePortMap = !!window.webkit?.messageHandlers?.portMap;
const savedScene = JSON.parse(
  JSON.stringify({
    nodes: DATA.nodes,
    layouts: DATA.layouts,
    sizes: DATA.sizes,
    routes: DATA.routes,
  }),
);
let liveScene = false;
let lastSnapshotKey = "";
let hostTimer;
function postHost(type, extra = {}) {
  window.webkit?.messageHandlers?.portMap?.postMessage({
    type,
    schemaVersion: 1,
    ...extra,
  });
}
const statusBar = el("div", { class: "native-status", role: "status" });
const statusText = el("span");
const refreshButton = el("button", { class: "control-button" });
refreshButton.textContent = "Refresh connections";
refreshButton.addEventListener("click", () => {
  refreshButton.disabled = true;
  statusText.textContent = "Scanning connections…";
  armHostTimeout();
  postHost("refresh");
});
const demoButton = el("button", { class: "control-button" });
demoButton.textContent = "Show demo setup";
demoButton.addEventListener("click", () => postHost("demo"));
statusBar.append(statusText, refreshButton, demoButton);
document.querySelector(".app-frame").before(statusBar);
const nativeStyle = document.createElement("style");
nativeStyle.textContent = `
.native-status{margin:0 28px 12px;display:flex;gap:10px;align-items:center;font-size:12px;color:var(--muted)}
.native-status>span{flex:1;line-height:1.5}.native-status button[hidden]{display:none!important}.native-status.error>span{color:var(--audio)}
body.native-host .bottom-note>span:last-child{display:none}
.device-name,.device-sub{max-width:100%;overflow:hidden;text-overflow:ellipsis}.selected-cable{max-width:210px;white-space:normal;line-height:1.5}
@media(max-width:760px){.native-status{margin:0 14px 10px;flex-wrap:wrap}}
`;
document.head.append(nativeStyle);
function armHostTimeout() {
  clearTimeout(hostTimer);
  hostTimer = setTimeout(() => {
    refreshButton.disabled = false;
    statusBar.classList.add("error");
    statusText.textContent =
      "The Mac has not returned a report. Try refreshing or view the demo setup.";
  }, 18000);
}
function replaceNodes(nodes) {
  DATA.nodes = nodes;
  for (const key of Object.keys(byId)) delete byId[key];
  Object.assign(byId, Object.fromEntries(nodes.map((n) => [n.id, n])));
  locate.replaceChildren();
  for (const n of nodes) {
    const option = el("option", { value: n.id });
    option.textContent = n.name;
    locate.append(option);
  }
  if (!byId[selected]) selected = nodes[0].id;
  document.querySelector(".concept-badges .badge").textContent =
    `${nodes.length} device images · all visible`;
}
const normalSelect = select;
select = function (id) {
  if (byId[id]) normalSelect(id);
};
const normalPhoto = photo;
photo = function (n) {
  if (
    DATA.atlas.includes(n.image) ||
    Object.hasOwn(DATA.assets, n.image) ||
    ["element", "satechi"].includes(n.image)
  )
    return normalPhoto(n);
  const wrap = el("span", {
    class: "photo",
    role: "img",
    "aria-label": `${n.name} — no product photo available`,
  });
  const icon = svg("svg", {
    width: "58",
    height: "58",
    viewBox: "0 0 64 64",
    fill: "none",
    stroke: "var(--muted)",
    "stroke-width": "2",
  });
  icon.append(
    svg("rect", { x: "10", y: "13", width: "44", height: "31", rx: "6" }),
  );
  icon.append(svg("path", { d: "M23 53h18M32 44v9" }));
  wrap.append(icon);
  return wrap;
};
const normalType = type;
type = (n) =>
  n.wire?.includes("Thunderbolt") || n.wire?.includes("USB4")
    ? "thunderbolt"
    : normalType(n);
// A small grid router keeps live paths out of the image rectangles.
function routeLive(nodes, positions, metrics, width, height) {
  const occupied = new Set(),
    used = new Map(),
    result = {};
  const key = (x, y) => `${x},${y}`;
  for (const n of nodes) {
    const [x, y] = positions[n.id],
      m = metrics[n.id];
    for (let i = (x - 10) / 10; i <= (x + m.width + 10) / 10; i++)
      for (let j = (y - 10) / 10; j <= (y + m.height + 10) / 10; j++)
        occupied.add(key(i, j));
  }
  function anchor(id, side) {
    const [x, y] = positions[id],
      { width: w, height: h } = metrics[id];
    const a = {
      r: [x + w, y + h / 2],
      l: [x, y + h / 2],
      t: [x + w / 2, y],
      b: [x + w / 2, y + h],
    }[side];
    const d = { r: [20, 0], l: [-20, 0], t: [0, -20], b: [0, 20] }[side];
    return { edge: a, x: (a[0] + d[0]) / 10, y: (a[1] + d[1]) / 10 };
  }
  function search(start, goal) {
    const heap = [],
      cost = new Map(),
      previous = new Map();
    function push(v) {
      heap.push(v);
      let i = heap.length - 1;
      while (i) {
        const p = (i - 1) >> 1;
        if (heap[p].f <= v.f) break;
        heap[i] = heap[p];
        i = p;
      }
      heap[i] = v;
    }
    function pop() {
      const first = heap[0],
        tail = heap.pop();
      if (heap.length) {
        let i = 0;
        while (i * 2 + 1 < heap.length) {
          let c = i * 2 + 1;
          if (c + 1 < heap.length && heap[c + 1].f < heap[c].f) c++;
          if (heap[c].f >= tail.f) break;
          heap[i] = heap[c];
          i = c;
        }
        heap[i] = tail;
      }
      return first;
    }
    const stateKey = (x, y, direction) => `${x},${y},${direction}`;
    const initial = stateKey(start.x, start.y, -1);
    cost.set(initial, 0);
    push({ x: start.x, y: start.y, direction: -1, g: 0, f: 0 });
    while (heap.length) {
      const current = pop(),
        ck = stateKey(current.x, current.y, current.direction);
      if (current.g !== cost.get(ck)) continue;
      if (current.x === goal.x && current.y === goal.y) {
        const path = [[current.x * 10, current.y * 10]];
        let p = ck;
        while (previous.has(p)) {
          p = previous.get(p);
          path.push(
            p
              .split(",")
              .slice(0, 2)
              .map(Number)
              .map((x) => x * 10),
          );
        }
        return path.reverse();
      }
      for (const [direction, [dx, dy]] of [
        [1, 0],
        [0, 1],
        [-1, 0],
        [0, -1],
      ].entries()) {
        const x = current.x + dx,
          y = current.y + dy,
          k = key(x, y);
        if (
          x < 0 ||
          y < 0 ||
          x > width / 10 ||
          y > height / 10 ||
          occupied.has(k)
        )
          continue;
        const turn =
          current.direction !== -1 && current.direction !== direction ? 2 : 0;
        const g = current.g + 1 + turn + (used.get(k) || 0) * 0.6;
        const next = stateKey(x, y, direction);
        if (g >= (cost.get(next) ?? Infinity)) continue;
        cost.set(next, g);
        previous.set(next, ck);
        push({
          x,
          y,
          direction,
          g,
          f: g + Math.abs(x - goal.x) + Math.abs(y - goal.y),
        });
      }
    }
    return null;
  }
  for (const n of nodes.filter((n) => n.parent)) {
    const a = positions[n.parent],
      b = positions[n.id];
    const horizontal = b[0] > a[0] ? ["r", "l"] : ["l", "r"];
    const vertical = b[1] > a[1] ? ["b", "t"] : ["t", "b"];
    const pairs =
      Math.abs(b[1] - a[1]) > Math.abs(b[0] - a[0])
        ? [vertical, horizontal]
        : [horizontal, vertical];
    pairs.push(["b", "b"], ["t", "t"]);
    let points;
    for (const [left, right] of pairs) {
      const start = anchor(n.parent, left),
        end = anchor(n.id, right);
      if (
        [start, end].some(
          (p) =>
            p.x < 0 ||
            p.y < 0 ||
            p.x > width / 10 ||
            p.y > height / 10 ||
            occupied.has(key(p.x, p.y)),
        )
      )
        continue;
      const path = search(start, end);
      if (!path) continue;
      for (const [x, y] of path)
        used.set(key(x / 10, y / 10), (used.get(key(x / 10, y / 10)) || 0) + 1);
      points = [start.edge, ...path, end.edge];
      break;
    }
    if (!points)
      throw new Error("A cable path could not be laid out. Try refreshing.");
    const compact = points.filter(
      (p, i) =>
        !i ||
        i === points.length - 1 ||
        !(
          (points[i - 1][0] === p[0] && p[0] === points[i + 1][0]) ||
          (points[i - 1][1] === p[1] && p[1] === points[i + 1][1])
        ),
    );
    result[n.id] = "M " + compact.map((p) => p.join(" ")).join(" L ");
  }
  return result;
}
let canvasWidth = 1560,
  canvasHeight = 820;
function installLiveLayout(nodes) {
  // Keep the demo's recognizable orbit for every live setup size. Additional
  // devices extend equally to the left and right, leaving the Mac at the center.
  const host = nodes.find((n) => !n.parent);
  const rest = nodes
    .filter((n) => n.parent)
    .sort((a, b) => a.id.localeCompare(b.id));
  const overflowCount = Math.max(0, nodes.length - savedScene.nodes.length);
  const outerColumns = overflowCount
    ? Math.ceil(Math.sqrt(overflowCount / 6))
    : 0;
  const outerRows = outerColumns
    ? Math.ceil(overflowCount / (2 * outerColumns))
    : 0;
  const paddingX = outerColumns * 260;
  canvasWidth = 1560 + 2 * paddingX;
  canvasHeight = Math.max(
    820,
    2 * (Math.ceil((outerRows - 1) / 2) * 220 + 110),
  );
  const paddingY = (canvasHeight - 820) / 2;
  for (const theme of ["clay", "afterhours"]) {
    const slots = savedScene.layouts[theme],
      baseSizes = savedScene.sizes[theme];
    const positions = {},
      metrics = {},
      assigned = new Set(["mac"]);
    metrics[host.id] = { ...baseSizes.mac };
    positions[host.id] = [
      (canvasWidth - metrics[host.id].width) / 2,
      (canvasHeight - metrics[host.id].height) / 2,
    ];
    // Assign recognized hardware first so snapshot order and unknown devices
    // cannot displace a known hub, display, or controller from its demo position.
    for (const n of rest) {
      const candidate =
        n.slot &&
        n.slot !== "mac" &&
        Object.hasOwn(slots, n.slot) &&
        !assigned.has(n.slot)
          ? n.slot
          : null;
      if (candidate) {
        assigned.add(candidate);
        positions[n.id] = [
          slots[candidate][0] + paddingX,
          slots[candidate][1] + paddingY,
        ];
        metrics[n.id] = { ...baseSizes[candidate] };
      }
    }
    const extra = [];
    for (const n of rest.filter((n) => !positions[n.id])) {
      const slot =
        Object.keys(slots).find(
          (slot) =>
            !assigned.has(slot) &&
            !["mac", "satechi", "element"].includes(slot),
        ) || Object.keys(slots).find((slot) => !assigned.has(slot));
      if (!slot) {
        extra.push(n);
        continue;
      }
      assigned.add(slot);
      positions[n.id] = [slots[slot][0] + paddingX, slots[slot][1] + paddingY];
      metrics[n.id] = { ...baseSizes[slot] };
    }
    extra.forEach((n, i) => {
      const column = Math.floor(i / (2 * outerRows)),
        side = i % 2,
        row = Math.floor((i % (2 * outerRows)) / 2),
        rowOffset = row ? Math.ceil(row / 2) * (row % 2 ? -1 : 1) : 0;
      const centerX = side
        ? 1560 + (column + 0.5) * 260
        : -(column + 0.5) * 260;
      metrics[n.id] = { ...baseSizes.expansion };
      positions[n.id] = [
        centerX + paddingX - metrics[n.id].width / 2,
        canvasHeight / 2 + rowOffset * 220 - metrics[n.id].height / 2,
      ];
    });
    DATA.layouts[theme] = positions;
    DATA.sizes[theme] = metrics;
    DATA.routes[theme] = routeLive(
      nodes,
      positions,
      metrics,
      canvasWidth,
      canvasHeight,
    );
  }
}

function validSnapshot(input) {
  if (
    !input ||
    !Array.isArray(input.nodes) ||
    !input.nodes.length ||
    input.nodes.length > 200
  )
    throw new Error("Invalid device report");
  const ids = new Set();
  for (const n of input.nodes) {
    if (
      !n ||
      typeof n.id !== "string" ||
      ids.has(n.id) ||
      !["name", "image", "kind", "wire", "speed"].every(
        (k) => typeof n[k] === "string",
      )
    )
      throw new Error("Invalid device report");
    ids.add(n.id);
  }
  if (input.nodes.filter((n) => !n.parent).length !== 1)
    throw new Error("Invalid host count");
  for (const n of input.nodes) {
    const seen = new Set([n.id]);
    let p = n.parent;
    while (p) {
      if (!ids.has(p) || seen.has(p)) throw new Error("Invalid cable topology");
      seen.add(p);
      p = input.nodes.find((n) => n.id === p).parent;
    }
  }
  return input;
}
const normalActivate = activate;
activate = function (value, changeHash = false) {
  normalActivate(value, changeHash);
  if (nativePortMap) postHost("appearance", { value: appearance });
  if (liveScene) document.querySelector("#zones").replaceChildren();
};
const normalFit = fit;
fit = function () {
  normalFit();
  if (!nativePortMap) return;
  const wrap = document.querySelector("#stage-wrap");
  const oldHeight = wrap.offsetHeight;
  const excess = Math.max(
    0,
    document.documentElement.scrollHeight - innerHeight,
  );
  const scale = Math.min(
    (wrap.clientWidth - 24) / canvasWidth,
    Math.max(220, oldHeight - excess - statusBar.offsetHeight - 12) /
      canvasHeight,
    1.2,
  );
  stage.style.width = `${canvasWidth}px`;
  stage.style.height = `${canvasHeight}px`;
  wireLayer.setAttribute("viewBox", `0 0 ${canvasWidth} ${canvasHeight}`);
  const rings = document.querySelector(".orbit-rings");
  if (liveScene && rings) {
    rings.style.left = `${(canvasWidth - rings.offsetWidth) / 2}px`;
    rings.style.top = `${(canvasHeight - rings.offsetHeight) / 2}px`;
  } else if (rings) {
    rings.style.left = "";
    rings.style.top = "";
  }
  wrap.style.height = `${Math.ceil(canvasHeight * scale)}px`;
  stage.style.transform = `translateX(${(-canvasWidth * scale) / 2}px) scale(${scale})`;
};
function restoreDemo() {
  liveScene = false;
  lastSnapshotKey = "";
  canvasWidth = 1560;
  canvasHeight = 820;
  for (const k of ["layouts", "sizes", "routes"])
    DATA[k] = JSON.parse(JSON.stringify(savedScene[k]));
  replaceNodes(JSON.parse(JSON.stringify(savedScene.nodes)));
  activate(design, false);
  statusText.textContent = "Demo setup · saved data, not a scan of this Mac";
}
window.portMap = {
  receive(event) {
    if (!event || event.type !== "state" || event.schemaVersion !== 1) return;
    clearTimeout(hostTimer);
    refreshButton.disabled = !!event.refreshing;
    statusBar.classList.remove("error");
    try {
      if (event.demo) restoreDemo();
      else {
        if (event.snapshot) {
          const snapshot = validSnapshot(event.snapshot),
            snapshotKey = JSON.stringify(snapshot.nodes);
          if (snapshotKey !== lastSnapshotKey || !liveScene) {
            // Prepare all geometry before replacing the displayed device inventory.
            const backup = {
              layouts: DATA.layouts,
              sizes: DATA.sizes,
              routes: DATA.routes,
            };
            DATA.layouts = {};
            DATA.sizes = {};
            DATA.routes = {};
            try {
              installLiveLayout(snapshot.nodes);
            } catch (error) {
              Object.assign(DATA, backup);
              throw error;
            }
            replaceNodes(snapshot.nodes);
            liveScene = true;
            lastSnapshotKey = snapshotKey;
            activate(design, false);
          }
          statusText.textContent = event.refreshing
            ? "Scanning connections…"
            : `${snapshot.source || "WhatCable + macOS"} · ${snapshot.connectedPorts ?? "?"} of ${snapshot.totalPorts ?? "?"} ports connected · updates automatically`;
        } else
          statusText.textContent = event.refreshing
            ? "Reading this Mac’s connections…"
            : "No connection report yet. Refresh or explore the demo setup.";
        if (event.error) {
          statusBar.classList.add("error");
          statusText.textContent = event.error;
        }
      }
      requestAnimationFrame(fit);
    } catch (error) {
      statusBar.classList.add("error");
      statusText.textContent =
        error.message || "The connection report could not be read.";
      refreshButton.disabled = false;
    }
  },
};
function startNativeHost() {
  if (!nativePortMap) {
    statusText.textContent =
      "Demo setup · open the Mac app for live connections";
    refreshButton.hidden = true;
    demoButton.hidden = true;
    return;
  }
  document.body.classList.add("native-host");
  statusText.textContent = "Reading this Mac’s connections…";
  armHostTimeout();
  postHost("ready");
}
if (nativePortMap) {
  // Never show the saved peripheral setup as if it were detected on this Mac.
  DATA.layouts = JSON.parse(JSON.stringify(savedScene.layouts));
  DATA.sizes = JSON.parse(JSON.stringify(savedScene.sizes));
  DATA.routes = { clay: {}, afterhours: {} };
  replaceNodes([
    {
      id: "mac",
      name: "This Mac",
      image: "computer",
      kind: "host",
      wire: "",
      speed: "",
      sub: "Waiting for scan",
    },
  ]);
}
