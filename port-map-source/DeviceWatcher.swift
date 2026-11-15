import AppKit
import Foundation
import IOKit

/// Calls `onChange` shortly after a USB or Thunderbolt device is plugged in or removed, or the
/// display arrangement changes. Events arrive in bursts (a hub brings many devices), so they
/// are debounced into one call.
@MainActor
final class DeviceWatcher {
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var pending: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var onChange: (() -> Void)?
    private let delay: TimeInterval = 1.5

    func start(onChange: @escaping () -> Void) {
        guard port == nil else { return }
        self.onChange = onChange
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for className in ["IOUSBHostDevice", "IOThunderboltSwitch"] {
            for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
                var iterator: io_iterator_t = 0
                guard IOServiceAddMatchingNotification(port, kind, IOServiceMatching(className),
                                                       deviceChanged, context, &iterator) == KERN_SUCCESS else { continue }
                drain(iterator) // arms the notification; existing devices are not changes
                iterators.append(iterator)
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    fileprivate func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

private func drain(_ iterator: io_iterator_t) {
    while case let entry = IOIteratorNext(iterator), entry != 0 { IOObjectRelease(entry) }
}

/// IOKit callback, delivered on the main queue. The iterator must be emptied to re-arm it.
private func deviceChanged(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    drain(iterator)
    guard let context else { return }
    let watcher = Unmanaged<DeviceWatcher>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { watcher.schedule() }
}
