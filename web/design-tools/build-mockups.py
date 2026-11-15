"""Build a dependency-free, offline design lab using original project artwork.

Run from any directory: python3 web/design-tools/build-mockups.py
The routed paths avoid every image card; device positions are design choices,
while relationships mirror the saved report plus ManualConnections.json.
"""
import base64
import heapq
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'web/public/mockups/index.html'
RESOURCES = ROOT / 'port-map-source/Resources'


def node(id, name, parent, image, kind, wire='', speed='', **extra):
    return dict(id=id, name=name, parent=parent, image=image, kind=kind,
                wire=wire, speed=speed, **extra)


nodes = [
    node('mac', 'Mac mini', None, 'mac', 'host', sub='Host computer'),
    node('satechi', 'Satechi Stand & Hub', 'mac', 'satechi', 'hub', 'USB-C', '10 Gb/s'),
    node('element', 'CalDigit Element Hub', 'mac', 'element', 'hub', 'Thunderbolt', '40 Gb/s'),
    node('lacie', 'LaCie P9227 Slim', 'mac', 'lacie', 'storage', 'USB 2', '480 Mb/s'),
    node('ether5', 'Realtek 5 GbE', 'mac', 'ethernet', 'network', 'USB-C', '10 Gb/s', generic=True),
    node('hdmi', 'ingnok · HDMI', 'mac', 'monitor', 'display', 'HDMI', '1080p · 60 Hz', generic=True),
    node('expansion', 'Seagate Expansion', 'satechi', 'expansion', 'storage', 'USB 2', '480 Mb/s', indirect=True),
    node('satechiSSD', 'SATECHI DISK Media', 'satechi', 'nvme', 'storage', 'USB', '10 Gb/s', generic=True),
    node('usbStorage', 'USB Storage', 'satechi', 'nvme', 'storage', 'USB', '5 Gb/s', generic=True),
    node('ether25', 'Realtek 2.5 GbE', 'satechi', 'ethernet', 'network', 'USB', '5 Gb/s', generic=True),
    node('nvme', 'ASMedia NVMe', 'element', 'nvme', 'storage', 'Thunderbolt', '', generic=True),
    node('z1', 'Traktor Z1 MK2', 'element', 'z1', 'controller', 'USB 2', '480 Mb/s', indirect=True),
    node('s4', 'Traktor S4 MK3', 'element', 's4', 'controller', 'USB 2', '480 Mb/s', indirect=True),
    node('x1', 'Traktor X1 MK3', 's4', 'x1', 'controller', 'USB', '12 Mb/s', indirect=True),
    node('display12', '12.3FHD display', 'element', 'monitor', 'display', 'DisplayPort', '1920 × 720 · 60 Hz', generic=True),
    node('displayDP', 'ingnok · USB-C', 'element', 'monitor', 'display', 'DisplayPort', '1080p · 60 Hz', generic=True),
    node('speakers', 'Klipsch The Fives', 's4', 'speakers', 'audio', 'RCA', '', manual=True),
    node('maestro', 'MaestroDMX', 's4', 'maestro', 'audio', 'TRS → RCA', '', manual=True),
    node('scarlett', 'Scarlett 4i4', 'maestro', 'scarlett', 'usb', 'USB', '', manual=True),
]
# Normalized art names in DeviceArtwork.png's 4 × 3 sprite sheet.
atlas = ['mac', 'element', 'satechi', 'expansion', 'lacie', 'nvme',
         's4', 'z1', 'x1', 'monitor', 'ethernet', 'hub']
assets = {}
for name, file in [('atlas', 'DeviceArtwork.png'), ('elementPhoto', 'CalDigitHero.jpg'),
                   ('satechiPhoto', 'SatechiHero.jpg'), ('speakers', 'KlipschFives.jpg'),
                   ('maestro', 'MaestroDMX.jpg'), ('scarlett', 'Scarlett4i4.jpg')]:
    path = RESOURCES / file
    mime = 'image/png' if path.suffix == '.png' else 'image/jpeg'
    assets[name] = f'data:{mime};base64,' + base64.b64encode(path.read_bytes()).decode()

# Card rectangles: 180 × 140, in a 1560 × 740 design canvas.
layouts = {
    'atlas': {
        'mac': (700, 10), 'satechi': (250, 210), 'element': (1030, 210),
        'lacie': (40, 10), 'ether5': (250, 10), 'hdmi': (1300, 10),
        'expansion': (10, 410), 'satechiSSD': (210, 410), 'usbStorage': (410, 410), 'ether25': (610, 410),
        'z1': (810, 410), 's4': (1010, 410), 'nvme': (1210, 410),
        'display12': (620, 210), 'displayDP': (820, 210),
        'x1': (810, 600), 'speakers': (1010, 600), 'maestro': (1210, 600), 'scarlett': (1410, 600),
    },
    'signal': {
        'mac': (20, 290), 'satechi': (240, 30), 'element': (240, 550),
        'expansion': (460, 30), 'satechiSSD': (680, 30), 'usbStorage': (900, 30), 'ether25': (1120, 30),
        'z1': (460, 290), 's4': (680, 290), 'x1': (900, 290), 'nvme': (1120, 290),
        'display12': (460, 550), 'displayDP': (680, 550), 'ether5': (900, 550), 'hdmi': (1120, 550),
        'lacie': (20, 550), 'speakers': (1340, 30), 'maestro': (1340, 290), 'scarlett': (1340, 550),
    },
    'orbit': {
        'mac': (680, 290), 'satechi': (240, 290), 'element': (1120, 290),
        'expansion': (20, 30), 'satechiSSD': (240, 30), 'usbStorage': (460, 30), 'hdmi': (680, 30),
        'display12': (900, 30), 'displayDP': (1120, 30), 'nvme': (1340, 30),
        'ether5': (20, 290), 'lacie': (1340, 290),
        'ether25': (20, 550), 'scarlett': (240, 550), 'maestro': (460, 550), 'speakers': (680, 550),
        'z1': (900, 550), 's4': (1120, 550), 'x1': (1340, 550),
    },
}
# Fix the wide fourth-level row in atlas without changing its hierarchy.
layouts['atlas']['scarlett'] = (1380, 600)
# Atlas cards use a slightly narrower frame, fitting the final audio chain.
CARD_W, CARD_H, WIDTH, HEIGHT, GRID = 180, 140, 1560, 780, 10


