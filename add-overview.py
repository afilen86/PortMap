from pathlib import Path
p=Path('work/port-map-source/PortMapApp.swift')
s=p.read_text().replace('.frame(minWidth: 680, minHeight: 510)', '.frame(minWidth: 920, minHeight: 680)').replace('.defaultSize(width: 980, height: 700)', '.defaultSize(width: 1280, height: 900)').replace('@AppStorage("mapView") private var mode: MapMode = .setup','@AppStorage("mapViewV12") private var mode: MapMode = .overview')
s=s.replace('portPicker(scan)\n                    Divider()\n                    if mode == .setup {', 'if mode != .overview {\n                        portPicker(scan)\n                        Divider()\n                    }\n                    if mode == .overview {\n                        OverviewView(scan: scan)\n                    } else if mode == .setup {')
s=s.replace('Text("Setup").tag(MapMode.setup)', 'Text("Overview").tag(MapMode.overview)\n                Text("Setup").tag(MapMode.setup)').replace('.frame(width: 138)', '.frame(width: 242)').replace('case setup, ports','case overview, setup, ports')
p.write_text(s)
