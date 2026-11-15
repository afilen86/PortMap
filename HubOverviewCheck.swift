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
                let hdmiReference = hub.art == .element ? all.devices.first {
                    $0.art == .monitor && $0.port?.group == "Display" && $0.title.lowercased() == "ingnok"
                } : nil
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hub connections").font(.title2.weight(.semibold))
                            Text(items.devices.count == 1 && items.interfaces.isEmpty
                                 ? "No downstream devices detected on this hub."
                                 : "Only devices downstream of the selected hub · select a device to trace its route")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Paths", isOn: $showPaths).toggleStyle(.switch).controlSize(.small)
                        Button("Interfaces (\(items.interfaces.count))") { showInterfaces.toggle() }
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
                    let layout = OverviewLayout(items: items.devices, rootID: hub.id, reference: hdmiReference)
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
                        if let reference = hdmiReference, let frame = layout.referenceFrame {
                            OverviewReferenceCard(device: reference) { selectedID = nil }
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
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
    var referenceFrame: CGRect?

    init(items: [OverviewDevice], rootID: String, reference: OverviewDevice? = nil) {
        let monitors = items.filter { $0.category == 0 && $0.id != rootID }
        let display12 = monitors.first { $0.title.lowercased() == "12.3fhd" }
        let upperDisplay = monitors.first { $0.title.lowercased() == "ingnok" }
        let hasConfirmedDisplayPair = items.first { $0.id == rootID }?.art == .element
            && monitors.count == 2 && display12 != nil && upperDisplay != nil
        let besideDisplay = hasConfirmedDisplayPair ? items.first { $0.art == .twister } : nil
        let controllers = items.filter { $0.category == 1 && $0.id != rootID && $0.id != besideDisplay?.id }.sorted {
            let order: [DeviceArt: Int] = [.z1: 0, .s4: 1, .x1: 2, .twister: 3]
            return (order[$0.art ?? .hub] ?? 3) < (order[$1.art ?? .hub] ?? 3)
        }
        let others = items.filter { $0.category != 0 && $0.category != 1 && $0.id != rootID }
        var nextY: CGFloat = 0
        if hasConfirmedDisplayPair, let display12, let upperDisplay {
            // User-confirmed placement: ingnok above 12.3FHD, Twister beside 12.3FHD.
            // These coordinates do not alter their independent detected parent links.
            let displayX: CGFloat = reference == nil ? 310 : 174
            tiers.append((0, 167, "UPPER DISPLAY"))
            frames[upperDisplay.id] = CGRect(x: displayX, y: 10, width: 340, height: 146)
            tiers.append((170, 167, besideDisplay == nil ? "12.3FHD" : "12.3FHD & MIDI FIGHTER TWISTER"))
            frames[display12.id] = CGRect(x: displayX, y: 180, width: 340, height: 146)
            if let besideDisplay {
                frames[besideDisplay.id] = CGRect(x: displayX + 374, y: 180, width: 200, height: 146)
            }
            if reference != nil {
                referenceFrame = CGRect(x: displayX + 606, y: 180, width: 246, height: 146)
            }
            nextY = 340
        } else if !monitors.isEmpty {
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
            let tierHeight: CGFloat = hasConfirmedDisplayPair ? 187 : 207
            let cardHeight: CGFloat = hasConfirmedDisplayPair ? 158 : 168
            tiers.append((nextY, tierHeight, "DJ CONTROLLERS ON THIS HUB"))
            for (index, device) in controllers.enumerated() {
                let step = 1000 / CGFloat(controllers.count)
                let width = min(device.art == .s4 ? 330 : 260, step - 18)
                frames[device.id] = CGRect(x: 100 + step * (CGFloat(index) + 0.5) - width / 2,
                                          y: nextY + 12, width: width, height: cardHeight)
            }
            nextY += tierHeight + 3
        }
        let lowerHeight = max(hasConfirmedDisplayPair ? 228 : 264, CGFloat(Int(ceil(Double(others.count) / 4))) * 118 + 28)
        tiers.append((nextY, lowerHeight, "SELECTED HUB & CONNECTED DEVICES"))
        frames[rootID] = CGRect(x: 460, y: nextY + 12, width: 280, height: hasConfirmedDisplayPair ? 190 : 226)
        for (index, device) in others.enumerated() {
            let column = index % 4
            let x: CGFloat = [22, 234, 766, 978][column]
            frames[device.id] = CGRect(x: x, y: nextY + 20 + CGFloat(index / 4) * 118,
                                      width: 200, height: 106)
        }
        size = CGSize(width: 1200, height: nextY + lowerHeight + 12)
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


// User-requested physical context, intentionally separate from hub membership/edges.
private struct OverviewReferenceCard: View {
    let device: OverviewDevice
    let select: () -> Void
    @State private var showDetails = false

    var body: some View {
        Button {
            select()
            showDetails = true
        } label: {
            VStack(spacing: 3) {
                if let image = device.art?.image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .opacity(0.55).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(device.title).font(.system(size: 13, weight: .semibold))
                Text("Direct HDMI · outside this hub").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .help("Spatial reference only · direct HDMI connection to the Mac")
        .accessibilityLabel("\(device.title), direct HDMI, spatial reference outside the selected hub")
        .popover(isPresented: $showDetails) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Direct HDMI · spatial reference only")
                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.top, 16)
                OverviewInspector(device: device)
            }
        }
    }
}
@main struct HubOverviewCheck {
 static func main() throws {
  let scan = try PortScan.capture()
  let all = OverviewInventory(scan: scan)
  precondition(all.hubs.count == 2, "Expected current setup's two recognized hubs")
  var branchIDs: [Set<String>] = []
  for hub in all.hubs {
   let branch = all.branch(rootID: hub.id)
   let ids = Set(branch.devices.map(\.id))
   branchIDs.append(ids)
   precondition(!ids.contains("host"), "Host leaked into downstream view")
   precondition(branch.devices.filter { $0.id == hub.id }.count == 1)
   precondition(branch.devices.allSatisfy { $0.port?.id == hub.port?.id }, "Foreign port device leaked into hub branch")
   precondition(branch.interfaces.allSatisfy { ids.contains($0.parentID) }, "Foreign interface in branch")
   precondition(branch.devices.filter { $0.id != hub.id }.allSatisfy { ids.contains($0.parentID ?? "") }, "Descendant unreachable")
   precondition(!branch.devices.contains { $0.art == .lacie || $0.title == "Realtek 5 GbE adapter" || $0.port?.group == "Display" }, "Direct connection leaked into branch")
   if hub.art == .element {
    precondition(branch.devices.count == 7 + branch.devices.filter { $0.art == .twister }.count)
    precondition(branch.devices.filter { $0.art == .monitor }.count == 2)
    let x1 = branch.devices.first { $0.art == .x1 }!
    precondition(branch.devices.first { $0.id == x1.parentID }?.art == .s4, "Controller chain lost")
   }
   if hub.art == .satechi {
    precondition(branch.devices.count == 5 + branch.devices.filter { $0.art == .twister }.count)
    precondition(!branch.devices.contains { $0.art == .monitor })
    precondition(branch.devices.contains { $0.art == .expansion }, "USB 2 companion branch lost")
   }
   if hub.art == .element {
    let hdmi = all.devices.first { $0.art == .monitor && $0.port?.group == "Display" && $0.title == "ingnok" }!
    let layout = OverviewLayout(items: branch.devices, rootID: hub.id, reference: hdmi)
    precondition(!branch.devices.contains { $0.id == hdmi.id })
    let upper = branch.devices.first { $0.title == "ingnok" }!
    let lower = branch.devices.first { $0.title == "12.3FHD" }!
    let twister = branch.devices.first { $0.art == .twister }!
    let u = layout.frames[upper.id]!, l = layout.frames[lower.id]!, t = layout.frames[twister.id]!
    precondition(u.midX == l.midX && u.maxY < l.minY, "Displays not stacked")
    let ref = layout.referenceFrame!
    precondition(ref.minX > t.maxX && ref.minX-t.maxX <= 40 && ref.midY == t.midY && ref.maxX <= layout.size.width, "HDMI reference not beside Twister")
    precondition(OverviewLayout(items: branch.devices, rootID: hub.id).referenceFrame == nil, "Missing HDMI still rendered")
    precondition(t.minX > l.maxX && t.minX-l.maxX <= 40 && t.midY == l.midY, "Twister not immediately right of 12.3FHD")
    precondition(branch.devices.filter { [.s4, .z1, .x1].contains($0.art) }.allSatisfy { layout.frames[$0.id]!.minY > l.maxY }, "Traktor devices not below display/Twister row")
    checkFit(branch, hub.id, reference: hdmi)
    print("PASS: live Twister recognized, confirmed display/Twister geometry, and Traktor lower tier")
   }
   checkFit(branch, hub.id)
   print("PASS \(hub.title): \(branch.devices.count) cards (including hub), \(branch.interfaces.count) interfaces")
   for d in branch.devices { print("  \(d.title) | \(d.id) | parent \(d.parentID ?? "none")") }
  }
  precondition(branchIDs[0].isDisjoint(with: branchIDs[1]), "Current hubs share nodes incorrectly")
  let empty = OverviewInventory(scan: PortScan(ports: [], version: "test", isMacMini: true))
  precondition(empty.hubs.isEmpty && empty.branch(rootID:"missing").devices.isEmpty)
  let hubPortIDs = Set(all.hubs.compactMap { $0.port?.id })
  let disconnected = OverviewInventory(scan: PortScan(ports: scan.ports.filter { !hubPortIDs.contains($0.id) }, version: "test", isMacMini: true))
  precondition(disconnected.hubs.isEmpty, "Direct devices treated as hubs after disconnection")
  let emptyHubPort = Port(id: "empty-hub-port", position: "Left", group: "Rear Thunderbolt", label: "Satechi", connected: true, link: "10 Gb/s", cable: nil, cableMatches: [], connections: [Connection(id: "empty-hub", name: "Mac Mini Stand & Hub", detail: nil, speed: "10 Gb/s", icon: "point.3.connected.trianglepath.dotted")])
  let emptyHub = OverviewInventory(scan: PortScan(ports: [emptyHubPort], version: "test", isMacMini: true))
  let root = emptyHub.hubs.first!
  let branch = emptyHub.branch(rootID:root.id)
  precondition(branch.devices.count == 1 && branch.interfaces.isEmpty)
  checkFit(branch, root.id)
  for name in ["MIDI Fighter Twister", "MIDIFIGHTER Twister", "DJ TechTools MIDI-Fighter Twister", "Midi Fighter Twister (USB MIDI)"] {
   let twister = Connection(id: "twister-test", name: name, detail: "DJ TechTools", speed: "Full Speed (12 Mbps)", icon: "cable.connector")
   let hubNode = Connection(id: "test-hub", name: "Mac Mini Stand & Hub", detail: nil, speed: "10 Gb/s", icon: "point.3.connected.trianglepath.dotted", children: [twister])
   let port = Port(id: "test-port", position: "Left", group: "Rear Thunderbolt", label: "Hub", connected: true, link: "10 Gb/s", cable: nil, cableMatches: [], connections: [hubNode])
   let inventory = OverviewInventory(scan: PortScan(ports: [port], version: "test", isMacMini: true))
   let hub = inventory.hubs.first!
   let branch = inventory.branch(rootID: hub.id)
   precondition(branch.devices.count == 2 && branch.devices.contains { $0.art == .twister && $0.category == 1 }, "Twister name variant missed")
   checkFit(branch, hub.id)
  }
  print("PASS: empty/disconnected states and all four Twister enumeration variants")
 }
 private static func checkFit(_ branch: OverviewInventory, _ rootID: String, reference: OverviewDevice? = nil) {
  let layout = OverviewLayout(items: branch.devices, rootID: rootID, reference: reference)
  precondition(Set(layout.frames.keys) == Set(branch.devices.map(\.id)), "Missing or foreign frame")
  for width: CGFloat in [920, 1280, 1861] {
   for height: CGFloat in [680, 900, 1050] {
    for reserved: CGFloat in [0, 260] {
     let viewport = CGSize(width: width, height: height-reserved)
     let scale = min(viewport.width/layout.size.width, viewport.height/layout.size.height)
     let x = (viewport.width-layout.size.width*scale)/2
     let y = (viewport.height-layout.size.height*scale)/2
     for frame in Array(layout.frames.values) + [layout.referenceFrame].compactMap({ $0 }) {
      precondition(frame.minX >= 0 && frame.minY >= 0 && frame.maxX <= layout.size.width && frame.maxY <= layout.size.height, "Canvas overflow")
      precondition(x+frame.minX*scale >= -0.001 && y+frame.minY*scale >= -0.001 && x+frame.maxX*scale <= viewport.width+0.001 && y+frame.maxY*scale <= viewport.height+0.001, "Viewport overflow")
     }
    }
   }
  }
  print("PASS: 18 fit combinations for \(rootID); scene \(layout.size)")
 }
}
