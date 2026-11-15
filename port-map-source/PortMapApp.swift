import AppKit
import SwiftUI

@main
struct PortMapApp: App {
    @StateObject private var model = MapModel()
    @StateObject private var power = PowerMonitor()

    var body: some Scene {
        Window("Port Map", id: "main") {
            MapView(model: model)
                .environmentObject(power)
                .frame(minWidth: 920, minHeight: 680)
                .task {
                    if model.scan == nil { await model.refresh() }
                    model.startWatching()
                }
                .task { power.start() }
        }
        .defaultSize(width: 1280, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Connections") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(model.refreshing)
            }
        }
    }
}

@MainActor
final class MapModel: ObservableObject {
    @Published private(set) var scan: PortScan?
    @Published private(set) var error: String?
    @Published private(set) var refreshing = false
    @Published var selectedID: String?

    var selection: Port? { scan?.ports.first { $0.id == selectedID } }

    private let watcher = DeviceWatcher()
    private var refreshAgain = false

    /// Rescans whenever a device is plugged in or removed.
    func startWatching() {
        watcher.start { [weak self] in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        // A change that arrives mid-scan may have been missed by it, so scan once more after.
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        error = nil
        defer {
            refreshing = false
            if refreshAgain {
                refreshAgain = false
                Task { await refresh() }
            }
        }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try PortScan.capture() }.value
            scan = result
            if selection == nil {
                selectedID = result.ports.first { port in
                    port.connections.contains { $0.hasSlowStorage }
                }?.id ?? result.ports.first(where: \.connected)?.id ?? result.ports.first?.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension Connection {
    var hasSlowStorage: Bool { slowStorage || children.contains(where: \.hasSlowStorage) }
}

struct MapView: View {
    @ObservedObject var model: MapModel
    @EnvironmentObject private var power: PowerMonitor
    @AppStorage("mapViewV12") private var mode: MapMode = .overview
    @State private var setupAll = true

    private var connectedCount: Int { model.scan?.ports.filter(\.connected).count ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let scan = model.scan {
                HStack(spacing: 0) {
                    if mode != .overview {
                        portPicker(scan)
                        Divider()
                    }
                    if mode == .overview {
                        OverviewView(scan: scan)
                    } else if mode == .setup {
                        SetupView(scan: scan, port: setupAll ? nil : model.selection)
                    } else if let selected = model.selection {
                        portDetail(selected).id(selected.id)
                    }
                }
                if let error = model.error {
                    Divider()
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 16) {
                    if let error = model.error {
                        ContentUnavailableView {
                            Label("Couldn’t read connections", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error).textSelection(.enabled)
                        } actions: {
                            Button("Try Again") { Task { await model.refresh() } }
                                .disabled(model.refreshing)
                        }
                    } else {
                        ProgressView()
                        Text("Reading connected devices…").font(.headline)
                        Text("Your ports and cable paths will appear here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "macmini")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Port Map").font(.system(size: 22, weight: .semibold))
                if let scan = model.scan {
                    Text("\(connectedCount) of \(scan.ports.count) ports connected")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("View", selection: $mode) {
                Text("Overview").tag(MapMode.overview)
                Text("Setup").tag(MapMode.setup)
                Text("Ports").tag(MapMode.ports)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .labelsHidden()
            .frame(width: 242)
            if model.refreshing { ProgressView().controlSize(.small) }
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise").padding(.horizontal, 4)
            }
            .controlSize(.large)
            .disabled(model.refreshing)
            .help("Scan active ports and devices (⌘R)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func portPicker(_ scan: PortScan) -> some View {
        let groups = scan.ports.reduce(into: [String]()) { groups, port in
            if !groups.contains(port.group) { groups.append(port.group) }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                if mode == .setup {
                    Button {
                        setupAll = true
                    } label: {
                        Label("All ports", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 9)
                            .background(setupAll ? Color.accentColor.opacity(0.14) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(setupAll ? .isSelected : [])
                }
                ForEach(groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        if group == "Rear Thunderbolt" {
                            Text("Facing the rear panel")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                        }
                        ForEach(scan.ports.filter { $0.group == group }) { port in
                            let selected = model.selectedID == port.id && !(mode == .setup && setupAll)
                            Button {
                                model.selectedID = port.id
                                setupAll = false
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: port.group == "Display" ? "display" : "cable.connector.horizontal")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(port.connected ? Color.accentColor : .secondary)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(port.shortName)
                                            .font(.subheadline.weight(.semibold))
                                        Text(port.connected ? port.label : "Available")
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Circle()
                                        .fill(port.connected ? Color.green : Color.secondary.opacity(0.3))
                                        .frame(width: 6, height: 6)
                                        .accessibilityHidden(true)
                                    if selected {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected ? Color.accentColor.opacity(0.14) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityValue(port.connected ? "Connected" : "Available")
                            .help(port.id)
                        }
                    }
                }
            }
            .padding(15)
        }
        .frame(width: 245)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.42))
    }

    private func portDetail(_ port: Port) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        portTitle(port)
                        Spacer(minLength: 10)
                        if port.connected { linkLabel(port) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        portTitle(port)
                        if port.connected { linkLabel(port) }
                    }
                }
                HStack(spacing: 8) {
                    Label(port.connected ? "Connected" : "Available",
                          systemImage: port.connected ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(port.connected ? Color.green : Color.secondary)
                    Text(port.id).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
                if let cable = port.cable, port.connected {
                    Label("Cable · \(cable)", systemImage: "cable.connector")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let draw = power.power(for: port) {
                    Label("Supplying \(draw.detail) to connected devices", systemImage: "bolt.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .help("Live from WhatCable Pro, updated about once a second")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 19)
            Divider().padding(.horizontal, 24)
            if port.connections.isEmpty {
                ContentUnavailableView {
                    Label(port.connected ? "No device details" : "Ready to connect",
                          systemImage: "cable.connector")
                } description: {
                    Text(port.connected
                         ? "This port is connected, but no device details were reported."
                         : "Connect a device to see its details and cable path here.")
                    if !port.connected && port.group == "Front USB-C" {
                        Text("USB 3 · up to 10 Gb/s")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(port.connections) { node in DeviceRow(node: node) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func portTitle(_ port: Port) -> some View {
        Text(port.displayName)
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private func linkLabel(_ port: Port) -> some View {
        Text(port.link)
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if let scan = model.scan {
                Text(scan.version.isEmpty ? "WhatCable + macOS" : "WhatCable \(scan.version) + macOS")
                Spacer()
                Label(model.refreshing ? "Scanning…" : "Updates automatically",
                      systemImage: model.refreshing ? "arrow.clockwise" : "arrow.triangle.2.circlepath")
                    .help("Rescans when a device is connected or removed")
                Text("Last scan \(scan.capturedAt.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
            } else {
                Text("WhatCable + macOS")
                Spacer()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 9)
        .padding(.horizontal, 24)
    }
}

private enum MapMode: String {
    case overview, setup, ports
}

struct DeviceRow: View {
    let node: Connection
    @State private var expanded = true

    var body: some View {
        if node.children.isEmpty {
            row.padding(.leading, 16)
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(node.children) { child in DeviceRow(node: child) }
                }
                .padding(.leading, 13)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.quaternary).frame(width: 1).padding(.leading, 3)
                }
            } label: {
                row
            }
        }
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: node.icon)
                .foregroundStyle(node.slowStorage ? .orange : .secondary)
                .frame(width: 17)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(.callout.weight(.medium)).textSelection(.enabled)
                if let detail = node.detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer(minLength: 4)
            if let speed = node.speed {
                Text(speed)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(node.slowStorage ? .orange : .secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
    }
}
