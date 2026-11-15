from pathlib import Path
p=Path('work/port-map-source/SetupView.swift');s=p.read_text()
a=s.index('struct OverviewView: View {');b=s.index('\nprivate struct OverviewDevice:',a)
s=s[:a]+'''struct OverviewView: View {
    let scan: PortScan
    @State private var selectedID: String?
    @State private var showInterfaces = false
    @State private var showPaths = true

    var body: some View {
        let items = OverviewInventory(scan: scan)
        let target = items.devices.first { $0.id == selectedID }
            ?? items.devices.first { $0.art == .nvme }
            ?? items.devices.first { $0.id != "host" }
            ?? items.devices.first!
        let trace = OverviewTrace(devices: items.devices, targetID: target.id)
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your connected setup").font(.title2.weight(.semibold))
                    Text("Select a device to trace its route; use its info button for details")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("All paths", isOn: $showPaths).toggleStyle(.switch).controlSize(.small)
                Button("Interfaces (\\(items.interfaces.count))") { showInterfaces.toggle() }
                    .popover(isPresented: $showInterfaces) { OverviewInterfaces(interfaces: items.interfaces) }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(trace.devices.map(\\.routeTitle).joined(separator: "  →  "))
                    .font(.system(size: 14, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                Text(trace.devices.dropFirst().compactMap { $0.wire?.label }.joined(separator: "    •    "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24).padding(.bottom, 5)
            .accessibilityIdentifier("connection-breadcrumb")
            GeometryReader { geometry in
                let layout = OverviewLayout(items: items.devices)
                let scale = min(geometry.size.width / layout.size.width, geometry.size.height / layout.size.height)
                ZStack(alignment: .topLeading) {
                    OverviewTiers(size: layout.size, tiers: layout.tiers)
                    OverviewConnections(devices: items.devices, frames: layout.frames,
                                        selectedID: target.id, showAll: showPaths)
                    ForEach(items.devices) { device in
                        if let frame = layout.frames[device.id], !(layout.hasStack && (device.id == "host" || device.art == .satechi)) {
                            OverviewCard(device: device, selected: trace.ids.contains(device.id)) { selectedID = device.id }
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                    if layout.hasStack, let stand = items.devices.first(where: { $0.art == .satechi }),
                       let host = items.devices.first(where: { $0.id == "host" }), let frame = layout.stackFrame {
                        OverviewStack(host: host, stand: stand, selectedIDs: trace.ids) { selectedID = $0 }
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .scaleEffect(scale, anchor: .center)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .clipped()
            HStack(spacing: 12) {
                Label("Highlighted route", systemImage: "line.diagonal").foregroundStyle(Color.accentColor)
                Text("– –  Through interfaces / unverified cable").foregroundStyle(.secondary)
                Spacer()
                Text("Cable routing is schematic").foregroundStyle(.secondary)
            }
            .font(.caption).padding(.horizontal, 24).padding(.top, 5).padding(.bottom, 10)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.32))
        .accessibilityIdentifier("physical-overview")
    }
}

private struct OverviewTrace {
    let devices: [OverviewDevice]
    var ids: Set<String> { Set(devices.map(\\.id)) }
    init(devices: [OverviewDevice], targetID: String) {
        var path: [OverviewDevice] = []
        var seen = Set<String>()
        var current: String? = targetID
        while let id = current, !seen.contains(id), let node = devices.first(where: { $0.id == id }) {
            seen.insert(id)
            path.append(node)
            current = node.parentID
        }
        self.devices = path.reversed()
    }
}
''' +s[b:]
s=s.replace('''    var isHub = false
    var subtitle''','''    var isHub = false
    var routeTitle: String {
        if art == .nvme, detail?.contains("2TB") == true { return "ASMedia NVMe · 2TB" }
        return title
    }
    var subtitle''',1)
