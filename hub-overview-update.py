from pathlib import Path
p=Path('work/port-map-source/SetupView.swift');s=p.read_text()
a=s.index('struct OverviewView: View {');b=s.index('\nprivate struct OverviewDevice:',a)
s=s[:a]+'''struct OverviewView: View {
    let scan: PortScan
    @State private var selectedHubID: String?
    @State private var selectedID: String?
    @State private var showInterfaces = false
    @State private var showPaths = true

    var body: some View {
        let all = OverviewInventory(scan: scan)
        let hubs = all.hubs
        let hub = hubs.first { $0.id == selectedHubID } ?? hubs.first
        VStack(spacing: 0) {
            if let hub {
                let items = all.branch(rootID: hub.id)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hub connections").font(.title2.weight(.semibold))
                            Text("Only devices downstream of the selected hub · select a device to trace its route")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Paths", isOn: $showPaths).toggleStyle(.switch).controlSize(.small)
                        Button("Interfaces (\\(items.interfaces.count))") { showInterfaces.toggle() }
                            .popover(isPresented: $showInterfaces) {
                                OverviewInterfaces(interfaces: items.interfaces)
                            }
                    }
                    Picker("Hub", selection: Binding(get: { hub.id }, set: { value in
                        selectedHubID = value
                        selectedID = nil
                        showInterfaces = false
                    })) {
                        ForEach(hubs) { option in Text(option.title).tag(option.id) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .accessibilityIdentifier("hub-selector")
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
                GeometryReader { geometry in
                    let layout = OverviewLayout(items: items.devices, rootID: hub.id)
                    let scale = min(geometry.size.width / layout.size.width, geometry.size.height / layout.size.height)
                    ZStack(alignment: .topLeading) {
                        OverviewTiers(size: layout.size, tiers: layout.tiers)
                        OverviewConnections(devices: items.devices, frames: layout.frames,
                                            selectedID: selectedID, showAll: showPaths)
                        ForEach(items.devices) { device in
                            if let frame = layout.frames[device.id] {
                                OverviewCard(device: device, selected: selectedID == device.id) {
                                    selectedID = selectedID == device.id ? nil : device.id
                                }
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .frame(width: layout.size.width, height: layout.size.height)
                    .scaleEffect(scale, anchor: .center)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .clipped()
                .id(hub.id)
                HStack(spacing: 14) {
                    Label("Reported connection", systemImage: "line.diagonal").foregroundStyle(.teal)
                    Text("– –  Through interfaces / unverified cable").foregroundStyle(.secondary)
                    Spacer()
                    Text("Illustrative placement").foregroundStyle(.secondary)
                }
                .font(.caption).padding(.horizontal, 24).padding(.top, 5).padding(.bottom, 10)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("No connected hub detected").font(.title2.weight(.semibold))
                    Text("Connect a hub and click Refresh. Setup and Ports still show all detected connections.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.32))
        .accessibilityIdentifier("hub-overview")
    }
}
''' +s[b:]
s=s.replace('    var stack = false\n','    var isHub = false\n',1)
s=s.replace('''private struct OverviewInterface: Identifiable {
    let id: String''','''private struct OverviewInterface: Identifiable {
    let parentID: String
    let id: String''',1)
s=s.replace('    var hasStack: Bool { devices.contains { $0.art == .satechi } }','''    var hubs: [OverviewDevice] { devices.filter(\\.isHub) }

    private init(devices: [OverviewDevice], interfaces: [OverviewInterface]) {
        self.devices = devices
        self.interfaces = interfaces
    }

    func branch(rootID: String) -> Self {
        guard devices.contains(where: { $0.id == rootID }) else {
            return Self(devices: [], interfaces: [])
        }
        var included: Set<String> = [rootID]
        var previousCount = 0
        while included.count != previousCount {
            previousCount = included.count
            for device in devices {
                if let parent = device.parentID, included.contains(parent) { included.insert(device.id) }
            }
        }
        return Self(devices: devices.filter { included.contains($0.id) },
                    interfaces: interfaces.filter { included.contains($0.parentID) })
    }''',1)
s=s.replace('''        if let host = devices.firstIndex(where: { $0.id == "host" }) {
            devices[host].stack = devices.contains { $0.art == .satechi }
        }
''','',1)
s=s.replace('''        let physical = node.art != nil || isStorageEndpoint''','''        let identifiedHub = node.art == .element || node.art == .satechi
            || (node.id.hasPrefix("switch-") && node.title.localizedCaseInsensitiveContains("hub"))
        let physical = node.art != nil || isStorageEndpoint || identifiedHub''',1)
