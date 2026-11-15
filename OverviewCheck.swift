import AppKit
import Foundation
import IOKit

struct Connection: Identifiable {
    let id: String
    let name: String
    let detail: String?
    let speed: String?
    let icon: String
    var children: [Connection] = []
    var slowStorage = false
}

struct Port: Identifiable {
    let id: String
    let position: String
    let group: String
    let label: String
    let connected: Bool
    let link: String
    let cable: String?
    let cableMatches: [String]
    let connections: [Connection]
}

struct PortScan {
    let ports: [Port]
    let version: String
    let isMacMini: Bool
    let capturedAt = Date()

    static func capture() throws -> Self {
        let applications = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "uk.whatcable.whatcable"),
            URL(fileURLWithPath: "/Applications/WhatCable.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/WhatCable.app")
        ].compactMap { $0 }
        let helpers = applications.map { $0.appendingPathComponent("Contents/Helpers/whatcable").path }
            + ["/opt/homebrew/bin/whatcable", "/usr/local/bin/whatcable"]
        guard let helper = helpers.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw ScanError("Install WhatCable in Applications, then click Refresh.")
        }

        let data = try readWhatCable(helper)
        let snapshot: Snapshot
        do {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            throw ScanError("The WhatCable report could not be read. Check that WhatCable is up to date and try again.")
        }
        guard !snapshot.ports.isEmpty else {
            throw ScanError("WhatCable returned no USB-C ports for this Mac.")
        }

        let storage = scanMountedStorage()
        let rearPositions = readRearPositions()
        let isMini = hardwareModel() == "Mac16,10"
        let switches = snapshot.thunderboltSwitches ?? []
        let videoCounts = Dictionary(grouping: snapshot.ports.flatMap { $0.displays ?? [] }
            + (snapshot.builtInDisplayPorts ?? []).flatMap { $0.displays ?? [] }, by: \.monitorName)
        let ports = snapshot.ports.map { info in
            let number = Int(info.name.split(separator: "@").last ?? "")
            let position = number.flatMap { rearPositions[$0] }
            let group = position != nil ? "Rear Thunderbolt" : (isMini ? "Front USB-C" : "USB-C")
            let usb = (info.devices ?? []).map { usbNode($0, storage: storage) }
            let video = (info.displays ?? []).enumerated().map { monitor($0, matching: videoCounts) }
            let branch = info.thunderboltSwitchIndex.map { parent in
                switchNodes(parent: parent, switches: switches, storage: storage)
            } ?? []
            let nodes: [Connection]
            if branch.count == 1 {
                var hub = branch[0]
                hub.children += video + usb
                nodes = [hub]
            } else {
                nodes = branch + video + usb
            }
            let name = branch.first?.name
                ?? usb.first(where: { $0.name.localizedCaseInsensitiveContains("stand") })?.name
                ?? usb.first?.name ?? video.first?.name ?? info.headline
            let speed = info.transports?.usb3Speed
                ?? (branch.isEmpty ? nil : branch.first?.speed)
                ?? ((info.transports?.active ?? []).contains("USB2") ? "USB 2 · 480 Mb/s" : info.headline)
            return Port(id: info.name, position: position ?? "@\(number.map(String.init) ?? info.name)",
                        group: group, label: info.connectionActive ? name : "Available",
                        connected: info.connectionActive, link: speed, cable: info.cable?.speed,
                        cableMatches: info.cable?.curatedBrands ?? [],
                        connections: nodes)
        }.sorted { left, right in
            let order = ["Left": 0, "Middle": 1, "Right": 2]
            return (order[left.position] ?? 3, left.id) < (order[right.position] ?? 3, right.id)
        }
        let displays = (snapshot.builtInDisplayPorts ?? []).map { info in
            let nodes = (info.displays ?? []).enumerated().map { monitor($0, matching: videoCounts) }
            return Port(id: info.name, position: "HDMI", group: "Display",
                        label: nodes.first?.name ?? "Available", connected: !nodes.isEmpty,
                        link: "HDMI", cable: nil, cableMatches: [], connections: nodes)
        }
        return Self(ports: ports + displays, version: snapshot.version ?? "", isMacMini: isMini)
    }
}

struct ScanError: LocalizedError {
    let errorDescription: String?
    init(_ text: String) { errorDescription = text }
}