a=s.index('private struct OverviewLayout {');b=s.index('\nprivate struct OverviewCard:',a)
s=s[:a]+'''private struct OverviewLayout {
    let size: CGSize
    var frames: [String: CGRect] = [:]
    var tiers: [(CGFloat, CGFloat, String)] = []
    let hasStack: Bool
    var stackFrame: CGRect?

    init(items: [OverviewDevice]) {
        hasStack = items.contains { $0.id == "host" } && items.contains { $0.art == .satechi }
        let monitors = items.filter { $0.category == 0 }
        let display12 = monitors.first { $0.title.lowercased() == "12.3fhd" }
        let upperDisplay = monitors.first { $0.title.lowercased() == "ingnok" && $0.port?.group != "Display" }
        let hdmi = monitors.first { $0.title.lowercased() == "ingnok" && $0.port?.group == "Display" }
        let confirmed = display12 != nil && upperDisplay != nil && monitors.count <= 3
        let besideDisplay = confirmed ? items.first { $0.art == .twister } : nil
        let controllers = items.filter { $0.category == 1 && $0.id != besideDisplay?.id }.sorted {
            let order: [DeviceArt: Int] = [.z1: 0, .s4: 1, .x1: 2, .twister: 3]
            return (order[$0.art ?? .hub] ?? 3) < (order[$1.art ?? .hub] ?? 3)
        }
        var nextY: CGFloat = 0
        if confirmed, let display12, let upperDisplay {
            let displayX: CGFloat = hdmi == nil ? 310 : 174
            tiers.append((0, 167, "UPPER DISPLAY"))
            frames[upperDisplay.id] = CGRect(x: displayX, y: 10, width: 340, height: 146)
            tiers.append((170, 167, "LOWER DISPLAY"))
            frames[display12.id] = CGRect(x: displayX, y: 180, width: 340, height: 146)
            if let besideDisplay { frames[besideDisplay.id] = CGRect(x: displayX + 374, y: 180, width: 200, height: 146) }
            if let hdmi { frames[hdmi.id] = CGRect(x: displayX + 606, y: 180, width: 246, height: 146) }
            nextY = 340
        } else if !monitors.isEmpty {
            tiers.append((0, 207, "DISPLAYS"))
            for (index, device) in monitors.enumerated() {
                let step = 1128 / CGFloat(monitors.count)
                let width = min(340, step - 18)
                frames[device.id] = CGRect(x: 36 + step * (CGFloat(index) + 0.5) - width / 2, y: 12, width: width, height: 174)
            }
            nextY = 215
        }
        if !controllers.isEmpty {
            let tierHeight: CGFloat = confirmed ? 187 : 207
            tiers.append((nextY, tierHeight, "DJ CONTROLLERS"))
            for (index, device) in controllers.enumerated() {
                let step = 1000 / CGFloat(controllers.count)
                let width = min(device.art == .s4 ? 330 : 260, step - 18)
                frames[device.id] = CGRect(x: 100 + step * (CGFloat(index) + 0.5) - width / 2, y: nextY + 12,
                                          width: width, height: confirmed ? 158 : 168)
            }
            nextY += tierHeight + 3
        }
        let others = items.filter { $0.category == 3 }
        let element = others.first { $0.art == .element }
        let nvme = others.first { $0.art == .nvme && $0.parentID == element?.id }
        var slots: [Int: OverviewDevice] = [:]
        if let element { slots[0] = element }
        if let nvme { slots[4] = nvme }
        var slot = 0
        for item in others where item.id != element?.id && item.id != nvme?.id {
            while slots[slot] != nil { slot += 1 }
            slots[slot] = item
        }
        let rows = max(2, (slots.keys.max() ?? 0) / 4 + 1)
        let groundHeight = max(282, CGFloat(rows) * 136 + 12)
        tiers.append((nextY, groundHeight, "GROUND LEVEL"))
        frames["host"] = CGRect(x: 460, y: nextY + 12, width: 280, height: 138)
        if let stand = items.first(where: { $0.art == .satechi }) {
            frames[stand.id] = CGRect(x: 460, y: nextY + 118, width: 280, height: 134)
            stackFrame = CGRect(x: 460, y: nextY + 12, width: 280, height: 240)
        }
        for (index, device) in slots {
            let x: CGFloat = [22, 234, 766, 978][index % 4]
            frames[device.id] = CGRect(x: x, y: nextY + 20 + CGFloat(index / 4) * 136, width: 200, height: 106)
        }
        size = CGSize(width: 1200, height: nextY + groundHeight + 12)
    }
}

private struct OverviewEdge {
    let childID: String
    let parentID: String
    let points: [CGPoint]
    let label: String?
    let labelPoint: CGPoint?
}

private enum OverviewRouting {
    static func edges(devices: [OverviewDevice], frames: [String: CGRect]) -> [OverviewEdge] {
        devices.compactMap { child in
            guard let parentID = child.parentID, let parent = devices.first(where: { $0.id == parentID }),
                  let source = frames[parentID], let target = frames[child.id] else { return nil }
            var points: [CGPoint]
            var labelPoint: CGPoint?
            var label: String?
            let rate = child.wire?.label.components(separatedBy: " · ").last
            if parentID == "host" && child.art == .element {
                let laneY = min(source.minY, target.minY) - 16
                points = [CGPoint(x: source.minX, y: source.midY), CGPoint(x: source.minX - 12, y: source.midY),
                          CGPoint(x: source.minX - 12, y: laneY), CGPoint(x: target.midX, y: laneY), CGPoint(x: target.midX, y: target.minY)]
                label = [child.subtitle, rate].compactMap { $0 }.joined(separator: " · ")
                labelPoint = CGPoint(x: (source.minX - 12 + target.midX) / 2, y: laneY)
            } else if parent.art == .element && child.art == .nvme && abs(source.midX - target.midX) < 1 {
                points = [CGPoint(x: source.midX, y: source.maxY), CGPoint(x: target.midX, y: target.minY)]
                label = rate
                labelPoint = CGPoint(x: source.midX + 76, y: (source.maxY + target.minY) / 2)
            } else if parentID == "host" && child.art == .satechi {
                points = [CGPoint(x: source.maxX, y: source.midY), CGPoint(x: source.maxX + 8, y: source.midY),
                          CGPoint(x: target.maxX + 8, y: target.midY), CGPoint(x: target.maxX, y: target.midY)]
            } else if parent.category == 1 && child.category == 1 {
                let laneY = max(source.maxY, target.maxY) + 10
                points = [CGPoint(x: source.midX, y: source.maxY), CGPoint(x: source.midX, y: laneY),
                          CGPoint(x: target.midX, y: laneY), CGPoint(x: target.midX, y: target.maxY)]
            } else if child.category == 0 || child.category == 1 {
                let railX: CGFloat = target.midX < 600 ? 12 : 1188
                let startY = source.minY - 12
                let endY = target.maxY + 10
                points = [CGPoint(x: source.midX, y: source.minY), CGPoint(x: source.midX, y: startY),
                          CGPoint(x: railX, y: startY), CGPoint(x: railX, y: endY),
                          CGPoint(x: target.midX, y: endY), CGPoint(x: target.midX, y: target.maxY)]
            } else {
                let toRight = target.midX > source.midX
                let edgeX = toRight ? source.maxX : source.minX
                let railX = edgeX + (toRight ? 8 : -8)
                let isBottom = target.midY > (frames["host"]?.midY ?? source.midY) + 60
                let laneY = isBottom ? target.maxY + 10 : (frames["host"]?.minY ?? target.minY) - 14
                let endpointY = isBottom ? target.maxY : target.minY
                points = [CGPoint(x: edgeX, y: source.midY), CGPoint(x: railX, y: source.midY),
                          CGPoint(x: railX, y: laneY), CGPoint(x: target.midX, y: laneY), CGPoint(x: target.midX, y: endpointY)]
            }
            return OverviewEdge(childID: child.id, parentID: parentID, points: points, label: label, labelPoint: labelPoint)
        }
    }
}

private struct OverviewConnections: View {
    let devices: [OverviewDevice]
    let frames: [String: CGRect]
    let selectedID: String?
    let showAll: Bool

    var body: some View {
        Canvas { context, _ in
            let traced = OverviewTrace(devices: devices, targetID: selectedID ?? "host").ids
            let edges = OverviewRouting.edges(devices: devices, frames: frames)
            // Draw the focused route last, on top of unrelated paths.
            for edge in edges.sorted(by: { (traced.contains($0.childID) ? 1 : 0) < (traced.contains($1.childID) ? 1 : 0) }) {
                let active = traced.contains(edge.childID) && traced.contains(edge.parentID)
                guard showAll || active, let start = edge.points.first,
                      let child = devices.first(where: { $0.id == edge.childID }) else { continue }
                var path = Path(); path.move(to: start)
                for point in edge.points.dropFirst() { path.addLine(to: point) }
                let color = active ? Color.accentColor : (child.wire?.color ?? .secondary)
                let style = StrokeStyle(lineWidth: active ? 3.5 : 1.6, lineCap: .round, lineJoin: .round,
                                        dash: child.indirect ? [7, 5] : [])
                if active { context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)) }
                context.stroke(path, with: .color(color.opacity(active ? 1 : 0.24)), style: style)
                for point in [edge.points.first, edge.points.last].compactMap({ $0 }) {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(color.opacity(active ? 1 : 0.35)))
                }
                if active, let label = edge.label, let point = edge.labelPoint {
                    let resolved = context.resolve(Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.accentColor))
                    let textSize = resolved.measure(in: CGSize(width: 240, height: 24))
                    let rect = CGRect(x: point.x - textSize.width / 2 - 7, y: point.y - 10, width: textSize.width + 14, height: 20)
                    context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(Color(nsColor: .windowBackgroundColor)))
                    context.draw(resolved, at: point)
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
''' +s[b:]
# Card selection traces immediately; a separate info action opens details.
a=s.index('private struct OverviewCard:');b=s.index('private struct OverviewInspector:',a)
card=s[a:b].replace('''            select()
            showDetails = true''','''            select()''',1)