s=s.replace('''            devices.append(OverviewDevice(id: id, title: node.title, art: node.art,''','''            devices.append(OverviewDevice(id: id, title: node.title, art: node.art ?? (identifiedHub ? .hub : nil),''',1)
s=s.replace('''indirect: indirect || (node.wire?.dashed ?? false), category: category))''','''indirect: indirect || (node.wire?.dashed ?? false), category: category, isHub: identifiedHub))''',1)
s=s.replace('OverviewInterface(id: id, title:', 'OverviewInterface(parentID: parent, id: id, title:',1)
a=s.index('private struct OverviewLayout {');b=s.index('\nprivate struct OverviewConnections:',a)
s=s[:a]+'''private struct OverviewLayout {
    let size: CGSize
    var frames: [String: CGRect] = [:]
    var tiers: [(CGFloat, CGFloat, String)] = []

    init(items: [OverviewDevice], rootID: String) {
        let monitors = items.filter { $0.category == 0 && $0.id != rootID }
        let controllers = items.filter { $0.category == 1 && $0.id != rootID }.sorted {
            let order: [DeviceArt: Int] = [.z1: 0, .s4: 1, .x1: 2]
            return (order[$0.art ?? .hub] ?? 3) < (order[$1.art ?? .hub] ?? 3)
        }
        let others = items.filter { $0.category != 0 && $0.category != 1 && $0.id != rootID }
        var nextY: CGFloat = 0
        if !monitors.isEmpty {
            tiers.append((nextY, 207, "DISPLAYS ON THIS HUB"))
            for (index, device) in monitors.enumerated() {
                let step = 1128 / CGFloat(monitors.count)
                let width = min(340, step - 18)
                frames[device.id] = CGRect(x: 36 + step * (CGFloat(index) + 0.5) - width / 2,
                                          y: nextY + 12, width: width, height: 174)
            }
            nextY += 215
        }
        if !controllers.isEmpty {
            tiers.append((nextY, 207, "DJ CONTROLLERS ON THIS HUB"))
            for (index, device) in controllers.enumerated() {
                let step = 1000 / CGFloat(controllers.count)
                let width = min(device.art == .s4 ? 330 : 260, step - 18)
                frames[device.id] = CGRect(x: 100 + step * (CGFloat(index) + 0.5) - width / 2,
                                          y: nextY + 12, width: width, height: 168)
            }
            nextY += 215
        }
        let lowerHeight = max(264, CGFloat(Int(ceil(Double(others.count) / 4))) * 118 + 28)
        tiers.append((nextY, lowerHeight, "SELECTED HUB & CONNECTED DEVICES"))
        frames[rootID] = CGRect(x: 460, y: nextY + 12, width: 280, height: 226)
        for (index, device) in others.enumerated() {
            let column = index % 4
            let x: CGFloat = [22, 234, 766, 978][column]
            frames[device.id] = CGRect(x: x, y: nextY + 20 + CGFloat(index / 4) * 118,
                                      width: 200, height: 106)
        }
        size = CGSize(width: 1200, height: nextY + lowerHeight + 12)
    }
}
''' +s[b:]
s=s.replace('''            } else if device.id == "host" && device.stack {
                Text("Mac mini above Satechi Stand & Hub, following your desk arrangement.").foregroundStyle(.secondary)
''','\n',1)
a=s.index('\nprivate struct OverviewStack: View {');b=s.index('// Decorative shelf context',a)
s=s[:a]+'\n\n'+s[b:]
s=s.replace('''    let size: CGSize
    var body: some View {
        Canvas { context, _ in
            let tiers: [(CGFloat, CGFloat, String)] = [
                (0, 207, "MONITORS"),
                (215, 207, "DJ CONTROLLERS"),
                (434, size.height - 434, "GROUND LEVEL")
            ]''','''    let size: CGSize
    let tiers: [(CGFloat, CGFloat, String)]
    var body: some View {
        Canvas { context, _ in''',1)
s=s.replace('''            // Small supports suggest the raised DJ shelf without adding graph nodes.
            for x: CGFloat in [48, size.width - 52] {
                let support = CGRect(x: x, y: 420, width: 4, height: 19)
                context.fill(Path(roundedRect: support, cornerRadius: 2), with: .color(.primary.opacity(0.13)))
            }
''','',1)
p.write_text(s)
