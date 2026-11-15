import AppKit
import Foundation

/// Live power on one Mac USB-C port, from WhatCable Pro's telemetry.
struct PortPower: Equatable {
    let watts: Double
    let volts: Double?
    let amps: Double?

    var label: String { String(format: watts < 10 ? "%.1f W" : "%.0f W", watts) }
    var detail: String {
        let parts = [volts.map { String(format: "%.2f V", $0) }, amps.map { String(format: "%.2f A", $0) }].compactMap { $0 }
        return parts.isEmpty ? label : "\(label) (\(parts.joined(separator: ", ")))"
    }
}

/// Streams `whatcable --monitor-json` (a WhatCable Pro feature) while the app is open.
/// Each line is one sample, about once a second. Ports that draw nothing, or that the Mac
/// doesn't meter, are simply absent from a sample, so a missing port means "unknown".
@MainActor
final class PowerMonitor: ObservableObject {
    enum Status: Equatable {
        case idle, starting, running
        case unavailable(String)
    }

    /// Keyed by the Mac's USB-C port number, the N in "Port-USB-C@N" (WhatCable's portIndex).
    @Published private(set) var ports: [Int: PortPower] = [:]
    /// Total power the Mac is taking in.
    @Published private(set) var macWatts: Double?
    @Published private(set) var status: Status = .idle

    private var process: Process?
    private var buffer = Data()
    private var lastSample = Date.distantPast
    private var gotSample = false
    private var restarts = 0
    private var staleTimer: Timer?
    private var terminateObserver: NSObjectProtocol?

    func power(for port: Port) -> PortPower? {
        port.usbCNumber.flatMap { ports[$0] }
    }

    func start() {
        guard process == nil else { return }
        guard let helper = PortScan.helperPath() else {
            status = .unavailable("Live power needs WhatCable")
            return
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: helper)
        child.arguments = ["--monitor-json"]
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.receive(data) }
        }
        child.terminationHandler = { [weak self] ended in
            let code = ended.terminationStatus
            Task { @MainActor in self?.ended(code) }
        }
        do {
            try child.run()
        } catch {
            status = .unavailable("Couldn't start WhatCable's power monitor")
            return
        }
        process = child
        status = gotSample ? .running : .starting
        if staleTimer == nil {
            staleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.dropStaleSamples() }
            }
        }
        if terminateObserver == nil {
            terminateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
    }

    func stop() {
        staleTimer?.invalidate()
        staleTimer = nil
        if let process {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if process.isRunning { process.terminate() }
        }
        process = nil
        status = .idle
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty, let sample = try? JSONDecoder().decode(Telemetry.self, from: line) else { continue }
            apply(sample)
        }
        if buffer.count > 1_000_000 { buffer.removeAll() } // never let a broken stream grow without bound
    }

    private func apply(_ sample: Telemetry) {
        var next: [Int: PortPower] = [:]
        for port in sample.portSamples ?? [] where port.watts > 0 {
            next[port.portIndex] = PortPower(watts: port.watts / 1000,
                                             volts: port.configuredVoltage.map { $0 / 1000 },
                                             amps: port.current.map { $0 / 1000 })
        }
        if next != ports { ports = next }
        let mac = sample.systemSample?.systemPowerIn.map { $0 / 1000 }
        if mac != macWatts { macWatts = mac }
        lastSample = Date()
        gotSample = true
        restarts = 0
        if status != .running { status = .running }
    }

    private func ended(_ code: Int32) {
        process = nil
        // Exiting before any sample means the feature isn't available (for example, no Pro licence).
        guard gotSample else {
            stop()
            status = .unavailable("Live power needs WhatCable Pro")
            return
        }
        guard restarts < 5 else {
            stop()
            status = .unavailable("WhatCable's power monitor keeps stopping")
            return
        }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    private func dropStaleSamples() {
        guard Date().timeIntervalSince(lastSample) > 6, !ports.isEmpty || macWatts != nil else { return }
        ports = [:]
        macWatts = nil
    }
}

private struct Telemetry: Decodable {
    struct System: Decodable {
        let systemPowerIn: Double? // mW
    }

    struct PortSample: Decodable {
        let portIndex: Int
        let watts: Double // mW, despite the name
        let configuredVoltage: Double? // mV
        let current: Double? // mA
    }

    let systemSample: System?
    let portSamples: [PortSample]?
}

extension Port {
    /// N for a Mac USB-C port named "Port-USB-C@N".
    var usbCNumber: Int? {
        guard id.hasPrefix("Port-USB-C@") else { return nil }
        return Int(id.split(separator: "@").last ?? "")
    }
}
