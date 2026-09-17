import Foundation
import IOKit.ps

/// Watches the system's power sources and publishes a `PowerSnapshot`
/// whenever anything changes.
///
/// IOKit delivers change notifications through a run loop source on the main
/// run loop, so everything here stays on the main actor. A slow fallback
/// timer covers the rare cases where an estimate changes without a
/// notification.
@MainActor
final class PowerMonitor {
    private(set) var snapshot: PowerSnapshot = .empty
    var onChange: ((PowerSnapshot) -> Void)?

    // The run loop source is only ever touched on the main actor, but Swift
    // cannot prove that for `deinit`, hence the unsafe annotation.
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    private var fallbackTask: Task<Void, Never>?
    nonisolated(unsafe) private var lowPowerObserver: NSObjectProtocol?
    private let weakSelf = WeakBox<PowerMonitor>()

    /// Fallback polling interval in seconds.
    var fallbackInterval: Duration = .seconds(60)

    init() {
        weakSelf.value = self
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        fallbackTask?.cancel()
    }

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // The source is scheduled on the main run loop, so the callback
            // always arrives on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
            }
        }, context)?.takeRetainedValue() {
            // Common modes so updates keep flowing while a menu is open.
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        } else {
            NSLog("Lithe: IOPSNotificationCreateRunLoopSource failed; relying on polling")
        }

        let box = weakSelf
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { box.value?.refresh() }
        }

        fallbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.fallbackInterval else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                self?.refresh()
            }
        }

        refresh(force: true)
    }

    /// Re-reads the power sources and notifies the observer if anything
    /// visible changed (or always, when `force` is set).
    func refresh(force: Bool = false) {
        let new = Self.readSnapshot()
        let changed = new.sources != snapshot.sources
            || new.externalPowerConnected != snapshot.externalPowerConnected
            || new.lowPowerMode != snapshot.lowPowerMode
        snapshot = new
        if changed || force {
            onChange?(new)
        }
    }

    /// Reads the current state of every power source from IOKit.
    nonisolated static func readSnapshot() -> PowerSnapshot {
        var sources: [PowerSource] = []
        var providing = kIOPSACPowerValue
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [Any] {
                for entry in list {
                    // `Get`, not `Copy`: the dictionary is owned by the blob.
                    if let description = IOPSGetPowerSourceDescription(blob, entry as CFTypeRef)?
                        .takeUnretainedValue() as? [String: Any] {
                        sources.append(PowerSourceParser.parse(description))
                    }
                }
            }
            if let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() {
                providing = type as String
            }
        }
        return PowerSnapshot(
            sources: sources,
            externalPowerConnected: providing == kIOPSACPowerValue,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

/// A weak reference that can be captured by `@Sendable` closures which are
/// known to run on the main thread (notification observers on the main queue).
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
}