def route_edges(positions, sizes=None, width=WIDTH, height=HEIGHT):
    sizes = sizes or {}
    occupied = set()
    for id, (x, y) in positions.items():
        w, h = sizes.get(id, {}).get("width", CARD_W), sizes.get(id, {}).get("height", CARD_H)
        for gx in range((x - 10) // GRID, (x + w + 10) // GRID + 1):
            for gy in range((y - 10) // GRID, (y + h + 10) // GRID + 1):
                occupied.add((gx, gy))
    reserved = {}
    routes = {}

    def anchor(id, side):
        x, y = positions[id]
        w, h = sizes.get(id, {}).get("width", CARD_W), sizes.get(id, {}).get("height", CARD_H)
        edge = {'r': (x + w, y + h // 2), 'l': (x, y + h // 2),
                't': (x + w // 2, y), 'b': (x + w // 2, y + h)}[side]
        delta = {'r': (20, 0), 'l': (-20, 0), 't': (0, -20), 'b': (0, 20)}[side]
        return edge, ((edge[0] + delta[0]) // GRID, (edge[1] + delta[1]) // GRID)

    def find_path(start, target):
        pending = [(0, 0, start, -1)]
        cost = {(start, -1): 0}
        parent = {}
        while pending:
            _, spent, point, direction = heapq.heappop(pending)
            state = (point, direction)
            if spent != cost.get(state):
                continue
            if point == target:
                points = [point]
                while state in parent:
                    state = parent[state]
                    points.append(state[0])
                return list(reversed(points)), spent
            for nd, (dx, dy) in enumerate([(1, 0), (0, 1), (-1, 0), (0, -1)]):
                p = (point[0] + dx, point[1] + dy)
                if not (0 <= p[0] <= width // GRID and 0 <= p[1] <= height // GRID):
                    continue
                if p in occupied and p not in (start, target):
                    continue
                next_cost = spent + 1 + (0.55 if direction not in (-1, nd) else 0) + reserved.get(p, 0) * 0.8
                next_state = (p, nd)
                if next_cost < cost.get(next_state, float('inf')):
                    cost[next_state] = next_cost
                    parent[next_state] = state
                    heuristic = abs(p[0] - target[0]) + abs(p[1] - target[1])
                    heapq.heappush(pending, (next_cost + heuristic, next_cost, p, nd))
        return None, float('inf')

    for d in nodes:
        if not d['parent']:
            continue
        source, target = positions[d['parent']], positions[d['id']]
        dx, dy = target[0] - source[0], target[1] - source[1]
        # Try three pairs of ports; prefer the shortest route with few turns.
        preferred = [('r', 'l')] if dx > 0 else [('l', 'r')]
        vertical = ('b', 't') if dy > 0 else ('t', 'b')
        candidates = list(dict.fromkeys(([vertical] + preferred if abs(dy) > abs(dx) else preferred + [vertical]) + [('b', 'b'), ('t', 't')]))
        best = None
        for a, b in candidates:
            edge_a, start = anchor(d["parent"], a)
            edge_b, end = anchor(d["id"], b)
            if start in occupied or end in occupied or not all(0 <= p[0] <= width // GRID and 0 <= p[1] <= height // GRID for p in (start, end)):
                continue
            points, score = find_path(start, end)
            if points and (best is None or score < best[0]):
                best = score, edge_a, edge_b, points
        if best is None:
            raise ValueError(f'No path to {d["id"]}')
        _, edge_a, edge_b, points = best
        for p in points:
            reserved[p] = reserved.get(p, 0) + 1
        points = [edge_a] + [(x * GRID, y * GRID) for x, y in points] + [edge_b]
        reduced = [points[0]]
        for i in range(1, len(points) - 1):
            a, b, c = reduced[-1], points[i], points[i + 1]
            if (a[0] == b[0] == c[0]) or (a[1] == b[1] == c[1]):
                continue
            reduced.append(b)
        reduced.append(points[-1])
        routes[d['id']] = 'M ' + ' L '.join(f'{x} {y}' for x, y in reduced)
    return routes

# Atlas final chain must not overlap the penultimate image card.
layouts['atlas']['x1'] = (700, 600)
layouts['atlas']['speakers'] = (920, 600)
layouts['atlas']['maestro'] = (1140, 600)
layouts['atlas']['scarlett'] = (1360, 600)

def main():
    payload = dict(nodes=nodes, layouts=layouts, routes={key: route_edges(pos) for key, pos in layouts.items()}, assets=assets, atlas=atlas)
    page = (HERE / 'mockups.template.html').read_text()
    page = page.replace('/*__DATA__*/', 'const DATA = ' + json.dumps(payload, separators=(',', ':')) + ';')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(page)
    print(f'Built {OUT} ({OUT.stat().st_size:,} bytes), {len(nodes)} cards in each of 3 designs')


if __name__ == "__main__":
    main()
