import Darwin
import Foundation

/// Cumulative CPU ticks summed over all cores. busy = user + system + nice.
public struct CPUTicks: Equatable, Sendable {
    public var busy: UInt64
    public var total: UInt64

    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

public enum CPUSampler {
    /// Reads `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`; nil if the call fails.
    public static func ticks() -> CPUTicks? {
        var count: natural_t = 0
        var info: processor_info_array_t? = nil
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        // The kernel allocates this array in our address space; we must give it back.
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(count) {
            let base = i * Int(CPU_STATE_MAX)
            // Ticks are unsigned 32-bit counters stored as integer_t.
            let u = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let s = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let n = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            busy += u + s + n
            total += u + s + n + idle
        }
        return CPUTicks(busy: busy, total: total)
    }

    /// Busy fraction between two snapshots, clamped to 0...1; 0 when the
    /// total delta is zero or negative (counters reset or wrapped).
    public static func load(previous: CPUTicks, current: CPUTicks) -> Double {
        guard current.total > previous.total else { return 0 }
        let total = Double(current.total - previous.total)
        let busy = Double(current.busy) - Double(previous.busy)
        return min(1, max(0, busy / total))
    }
}

/// Mean of the last `window` values pushed (fewer while filling).
public struct MovingAverage: Sendable {
    private let window: Int
    private var values: [Double] = []

    public init(window: Int) {
        self.window = max(1, window)
        values.reserveCapacity(self.window)
    }

    public mutating func push(_ x: Double) -> Double {
        if values.count == window { values.removeFirst() }
        values.append(x)
        return values.reduce(0, +) / Double(values.count)
    }
}
