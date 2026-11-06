import Darwin
import Foundation
import os

public enum MemorySampler {
    /// used = (active + wired + compressed) × page size.
    public static func used(active: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
        (active + wired + compressed) * pageSize
    }

    /// `host_statistics64(HOST_VM_INFO64)` for used, `sysctl hw.memsize` for total.
    public static func sample() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        var memsize: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &memsize, &size, nil, 0) == 0 else { return nil }
        let used = used(active: UInt64(stats.active_count), wired: UInt64(stats.wire_count),
                        compressed: UInt64(stats.compressor_page_count), pageSize: UInt64(pageSize))
        return (used, memsize)
    }

    /// `sysctl vm.swapusage` → `xsu_used` in bytes.
    public static func swapUsed() -> UInt64? {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return nil }
        return swap.xsu_used
    }
}

/// Holds the last memory-pressure level the kernel reported. Events arrive on
/// a private queue; `latest` is readable (and settable, for tests) from any thread.
public final class MemoryPressureWatcher: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<MemoryPressure>(initialState: .normal)
    private let sourceLock = OSAllocatedUnfairLock()
    private var source: DispatchSourceMemoryPressure?  // guarded by sourceLock
    private let queue = DispatchQueue(label: "marshal.vitals.memory-pressure")

    public init() {}

    deinit { source?.cancel() }

    public var latest: MemoryPressure {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// Idempotent. Seeds `latest` from `kern.memorystatus_vm_pressure_level`
    /// so a launch under pressure is not reported as normal until the next event.
    public func start() {
        sourceLock.withLock {
            guard source == nil else { return }
            if let seeded = Self.currentLevel() { latest = seeded }
            let s = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
            s.setEventHandler { [weak self, weak s] in
                guard let s else { return }
                let event = s.data
                let level: MemoryPressure =
                    event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
                self?.latest = level
            }
            s.resume()
            source = s
        }
    }

    /// Idempotent. Keeps `latest` as last seen.
    public func stop() {
        sourceLock.withLock {
            source?.cancel()
            source = nil
        }
    }

    /// 1 normal, 2 warning, 4 critical (DISPATCH_MEMORYPRESSURE_* values).
    static func currentLevel() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
