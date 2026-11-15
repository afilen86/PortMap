import AppKit
import SwiftUI

struct SetupView: View {
    let scan: PortScan
    let port: Port?

    private var ports: [Port] { port.map { [$0] } ?? scan.ports.filter(\.connected) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connected setup")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Device illustrations · solid cable paths · dashed internal or unverified paths")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    SetupDeviceRow(device: SetupDevice(
                        id: "mac", title: scan.isMacMini ? "Mac mini M4" : "This Mac",
                        detail: port == nil ? "All connected ports" : "Selected port",
                        art: scan.isMacMini ? .macMini : nil, icon: "desktopcomputer",
                        wire: nil, children: []
                    ))
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                            SetupPortBranch(port: port, last: index == ports.count - 1)
                        }
                    }
                    .padding(.leading, 17)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 810, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(port?.id ?? "all")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("setup-map")
    }
}

private struct SetupPortBranch: View {
    let port: Port
    let last: Bool
    @State private var showCable = false

    private var heading: String {
        switch port.group {
        case "Rear Thunderbolt": "Rear \(port.position.lowercased())"
        case "Display": "Rear HDMI"
        default: "\(port.group) \(port.position)"
        }
    }

    var body: some View {
        let devices = SetupDevice.nodes(for: port)
        let wire = SetupWire.host(port)
        VStack(alignment: .leading, spacing: 7) {
            if port.connected {
                Button {
                    showCable.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Text(heading).font(.subheadline.weight(.semibold))
                        Text(wire.label).font(.caption.weight(.medium)).foregroundStyle(wire.color)
                        ConnectorArtwork(connector: wire.connector, width: 41, height: 25)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 29)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Inspect the cable at \(heading)")
                .popover(isPresented: $showCable, arrowEdge: .bottom) {
                    CableDetails(wire: wire, port: port, heading: heading)
                }
            } else {
                Text(heading).font(.subheadline.weight(.semibold)).frame(minHeight: 29)
            }
            if devices.isEmpty && !port.connected {
                Text("No device connected").font(.callout).foregroundStyle(.secondary)
            } else {
                SetupChildren(devices: devices)
            }
        }
        .padding(.leading, 29)
        .padding(.bottom, 10)
        .overlay(alignment: .topLeading) {
            CablePath(wire: wire, last: last, turnAt: 14, length: 24)
        }
    }
}

private struct CableDetails: View {
    let wire: SetupWire
    let port: Port
    let heading: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(heading).font(.headline)
            ConnectorArtwork(connector: wire.connector, width: 144, height: 84)
            if let connector = wire.connector {
                Text("\(connector.label) plug at the Mac · illustration")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(wire.label).font(.callout.weight(.semibold)).foregroundStyle(wire.color)
            Text(wire.explanation).foregroundStyle(.secondary)
            ForEach(port.cableMatches, id: \.self) { match in
                Text("WhatCable e-marker match · \(match)").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(width: 270, alignment: .leading)
        .padding(16)
    }
}

private struct SetupChildren: View {
    let devices: [SetupDevice]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                SetupBranch(device: device, last: index == devices.count - 1)
            }
        }
    }
}

private struct SetupBranch: View {
    let device: SetupDevice
    let last: Bool
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupDeviceRow(device: device, expanded: device.children.isEmpty ? nil : $expanded)
            if expanded && !device.children.isEmpty {
                SetupChildren(devices: device.children)
                    .padding(.leading, 13)
                    .padding(.top, 4)
            }
        }
        .padding(.leading, 25)
        .padding(.bottom, 5)
        .overlay(alignment: .topLeading) {
            if let wire = device.wire {
                CablePath(wire: wire, last: last, turnAt: device.art == nil ? 22 : 35, length: 25)
            }
        }
    }
}