private struct Snapshot: Decodable {
    let version: String?
    let ports: [USBPort]
    let builtInDisplayPorts: [DisplayPort]?
    let thunderboltSwitches: [Switch]?
}

private struct USBPort: Decodable {
    let name: String
    let headline: String
    let connectionActive: Bool
    let transports: Transports?
    let cable: Cable?
    let thunderboltSwitchIndex: Int?
    let devices: [USBDevice]?
    let displays: [Monitor]?
}

private struct Transports: Decodable {
    let active: [String]?
    let usb3Speed: String?
}

private struct Cable: Decodable {
    let speed: String?
    let curatedBrands: [String]?
}

private struct DisplayPort: Decodable {
    let name: String
    let displays: [Monitor]?
}

private struct Monitor: Decodable {
    let monitorName: String
}

private struct USBDevice: Decodable {
    let locationID: String?
    let name: String?
    let speed: String?
    let vendorName: String?
    let children: [Self]?
}

private struct Switch: Decodable {
    struct Lane: Decodable {
        let portNumber: Int
        let linkActive: Bool
        let txGbps: Double?
    }

    let index: Int
    let parentSwitchIndex: Int?
    let modelName: String?
    let vendorName: String?
    let routeString: UInt64
    let depth: Int
    let ports: [Lane]
}

private struct Storage {
    var usb: [UInt32: [String]] = [:]
    var thunderbolt: [ThunderboltKey: [String]] = [:]
}

private struct ThunderboltKey: Hashable {
    let route: UInt64
    let model: String
    let vendor: String
}

private func readWhatCable(_ path: String) throws -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--json"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let timeout = DispatchWorkItem {
        if process.isRunning { process.terminate() }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: timeout)
    defer { timeout.cancel() }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ScanError("WhatCable could not complete the scan. Try Refresh again.")
    }
    return data
}

private func usbNode(_ device: USBDevice, storage: Storage) -> Connection {
    let location = device.locationID.flatMap { UInt32($0.dropFirst(2), radix: 16) }
    let volumes = location.flatMap { storage.usb[$0] } ?? []
    let name = device.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Unnamed USB device"
    let isDrive = !volumes.isEmpty || name.localizedCaseInsensitiveContains("Expansion HDD")
    let children = (device.children ?? []).map { usbNode($0, storage: storage) }
    let slow = isDrive && (device.speed?.contains("480 Mbps") ?? false)
    let detail = ([device.vendorName].compactMap { $0 } + volumes).joined(separator: " · ")
    return Connection(id: device.locationID ?? UUID().uuidString, name: name, detail: detail,
                      speed: device.speed, icon: isDrive ? "externaldrive" : (children.isEmpty ? "cable.connector" : "point.3.connected.trianglepath.dotted"),
                      children: children, slowStorage: slow)
}

private func switchNodes(parent: Int, switches: [Switch], storage: Storage) -> [Connection] {
    let upstream = switches.first { $0.index == parent }
    return switches.filter { $0.parentSwitchIndex == parent }.map { hub in
        let model = hub.modelName ?? "USB4 device"
        let vendor = hub.vendorName ?? ""
        let key = ThunderboltKey(route: hub.routeString, model: model, vendor: vendor)
        let unique = switches.filter { $0.routeString == hub.routeString && $0.modelName == model && $0.vendorName == vendor }.count == 1
        let volumes = unique ? storage.thunderbolt[key] ?? [] : []
        let branchPort = Int((hub.routeString >> max(0, (hub.depth - 1) * 8)) & 0xff)
        let tx = upstream?.ports.first { $0.portNumber == branchPort && $0.linkActive }?.txGbps
        let speed = tx.flatMap { $0 > 0 ? "\($0.formatted()) Gb/s" : nil }
        let detail = ([vendor].filter { !$0.isEmpty } + volumes).joined(separator: " · ")
        return Connection(id: "switch-\(hub.index)", name: model, detail: detail, speed: speed,
                          icon: volumes.isEmpty ? "bolt.horizontal" : "externaldrive",
                          children: switchNodes(parent: hub.index, switches: switches, storage: storage))
    }
}

private func monitor(_ entry: (Int, Monitor), matching counts: [String: [Monitor]]) -> Connection {
    let name = entry.1.monitorName
    let detail = (counts[name]?.count ?? 0) > 1 ? "Display name also reported on another path" : nil
    return Connection(id: "display-\(entry.0)", name: name, detail: detail, speed: nil, icon: "display")
}