card=card.replace('''        .help("Inspect \\(device.title) · \\(device.subtitle)")''','''        .help("Trace \\(device.title) · \\(device.subtitle)")
        .overlay(alignment: .topTrailing) {
            Button { showDetails = true } label: {
                Image(systemName: "info.circle").font(.system(size: 14)).padding(7)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Inspect \\(device.title)")
            .accessibilityLabel("Inspect \\(device.title)")
        }''',1)
s=s[:a]+card+s[b:]
# Remove the former hub-only spatial reference card; HDMI is a real full-view node again.
a=s.find('// User-requested physical context, intentionally separate from hub membership/edges.')
if a!=-1:s=s[:a]
s+='''

private struct OverviewStack: View {
    let host: OverviewDevice
    let stand: OverviewDevice
    let selectedIDs: Set<String>
    let select: (String) -> Void
    @State private var inspectHost = false
    @State private var inspectStand = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { select(host.id) } label: {
                    Text(host.title).font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity)
                }
                Button { inspectHost = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Inspect Mac mini")
            }
            .buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 4)
            .popover(isPresented: $inspectHost) { OverviewInspector(device: host) }
            GeometryReader { geometry in
                Button { select(host.id) } label: {
                    ZStack {
                        if let image = DeviceArt.satechi.image {
                            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                                .frame(width: 210, height: 175).offset(y: 20)
                        }
                        if let image = DeviceArt.macMini.image {
                            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                                .frame(width: 200, height: 160).offset(y: -13)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Trace Mac mini sitting on Satechi Stand & Hub")
            }
            HStack {
                Button { select(stand.id) } label: {
                    VStack(spacing: 2) {
                        Text(stand.title).font(.system(size: 13, weight: .semibold))
                        Text(stand.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }
                Button { inspectStand = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Inspect Satechi Stand & Hub")
            }
            .buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 10)
            .popover(isPresented: $inspectStand) { OverviewInspector(device: stand) }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(selectedIDs.contains(host.id) || selectedIDs.contains(stand.id) ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}
'''
p.write_text(s)