private struct SetupDeviceRow: View {
    let device: SetupDevice
    var expanded: Binding<Bool>?
    @State private var showingDetails = false

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Button {
                showingDetails.toggle()
            } label: {
                HStack(spacing: 10) {
                    DeviceArtwork(art: device.art, icon: device.icon)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.title).font(.callout.weight(.semibold))
                        if let wire = device.wire {
                            Text(wire.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(wire.color)
                        } else if let detail = device.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: device.art == nil ? 37 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel([device.title, device.wire?.label].compactMap { $0 }.joined(separator: ", "))
            .help("Inspect \(device.title)")
            .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
                DeviceDetails(device: device)
            }
            if let expanded {
                Button {
                    expanded.wrappedValue.toggle()
                } label: {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(expanded.wrappedValue ? "Collapse \(device.title)" : "Expand \(device.title)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.primary.opacity(device.art == nil ? 0.028 : 0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.07))
                .allowsHitTesting(false)
        }
    }
}

private struct DeviceDetails: View {
    let device: SetupDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(device.title).font(.headline)
            if let detail = device.detail, !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
            if let wire = device.wire {
                Label(wire.label, systemImage: "cable.connector").foregroundStyle(wire.color)
                Text(wire.explanation).foregroundStyle(.secondary)
            }
            if device.art != nil {
                Text("Representative device illustration").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .multilineTextAlignment(.leading)
        .frame(width: 265, alignment: .leading)
        .padding(16)
    }
}

private struct CablePath: View {
    let wire: SetupWire
    let last: Bool
    let turnAt: CGFloat
    let length: CGFloat

    var body: some View {
        Canvas { context, size in
            let x: CGFloat = 6
            let bend: CGFloat = 7
            var cord = Path()
            cord.move(to: CGPoint(x: x, y: 0))
            cord.addLine(to: CGPoint(x: x, y: turnAt - bend))
            cord.addQuadCurve(to: CGPoint(x: x + bend, y: turnAt),
                              control: CGPoint(x: x, y: turnAt))
            cord.addLine(to: CGPoint(x: length, y: turnAt))
            context.stroke(cord, with: .color(wire.color.opacity(0.84)),
                           style: StrokeStyle(lineWidth: wire.dashed ? 1.3 : 2.3, lineCap: .round,
                                              dash: wire.dashed ? [3, 4] : []))
            if !last {
                let continuation = Path { path in
                    path.move(to: CGPoint(x: x, y: turnAt - bend))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(continuation, with: .color(.secondary.opacity(0.38)), lineWidth: 1)
            }
            let terminal = CGRect(x: length - 3, y: turnAt - 3, width: 6, height: 6)
            context.fill(Path(roundedRect: terminal, cornerRadius: 1.8), with: .color(wire.color))
        }
        .frame(width: length + 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DeviceArtwork: View {
    let art: DeviceArt?
    let icon: String

    var body: some View {
        if let art, let image = art.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 97, height: 62)
                .accessibilityHidden(true)
        } else {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 29, height: 27)
                .accessibilityHidden(true)
        }
    }
}

private enum DeviceArt: Int, CaseIterable {
    case macMini, element, satechi, expansion, lacie, nvme, s4, z1, x1, monitor, ethernet, hub, twister

    var image: NSImage? { self == .twister ? Self.twisterImage : Self.images[self] }

    private static let twisterImage: NSImage? = Bundle.main.url(forResource: "TwisterArtwork", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    private static let images = readAtlas("DeviceArtwork", columns: 4, rows: 3, cells: allCases.filter { $0 != .twister })
}

private enum ConnectorArt: Int, CaseIterable {
    case usbC, hdmi

    var label: String { self == .usbC ? "USB-C" : "HDMI" }
    var image: NSImage? { Self.images[self] }

    private static let images = readAtlas("CableArtwork", columns: 2, rows: 1, cells: allCases)
}

private struct ConnectorArtwork: View {
    let connector: ConnectorArt?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        if let image = connector?.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: height)
                .accessibilityHidden(true)
        }
    }
}

private func readAtlas<Cell: RawRepresentable & Hashable>(
    _ resource: String, columns: Int, rows: Int, cells: [Cell]
) -> [Cell: NSImage] where Cell.RawValue == Int {
    guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
          let atlas = NSImage(contentsOf: url),
          let bitmap = atlas.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [:] }
    let width = bitmap.width / columns
    let height = bitmap.height / rows
    return Dictionary(uniqueKeysWithValues: cells.compactMap { cell in
        let rect = CGRect(x: (cell.rawValue % columns) * width, y: (cell.rawValue / columns) * height,
                          width: width, height: height)
        guard let crop = bitmap.cropping(to: rect) else { return nil }
        return (cell, NSImage(cgImage: crop, size: rect.size))
    })
}

private struct SetupWire {
    let label: String
    let explanation: String
    let color: Color
    var dashed = false
    var connector: ConnectorArt? = nil

