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