private func hardwareModel() -> String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "" }
    return String(cString: buffer)
}

private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

private func readRearPositions() -> [Int: String] {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMSPMIDevice"), &iterator) == KERN_SUCCESS else { return [:] }
    defer { IOObjectRelease(iterator) }
    let labels = ["back-left": "Left", "back-middle": "Middle", "back-right": "Right"]
    var positions: [Int: String] = [:]
    while case let entry = IOIteratorNext(iterator), entry != 0 {
        defer { IOObjectRelease(entry) }
        guard let label = property(entry, "port-location") as? Data,
              let number = property(entry, "port-number") as? Data,
              let raw = String(data: label.prefix(while: { $0 != 0 }), encoding: .utf8),
              let position = labels[raw], let port = number.first else { continue }
        positions[Int(port)] = position
    }
    return positions
}

private func scanMountedStorage() -> Storage {
    var storage = Storage()
    var table: UnsafeMutablePointer<statfs>?
    let count = Int(getmntinfo(&table, MNT_NOWAIT))
    guard let table, count > 0 else { return storage }
    for var mount in UnsafeBufferPointer(start: table, count: count) {
        guard mount.f_flags & UInt32(MNT_LOCAL) != 0 else { continue }
        let device = withUnsafeBytes(of: &mount.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let target = withUnsafeBytes(of: &mount.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard device.hasPrefix("/dev/disk"), target.hasPrefix("/Volumes/") else { continue }
        let bsdName = String(device.dropFirst("/dev/".count))
        let name = URL(fileURLWithPath: target).lastPathComponent
        var node = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsdName))
        while node != 0 {
            if IOObjectConformsTo(node, "IOUSBHostDevice") != 0,
               let location = property(node, "locationID") as? NSNumber {
                storage.usb[location.uint32Value, default: []].append(name)
                IOObjectRelease(node)
                break
            }
            if let tunnel = property(node, "Thunderbolt Path") as? String,
               let switchPath = tunnel.range(of: "/IOThunderboltPort@", options: .backwards) {
                let router = IORegistryEntryFromPath(kIOMainPortDefault, String(tunnel[..<switchPath.lowerBound]))
                if router != 0 {
                    if let route = property(router, "Route String") as? NSNumber,
                       let model = property(router, "Device Model Name") as? String,
                       let vendor = property(router, "Device Vendor Name") as? String {
                        storage.thunderbolt[.init(route: route.uint64Value, model: model, vendor: vendor), default: []].append(name)
                    }
                    IOObjectRelease(router)
                }
                IOObjectRelease(node)
                break
            }
            var parent: io_registry_entry_t = 0
            IORegistryEntryGetParentEntry(node, kIOServicePlane, &parent)
            IOObjectRelease(node)
            node = parent
        }
    }
    return storage
}
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
    case macMini, element, satechi, expansion, lacie, nvme, s4, z1, x1, monitor, ethernet, hub

    var image: NSImage? { Self.images[self] }

    private static let images = readAtlas("DeviceArtwork", columns: 4, rows: 3, cells: allCases)
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
        let title: String
        let art: DeviceArt?
        var logical = false
        switch name {
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
        return Self(id: node.id, title: title, detail: details, art: art, icon: node.icon,
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

    private var inventory: OverviewInventory { OverviewInventory(scan: scan) }

    var body: some View {
        let items = inventory
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your whole setup").font(.title2.weight(.semibold))
                    Text("Three levels · representative artwork · select a device to trace its connection")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Paths", isOn: $showPaths).toggleStyle(.switch).controlSize(.small)
                Button("Interfaces (\(items.interfaces.count))") { showInterfaces.toggle() }
                    .popover(isPresented: $showInterfaces) {
                        OverviewInterfaces(interfaces: items.interfaces)
                    }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
            GeometryReader { geometry in
                let layout = OverviewLayout(items: items.devices)
                let scale = min(geometry.size.width / layout.size.width, geometry.size.height / layout.size.height)
                ZStack(alignment: .topLeading) {
                    OverviewTiers(size: layout.size)
                    OverviewConnections(devices: items.devices, frames: layout.frames,
                                        selectedID: selectedID, showAll: showPaths)
                    ForEach(items.devices) { device in
                        if let frame = layout.frames[device.id], !(items.hasStack && (device.id == "host" || device.art == .satechi)) {
                            OverviewCard(device: device, selected: selectedID == device.id) {
                                selectedID = selectedID == device.id ? nil : device.id
                            }
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                        }
                    }
                    if items.hasStack, let host = items.devices.first(where: { $0.id == "host" }),
                       let stand = items.devices.first(where: { $0.art == .satechi }) {
                        OverviewStack(host: host, stand: stand, selectedID: selectedID) { selectedID = $0 }
                            .frame(width: 280, height: 240)
                            .position(x: 600, y: 558)
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                // Scaling changes drawing, not layout. Keep the original scene's
                // center at the viewport center, avoiding nested-frame offsets.
                .scaleEffect(scale, anchor: .center)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .clipped()
            HStack(spacing: 14) {
                Label("Reported connection", systemImage: "line.diagonal").foregroundStyle(.teal)
                Text("– –  Through interfaces / unverified cable").foregroundStyle(.secondary)
                Spacer()
                Text("Monitor order is illustrative").foregroundStyle(.secondary)
            }
            .font(.caption).padding(.horizontal, 24).padding(.top, 5).padding(.bottom, 10)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.32))
        .accessibilityIdentifier("physical-overview")
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
    var stack = false
    var subtitle: String {
        guard let port else { return "Host computer" }
        let location = port.group == "Display" ? "HDMI" : port.group == "Rear Thunderbolt" ? "Rear \(port.position.lowercased())" : "\(port.group) \(port.position)"
        return location
    }
}

private struct OverviewInterface: Identifiable {
    let id: String
    let title: String
    let path: [String]
    let detail: String?
}

private struct OverviewInventory {
    var devices: [OverviewDevice] = []
    var interfaces: [OverviewInterface] = []
    var hasStack: Bool { devices.contains { $0.art == .satechi } }

    init(scan: PortScan) {
        devices = [OverviewDevice(id: "host", title: scan.isMacMini ? "Mac mini M4" : "This Mac", art: scan.isMacMini ? .macMini : nil,
                                  icon: "desktopcomputer", port: nil, path: [], detail: nil, wire: nil, parentID: nil,
                                  indirect: false, category: 2)]
        for port in scan.ports where port.connected {
            for node in SetupDevice.nodes(for: port) {
                append(node, port: port, path: [port.id], parent: "host", indirect: false)
            }
        }
        if let host = devices.firstIndex(where: { $0.id == "host" }) {
            devices[host].stack = devices.contains { $0.art == .satechi }
        }
    }

    private mutating func append(_ node: SetupDevice, port: Port, path: [String], parent: String, indirect: Bool) {
        let fullPath = path + [node.title]
        let id = port.id + "/" + node.id
        let isStorageEndpoint = node.title.lowercased() == "usb storage" || node.title.lowercased() == "satechi disk media"
        let physical = node.art != nil || isStorageEndpoint
        var nextParent = parent
        if physical {
            let category = node.art == .monitor ? 0 : [.s4, .z1, .x1].contains(node.art) ? 1 : node.art == .satechi ? 2 : 3
            devices.append(OverviewDevice(id: id, title: node.title, art: node.art,
                                          icon: isStorageEndpoint ? "externaldrive" : node.icon, port: port, path: fullPath,
                                          detail: node.detail, wire: node.wire, parentID: parent,
                                          indirect: indirect || (node.wire?.dashed ?? false), category: category))
            nextParent = id
        } else {
            interfaces.append(OverviewInterface(id: id, title: node.title, path: fullPath, detail: node.detail))
        }
        for child in node.children {
            append(child, port: port, path: fullPath, parent: nextParent, indirect: !physical)
        }
    }
}

private struct OverviewLayout {
    let size: CGSize
    var frames: [String: CGRect] = [:]

    init(items: [OverviewDevice]) {
        let others = items.filter { $0.category == 3 }
        let extraRows = max(2, Int(ceil(Double(others.count) / 4)))
        size = CGSize(width: 1200, height: 460 + CGFloat(extraRows) * 118)
        let monitors = items.filter { $0.category == 0 }
        let controllers = items.filter { $0.category == 1 }.sorted {
            let order: [DeviceArt: Int] = [.z1: 0, .s4: 1, .x1: 2]
            return (order[$0.art ?? .hub] ?? 3) < (order[$1.art ?? .hub] ?? 3)
        }
        for (index, device) in monitors.enumerated() {
            let width = min(300, 1128 / CGFloat(max(1, monitors.count)) - 18)
            let step = 1128 / CGFloat(max(1, monitors.count))
            frames[device.id] = CGRect(x: 36 + step * (CGFloat(index) + 0.5) - width / 2, y: 12, width: width, height: 174)
        }
        for (index, device) in controllers.enumerated() {
            let step = 1000 / CGFloat(max(1, controllers.count))
            let width = min(device.art == .s4 ? 330 : 260, step - 18)
            frames[device.id] = CGRect(x: 100 + step * (CGFloat(index) + 0.5) - width / 2, y: 227, width: width, height: 168)
        }
        frames["host"] = CGRect(x: 460, y: 438, width: 280, height: 138)
        if let stand = items.first(where: { $0.art == .satechi }) {
            frames[stand.id] = CGRect(x: 460, y: 544, width: 280, height: 134)
        }
        for (index, device) in others.enumerated() {
            let column = index % 4
            let x: CGFloat = [22, 234, 766, 978][column]
            let y = 448 + CGFloat(index / 4) * 118
            frames[device.id] = CGRect(x: x, y: y, width: 200, height: 106)
        }
    }
}

private struct OverviewConnections: View {
    let devices: [OverviewDevice]
    let frames: [String: CGRect]
    let selectedID: String?
    let showAll: Bool

    private var highlighted: Set<String> {
        var path = Set<String>()
        var current = selectedID
        while let id = current, !path.contains(id) {
            path.insert(id)
            current = devices.first { $0.id == id }?.parentID
        }
        return path
    }

    var body: some View {
        Canvas { context, _ in
            let traced = highlighted
            for device in devices {
                guard let parent = device.parentID, let target = frames[device.id], let source = frames[parent] else { continue }
                let active = traced.contains(device.id) && traced.contains(parent)
                guard showAll || active else { continue }
                let upward = target.midY < source.midY
                let start = CGPoint(x: source.midX, y: upward ? source.minY + 7 : source.maxY - 7)
                let end = CGPoint(x: target.midX, y: upward ? target.maxY - 5 : target.minY + 5)
                var path = Path()
                path.move(to: start)
                let midY = (start.y + end.y) / 2
                path.addCurve(to: end, control1: CGPoint(x: start.x, y: midY), control2: CGPoint(x: end.x, y: midY))
                let color = device.wire?.color ?? .teal
                context.stroke(path, with: .color(color.opacity(active ? 0.95 : 0.18)),
                               style: StrokeStyle(lineWidth: active ? 3 : 1.4, lineCap: .round,
                                                  dash: device.indirect ? [5, 5] : []))
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
            showDetails = true
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
        .help("Inspect \(device.title) · \(device.subtitle)")
        .accessibilityLabel("\(device.title), \(device.subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .popover(isPresented: $showDetails) { OverviewInspector(device: device) }
    }

    @ViewBuilder private var artwork: some View {
        if let art = device.art, let image = art.image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .padding(.horizontal, device.category == 1 && art != .s4 ? 45 : 5)
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
            } else if device.id == "host" && device.stack {
                Text("Mac mini above Satechi Stand & Hub, following your desk arrangement.").foregroundStyle(.secondary)
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


private struct OverviewStack: View {
    let host: OverviewDevice
    let stand: OverviewDevice
    let selectedID: String?
    let select: (String) -> Void
    @State private var inspectHost = false
    @State private var inspectStand = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                select(host.id)
                inspectHost = true
            } label: {
                Text(host.title).font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.top, 11).padding(.bottom, 4)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $inspectHost) { OverviewInspector(device: host) }
            GeometryReader { geometry in
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
                .onTapGesture { select(host.id); inspectHost = true }
                .accessibilityLabel("Mac mini sitting on Satechi Stand & Hub")
            }
            Button {
                select(stand.id)
                inspectStand = true
            } label: {
                VStack(spacing: 2) {
                    Text(stand.title).font(.system(size: 13, weight: .semibold))
                    Text(stand.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 4).padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Inspect Satechi Stand & Hub")
            .popover(isPresented: $inspectStand) { OverviewInspector(device: stand) }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(selectedID == host.id || selectedID == stand.id ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}


// Decorative shelf context follows the user's three levels, not a measured room model.
private struct OverviewTiers: View {
    let size: CGSize
    var body: some View {
        Canvas { context, _ in
            let tiers: [(CGFloat, CGFloat, String)] = [
                (0, 207, "MONITORS"),
                (215, 207, "DJ CONTROLLERS"),
                (434, size.height - 434, "GROUND LEVEL")
            ]
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
            // Small supports suggest the raised DJ shelf without adding graph nodes.
            for x: CGFloat in [48, size.width - 52] {
                let support = CGRect(x: x, y: 420, width: 4, height: 19)
                context.fill(Path(roundedRect: support, cornerRadius: 2), with: .color(.primary.opacity(0.13)))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
@main struct OverviewCheck {
 static func main() throws {
  let scan = try PortScan.capture()
  let inventory = OverviewInventory(scan: scan)
  let layout = OverviewLayout(items: inventory.devices)
  for width: CGFloat in [920, 1280, 1861] {
   for height: CGFloat in [680, 900, 1050] {
    for reservedHeight: CGFloat in [0, 220] {
     let viewport = CGSize(width: width, height: height - reservedHeight)
     let scale = min(viewport.width / layout.size.width, viewport.height / layout.size.height)
     let rendered = CGRect(x: (viewport.width-layout.size.width*scale)/2,
                           y: (viewport.height-layout.size.height*scale)/2,
                           width: layout.size.width*scale, height: layout.size.height*scale)
     let epsilon: CGFloat = 0.001
     precondition(abs(rendered.midX-viewport.width/2)<epsilon && abs(rendered.midY-viewport.height/2)<epsilon, "Scene shifted from center")
     precondition(rendered.minX >= -epsilon && rendered.minY >= -epsilon && rendered.maxX <= viewport.width+epsilon && rendered.maxY <= viewport.height+epsilon, "Scene overflows viewport")
     for frame in layout.frames.values {
      let final = CGRect(x: rendered.minX+frame.minX*scale, y: rendered.minY+frame.minY*scale,
                         width: frame.width*scale,height: frame.height*scale)
      precondition(final.minX >= -epsilon && final.minY >= -epsilon && final.maxX <= viewport.width+epsilon && final.maxY <= viewport.height+epsilon, "Card overflows viewport")
     }
     print("FIT PASS: window \(Int(width))×\(Int(height)), reserved \(Int(reservedHeight)), rendered \(rendered)")
    }
   }
  }
  let identifiers = inventory.devices.map(\.id) + inventory.interfaces.map(\.id)
  precondition(Set(identifiers).count == identifiers.count, "Duplicate overview IDs")
  for device in inventory.devices {
   guard let frame = layout.frames[device.id] else { fatalError("Missing layout") }
   precondition(frame.minX >= 0 && frame.maxX <= layout.size.width && frame.minY >= 0 && frame.maxY <= layout.size.height, "Clipped layout")
   if let parent = device.parentID { precondition(inventory.devices.contains { $0.id == parent }, "Disconnected overview node") }
  }
  func count(_ n: SetupDevice) -> Int { 1 + n.children.map(count).reduce(0,+) }
  let expected = scan.ports.filter(\.connected).flatMap(SetupDevice.nodes).map(count).reduce(0,+)
  precondition(identifiers.count - 1 == expected, "Dropped detected node")
  let displays = inventory.devices.filter { $0.category == 0 }
  let reportedDisplays = scan.ports.flatMap(SetupDevice.nodes).flatMap { root -> [SetupDevice] in
    func flatten(_ n: SetupDevice) -> [SetupDevice] { [n] + n.children.flatMap(flatten) }
    return flatten(root)
  }.filter { $0.art == .monitor }
  precondition(displays.count == reportedDisplays.count, "Merged display paths")
  print("PASS: \(inventory.devices.count) visible endpoints including host; \(inventory.interfaces.count) interfaces; \(displays.count) separate display paths; every detected node reachable; layout bounds valid.")
  for d in inventory.devices { print("\(d.title) | \(d.subtitle) | \(d.parentID ?? "root")") }
 }
}