    static func host(_ port: Port) -> Self {
        if !port.connected {
            return Self(label: "Available", explanation: "", color: .secondary, dashed: true)
        }
        if port.group == "Display" {
            return Self(label: "HDMI", explanation: "HDMI port on the Mac. The display-end connector or adapter is unverified.",
                        color: .purple, connector: .hdmi)
        }
        if port.connections.contains(where: { $0.id.hasPrefix("switch-") }) {
            let explanation = port.cable.map { "WhatCable reports \($0)." }
                ?? "USB4 link detected. Cable specifications are unavailable."
            return Self(label: "Thunderbolt / USB4 · \(port.link)", explanation: explanation,
                        color: .indigo, connector: .usbC)
        }
        let speed = cleanSpeed(port.link) ?? port.link
        return Self(label: speed.hasPrefix("USB") ? speed : "USB-C · \(speed)",
                    explanation: "USB-C at the Mac. The other plug, cable color, and cable length are unverified.",
                    color: .teal, connector: .usbC)
    }

    static func device(_ node: Connection, port: Port, logical: Bool) -> Self {
        if node.id.hasPrefix("display-") {
            if port.group == "Display" { return host(port) }
            return Self(label: "DisplayPort tunnel",
                        explanation: "macOS reports display traffic through this port. The display-end cable is unverified.",
                        color: .purple, dashed: true)
        }
        if node.id.hasPrefix("switch-") {
            let speed = cleanSpeed(node.speed)
            return Self(label: ["Thunderbolt / USB4", speed].compactMap { $0 }.joined(separator: " · "),
                        explanation: "The Thunderbolt route is detected. The downstream cable's make, length, and appearance are unverified.",
                        color: .indigo)
        }
        let speed = cleanSpeed(node.speed)
        return Self(label: [logical ? "USB path" : "USB", speed].compactMap { $0 }.joined(separator: " · "),
                    explanation: logical
                        ? "This is a reported USB branch or interface. Its internal wiring and any external cable are unverified."
                        : "The USB path and link rate were detected. Connector types at the device, brand, color, and length are unverified.",
                    color: logical ? .secondary : .teal, dashed: logical)
    }

    private static func cleanSpeed(_ value: String?) -> String? {
        guard let value else { return nil }
        if let start = value.firstIndex(of: "("), let end = value.lastIndex(of: ")"), start < end {
            return cleanSpeed(String(value[value.index(after: start)..<end]))
        }
        return value.replacingOccurrences(of: "Gbps", with: "Gb/s")
            .replacingOccurrences(of: "Mbps", with: "Mb/s")
    }
}

private struct SetupDevice: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let art: DeviceArt?
    let icon: String
    let wire: SetupWire?
    var children: [Self]

    static func nodes(for port: Port) -> [Self] {
        let nodes = port.connections.map { build($0, port: port) }
        guard let stand = nodes.first(where: { $0.art == .satechi }),
              let companion = nodes.first(where: { $0.art == nil && $0.title == "Satechi USB 2 branch" }) else {
            return nodes
        }
        var dock = stand
        dock.children = [companion] + dock.children
        return [dock] + nodes.filter { $0.id != stand.id && $0.id != companion.id }
    }

    private static func build(_ node: Connection, port: Port) -> Self {
        let name = node.name.lowercased()
        let manufacturer = node.detail?.lowercased() ?? ""
        let normalizedName = name.filter { $0.isLetter || $0.isNumber }
        let title: String
        let art: DeviceArt?
        var logical = false
        switch name {
        case _ where normalizedName.contains("midifightertwister"):
            (title, art) = ("MIDI Fighter Twister", .twister)
        case "mac mini stand & hub": (title, art) = ("Satechi Stand & Hub", .satechi)
        case "element hub" where node.id.hasPrefix("switch-"):
            (title, art) = ("CalDigit Element Hub", .element)
        case "element hub":
            (title, art) = ("Element Hub management interface", nil)
            logical = true
        case "expansion hdd": (title, art) = ("Seagate Expansion Desktop", .expansion)
        case "p9227 slim": (title, art) = ("LaCie P9227 Slim", .lacie)
        case "246x" where manufacturer.contains("asmedia"):
            (title, art) = ("ASMedia 246x NVMe enclosure", .nvme)
        case "traktor kontrol s4 mk3 hub":
            (title, art) = ("Traktor Kontrol S4 MK3", .s4)
        case "traktor kontrol s4 mk3":
            (title, art) = ("S4 controller interface", nil)
            logical = true
        case "traktor z1 mk2": (title, art) = ("Traktor Z1 MK2", .z1)
        case "traktor x1 mk3": (title, art) = ("Traktor X1 MK3", .x1)
        case "touchscreen":
            (title, art) = ("Touchscreen USB interface", nil)
            logical = true
        case "usb2.0 hub" where manufacturer.contains("satechi"):
            (title, art) = ("Satechi USB 2 branch", nil)
            logical = true
        case "element usb 2.0 hub", "usb2.0 hub", "usb 2.0 hub", "usb3.0 hub":
            (title, art) = (node.name, nil)
            logical = true
        case "usb billboard device", "unnamed usb device", "satechi disk media", "usb storage":
            (title, art) = (node.name, nil)
            logical = true
        case let adapter where adapter.hasSuffix(" lan"):
            let lan = adapter.contains("5g_5g") ? "5 GbE" : "2.5 GbE"
            (title, art) = ("Realtek \(lan) adapter", manufacturer.contains("realtek") ? .ethernet : nil)
        case _ where node.id.hasPrefix("display-"): (title, art) = (node.name, .monitor)
        default:
            (title, art) = (node.name, nil)
            logical = true
        }
        let details = [node.detail?.isEmpty == false ? node.detail : nil,
                       art == .monitor || art == .ethernet || art == .nvme ? "Enclosure or chassis illustration is generic." : nil]
            .compactMap { $0 }
            .joined(separator: " ")
        return Self(id: node.id, title: title, detail: details, art: art, icon: art == .twister ? "slider.vertical.3" : node.icon,
                    wire: .device(node, port: port, logical: logical),
                    children: node.children.map { build($0, port: port) })
    }
}

