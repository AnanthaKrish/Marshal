import Darwin
import Foundation

public enum TopProcessSampler {
    /// Mach time units → nanoseconds. `ri_user_time`/`ri_system_time` are in
    /// Mach absolute time units, which on Apple Silicon are not nanoseconds
    /// (timebase 125/3: 24 M units per CPU second).
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        return tb.denom == 0 ? (1, 1) : (UInt64(tb.numer), UInt64(tb.denom))
    }()

    /// CPU time used so far (user + system, nanoseconds) for every process we
    /// can read. Processes whose rusage cannot be read are skipped.
    public static func snapshot() -> [Int32: UInt64] {
        let capacity = max(1024, Int(proc_listallpids(nil, 0)) + 64)
        var pids = [pid_t](repeating: 0, count: capacity)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return [:] }
        let tb = timebase
        var result: [Int32: UInt64] = [:]
        result.reserveCapacity(Int(n))
        for pid in pids.prefix(min(Int(n), pids.count)) where pid > 0 {
            var ru = rusage_info_current()
            let ok = withUnsafeMutablePointer(to: &ru) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard ok == 0 else { continue }
            let ticks = ru.ri_user_time &+ ru.ri_system_time
            result[pid] = ticks.multipliedFullWidth(by: tb.numer).high == 0
                ? ticks * tb.numer / tb.denom
                : ticks / tb.denom * tb.numer
        }
        return result
    }

    /// The process with the largest CPU-time delta. `cpu` is delta ns /
    /// (interval s × 1e9): the share of one core, so it can exceed 1 for a
    /// multi-threaded process on a multi-core machine. Pids absent from either
    /// snapshot, or whose counter went backwards (pid reuse), are skipped.
    public static func top(previous: [Int32: UInt64], current: [Int32: UInt64],
                           interval: TimeInterval) -> TopProcess? {
        top(previous: previous, current: current, interval: interval, name: name(of:))
    }

    static func top(previous: [Int32: UInt64], current: [Int32: UInt64], interval: TimeInterval,
                    name: (Int32) -> String?) -> TopProcess? {
        guard interval > 0 else { return nil }
        var best: (pid: Int32, delta: UInt64)?
        for (pid, now) in current {
            guard let before = previous[pid], now > before else { continue }
            let delta = now - before
            if let b = best, delta < b.delta || (delta == b.delta && pid > b.pid) { continue }
            best = (pid, delta)  // ties go to the lower pid, for determinism
        }
        guard let best else { return nil }
        return TopProcess(name: name(best.pid) ?? "pid \(best.pid)",
                          cpu: Double(best.delta) / (interval * 1e9))
    }

    static func name(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let s = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return s.isEmpty ? nil : s
    }
}
