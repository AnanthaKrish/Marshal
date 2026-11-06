import Combine
import Foundation

/// Samples the machine and publishes `Vitals` and `conditions`.
///
/// Scheduling: one background task wakes on a single 1 s tick (continuous
/// clock, deadline-based so it does not drift) and dispatches by modulus:
/// CPU every 2 s, memory/pressure/thermal every 5 s, swap and battery every
/// 30 s, the top process every 10 s only while the assessed (not demo)
/// conditions contain `.sweating`. All Mach/sysctl/IOKit reads happen off
/// the main actor; only `ingest` runs on it. Ticks that sample nothing do
/// no work. A gap of more than 30 s between ticks (sleep) restarts the CPU
/// average and the assessor's pending windows.
@MainActor
public final class VitalsMonitor: ObservableObject {
    @Published public private(set) var vitals = Vitals()
    @Published public private(set) var conditions: VitalsConditions = []
    /// A demo set that replaces the assessed conditions until cleared.
    @Published public var override: VitalsConditions? {
        didSet { recompute() }
    }

    /// The last kernel memory-pressure event; read by every memory sample.
    public let pressure = MemoryPressureWatcher()

    private var assessor = VitalsAssessor()
    private var assessed: VitalsConditions = []
    private var task: Task<Void, Never>?

    public init() {}

    /// Idempotent.
    public func start() {
        guard task == nil else { return }
        pressure.start()
        let pressure = self.pressure
        task = Task.detached(priority: .utility) { [weak self] in
            var sampling = VitalsSampling()
            let clock = ContinuousClock()
            var deadline = clock.now
            var tick = 0
            while !Task.isCancelled {
                if sampling.resetAfterGap(now: .now) {
                    guard let self else { return }
                    await MainActor.run { self.resetAssessorTimers() }
                }
                let sweating = await self?.wantsTopProcess ?? false
                if let v = sampling.tick(tick, sweating: sweating, pressure: pressure.latest, now: .now) {
                    guard let self else { return }
                    // Checked on the main actor, after any stop() that ran first: no sample lands after stop().
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.ingest(v, now: v.sampledAt)
                    }
                }
                tick += 1
                deadline += .seconds(1)
                if deadline < clock.now { deadline = clock.now } // after sleep/wake, do not burst
                do { try await Task.sleep(until: deadline, clock: clock) } catch { return }
            }
        }
    }

    /// Cancels sampling and the pressure source. `vitals` and `conditions` keep their last values.
    public func stop() {
        task?.cancel()
        task = nil
        pressure.stop()
    }

    /// The single path that runs the assessor; the sampling task calls it too.
    public func ingest(_ v: Vitals, now: Date) {
        vitals = v
        assessed = assessor.assess(v, now: now)
        recompute()
    }

    /// Whether the real (assessed) conditions call for the top process. A
    /// demo override never does: a Sweating demo must not sample processes,
    /// and a Sleepy demo during real load still must.
    var wantsTopProcess: Bool { assessed.contains(.sweating) }

    /// After sleep the assessor's pending windows span the gap; start them over.
    func resetAssessorTimers() {
        assessor.resetTimers()
    }

    private func recompute() {
        let next = override ?? assessed
        if conditions != next { conditions = next }
    }
}

/// The sampling state carried between ticks. Not isolated; lives inside the
/// monitor's background task.
struct VitalsSampling {
    private var vitals = Vitals()
    private var cpuPrevious: CPUTicks?
    private var cpuAverage = MovingAverage(window: 5)
    private var topPrevious: (at: Date, cpu: [Int32: UInt64])?
    private var lastTickAt: Date?

    /// A longer gap between ticks than this means the Mac slept.
    static let maxTickGap: TimeInterval = 30

    /// Call at the start of every tick. After a gap longer than `maxTickGap`
    /// it drops the CPU average and the previous tick counts (they span the
    /// sleep) and returns true so the caller can reset the assessor's timers.
    mutating func resetAfterGap(now: Date) -> Bool {
        defer { lastTickAt = now }
        guard let last = lastTickAt, now.timeIntervalSince(last) > Self.maxTickGap else { return false }
        cpuPrevious = nil
        cpuAverage = MovingAverage(window: 5)
        topPrevious = nil
        return true
    }

    /// Runs whatever is due on tick `n` (seconds since start) and returns the
    /// updated vitals, or nil when nothing was due.
    mutating func tick(_ n: Int, sweating: Bool, pressure: MemoryPressure, now: Date) -> Vitals? {
        var changed = false

        if n % 2 == 0, let ticks = CPUSampler.ticks() {
            if let previous = cpuPrevious {
                let raw = CPUSampler.load(previous: previous, current: ticks)
                vitals.cpuRaw = raw
                vitals.cpu = cpuAverage.push(raw)
                changed = true
            }
            cpuPrevious = ticks
        }

        if n % 5 == 0 {
            if let m = MemorySampler.sample() {
                vitals.memoryUsed = m.used
                vitals.memoryTotal = m.total
            }
            vitals.memoryPressure = pressure
            vitals.thermal = ThermalSampler.current()
            changed = true
        }

        if n % 30 == 0 {
            if let swap = MemorySampler.swapUsed() { vitals.swapUsed = swap }
            let battery = BatterySampler.sample()
            vitals.batteryLevel = battery.level
            vitals.isCharging = battery.isCharging
            changed = true
        }

        if n % 10 == 0 {
            if sweating {
                let snapshot = TopProcessSampler.snapshot()
                if let previous = topPrevious {
                    vitals.topProcess = TopProcessSampler.top(
                        previous: previous.cpu, current: snapshot,
                        interval: now.timeIntervalSince(previous.at))
                }
                topPrevious = (now, snapshot)
            } else if topPrevious != nil || vitals.topProcess != nil {
                topPrevious = nil
                vitals.topProcess = nil
            }
            changed = true
        }

        guard changed else { return nil }
        vitals.sampledAt = now
        return vitals
    }
}