// The overview arranges detected endpoints spatially. It never derives topology
// from their screen positions; each edge and inspector retains the scan path.
struct OverviewView: View {
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
                Button("Interfaces (\(items.interfaces.count))") { showInterfaces.toggle() }
                    .popover(isPresented: $showInterfaces) { OverviewInterfaces(interfaces: items.interfaces) }
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(trace.devices.map(\.routeTitle).joined(separator: "  →  "))
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
    var ids: Set<String> { Set(devices.map(\.id)) }
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

private struct OverviewDevice: Identifiable {
    let id: String
    let title: String
    let art: DeviceArt?
    let icon: String
    let port: Port?
    let path: [String]
    let detail: String?
    let wire: SetupWire?
    let parentID: String?
    let indirect: Bool
    let category: Int // display, controller, host/stand, other
    var isHub = false
    var routeTitle: String {
        if art == .nvme, detail?.contains("2TB") == true { return "ASMedia NVMe · 2TB" }
        return title
    }
    var subtitle: String {
        guard let port else { return "Host computer" }
        let location = port.group == "Display" ? "HDMI" : port.group == "Rear Thunderbolt" ? "Rear \(port.position.lowercased())" : "\(port.group) \(port.position)"
        return location
    }
}

private struct OverviewInterface: Identifiable {
    let parentID: String
    let id: String
    let title: String
    let path: [String]
    let detail: String?
}

private struct OverviewInventory {
    var devices: [OverviewDevice] = []
    var interfaces: [OverviewInterface] = []
    var hubs: [OverviewDevice] { devices.filter(\.isHub) }

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
    }

    init(scan: PortScan) {
        devices = [OverviewDevice(id: "host", title: scan.isMacMini ? "Mac mini M4" : "This Mac", art: scan.isMacMini ? .macMini : nil,
                                  icon: "desktopcomputer", port: nil, path: [], detail: nil, wire: nil, parentID: nil,
                                  indirect: false, category: 2)]
        for port in scan.ports where port.connected {
            for node in SetupDevice.nodes(for: port) {
                append(node, port: port, path: [port.id], parent: "host", indirect: false)
            }
        }
    }

    private mutating func append(_ node: SetupDevice, port: Port, path: [String], parent: String, indirect: Bool) {
        let fullPath = path + [node.title]
        let id = port.id + "/" + node.id
        let isStorageEndpoint = node.title.lowercased() == "usb storage" || node.title.lowercased() == "satechi disk media"
        let identifiedHub = node.art == .element || node.art == .satechi
            || (node.id.hasPrefix("switch-") && node.title.localizedCaseInsensitiveContains("hub"))
        let lowerTitle = node.title.lowercased()
        let knownInterface = lowerTitle.contains("interface") || lowerTitle.contains("hub")
            || lowerTitle.contains("branch") || ["unnamed usb device", "usb billboard device"].contains(lowerTitle)
        // Preserve named endpoints even when no model-specific illustration exists.
        let namedEndpoint = node.children.isEmpty && !knownInterface
        let physical = node.art != nil || isStorageEndpoint || identifiedHub || namedEndpoint
        var nextParent = parent
        if physical {
            let category = node.art == .monitor ? 0 : [.s4, .z1, .x1, .twister].contains(node.art) ? 1 : node.art == .satechi ? 2 : 3
            devices.append(OverviewDevice(id: id, title: node.title, art: node.art ?? (identifiedHub ? .hub : nil),
                                          icon: isStorageEndpoint ? "externaldrive" : node.icon, port: port, path: fullPath,
                                          detail: node.detail, wire: node.wire, parentID: parent,
                                          indirect: indirect || (node.wire?.dashed ?? false), category: category, isHub: identifiedHub))
            nextParent = id
        } else {
            interfaces.append(OverviewInterface(parentID: parent, id: id, title: node.title, path: fullPath, detail: node.detail))
        }
        for child in node.children {
            append(child, port: port, path: fullPath, parent: nextParent, indirect: !physical)
        }
    }
}

private struct OverviewLayout {
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

private struct OverviewCard: View {
    let device: OverviewDevice
    let selected: Bool
    let select: () -> Void
    @State private var showDetails = false

    var body: some View {
        Button {
            select()
        } label: {
            VStack(spacing: 2) {
                artwork
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(device.title).font(.system(size: device.category == 3 ? 12 : 14, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(device.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(device.category == 2 ? 0.80 : 0.92), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.09), lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .help("Trace \(device.title) · \(device.subtitle)")
        .overlay(alignment: .topTrailing) {
            Button { showDetails = true } label: {
                Image(systemName: "info.circle").font(.system(size: 14)).padding(7)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Inspect \(device.title)")
            .accessibilityLabel("Inspect \(device.title)")
        }
        .accessibilityLabel("\(device.title), \(device.subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .popover(isPresented: $showDetails) { OverviewInspector(device: device) }
    }

    @ViewBuilder private var artwork: some View {
        if let art = device.art, let image = art.image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .padding(.horizontal, device.category == 1 && (art == .z1 || art == .x1) ? 45 : 5)
                .accessibilityHidden(true)
        } else {
            Image(systemName: device.icon).resizable().scaledToFit().padding(12).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

private struct OverviewInspector: View {
    let device: OverviewDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(device.title).font(.headline)
            if let detail = device.detail, !detail.isEmpty { Text(detail).foregroundStyle(.secondary) }
            if !device.path.isEmpty {
                Text("Reported route").font(.subheadline.weight(.semibold))
                Text((["Mac"] + device.path).joined(separator: " → ")).textSelection(.enabled)
            }
            if let wire = device.wire {
                Text(wire.label).foregroundStyle(wire.color).fontWeight(.medium)
                Text(wire.explanation).foregroundStyle(.secondary)
            }
            if device.art == .monitor {
                Text("Shown as its own detected display path. Left-to-right placement is illustrative; matching names are not merged.")
                    .foregroundStyle(.secondary)

            }
            Text(device.art == nil && device.port != nil ? "Reported endpoint; physical enclosure not identified." : "Representative illustration; cable routing on screen is schematic.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout).padding(18).frame(width: 340, alignment: .leading)
    }
}

private struct OverviewInterfaces: View {
    let interfaces: [OverviewInterface]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reported interfaces").font(.headline)
            Text("Internal hubs, management and unclassified interfaces stay attached to their detected routes. They are not counted as extra physical boxes.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(interfaces) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.callout.weight(.semibold))
                            Text(item.path.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let detail = item.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(18).frame(width: 420, height: 400)
    }
}



// Decorative shelf context follows the user's three levels, not a measured room model.
private struct OverviewTiers: View {
    let size: CGSize
    let tiers: [(CGFloat, CGFloat, String)]
    var body: some View {
        Canvas { context, _ in
            for (index, tier) in tiers.enumerated() {
                let (top, height, title) = tier
                let surface = CGRect(x: 12, y: top, width: size.width - 24, height: height)
                let shape = Path(roundedRect: surface, cornerRadius: 22)
                context.fill(shape, with: .color(.primary.opacity(index == 1 ? 0.037 : 0.018)))
                let edgeY = top + height - 5
                var edge = Path()
                edge.move(to: CGPoint(x: 34, y: edgeY))
                edge.addLine(to: CGPoint(x: size.width - 34, y: edgeY))
                context.stroke(edge, with: .color(.primary.opacity(index == 1 ? 0.16 : 0.08)),
                               style: StrokeStyle(lineWidth: index == 1 ? 3 : 1, lineCap: .round))
                context.draw(Text(title).font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary),
                             at: CGPoint(x: 35, y: edgeY - 8), anchor: .leading)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}




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
