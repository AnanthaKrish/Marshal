import Foundation

public enum MemoryPressure: String, Codable, Sendable {
    case normal, warning, critical
}

/// Ordered by its Int raw value; encoded by name (`"serious"`) so
/// `marshal vitals` reads well. Decodes either form.
public enum ThermalLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    case nominal, fair, serious, critical

    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            guard let level = Self.allCases.first(where: { $0.name == name }) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown thermal level \(name)")
            }
            self = level
        } else {
            let raw = try container.decode(Int.self)
            guard let level = Self(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown thermal level \(raw)")
            }
            self = level
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

public struct TopProcess: Equatable, Codable, Sendable {
    public var name: String
    public var cpu: Double

    public init(name: String, cpu: Double) {
        self.name = name
        self.cpu = cpu
    }
}

public struct Vitals: Equatable, Codable, Sendable {
    /// 0...1, 10 s moving average.
    public var cpu: Double
    /// 0...1, the latest 2 s delta.
    public var cpuRaw: Double
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var swapUsed: UInt64
    public var memoryPressure: MemoryPressure
    public var thermal: ThermalLevel
    /// nil on desktops.
    public var batteryLevel: Int?
    public var isCharging: Bool
    public var topProcess: TopProcess?
    public var sampledAt: Date

    public init(cpu: Double = 0, cpuRaw: Double = 0,
                memoryUsed: UInt64 = 0, memoryTotal: UInt64 = 0, swapUsed: UInt64 = 0,
                memoryPressure: MemoryPressure = .normal, thermal: ThermalLevel = .nominal,
                batteryLevel: Int? = nil, isCharging: Bool = false,
                topProcess: TopProcess? = nil, sampledAt: Date = .now) {
        self.cpu = cpu
        self.cpuRaw = cpuRaw
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.swapUsed = swapUsed
        self.memoryPressure = memoryPressure
        self.thermal = thermal
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.topProcess = topProcess
        self.sampledAt = sampledAt
    }
}

public struct VitalsConditions: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let sweating = VitalsConditions(rawValue: 1 << 0)
    public static let hot = VitalsConditions(rawValue: 1 << 1)
    public static let overheated = VitalsConditions(rawValue: 1 << 2)
    public static let stuffed = VitalsConditions(rawValue: 1 << 3)
    public static let dizzy = VitalsConditions(rawValue: 1 << 4)
    public static let sleepy = VitalsConditions(rawValue: 1 << 5)
    public static let crying = VitalsConditions(rawValue: 1 << 6)

    /// `base` plus everything it implies: hot => sweating, overheated => hot, crying => sleepy.
    public static func implied(_ base: VitalsConditions) -> VitalsConditions {
        var r = base
        if r.contains(.overheated) { r.insert(.hot) }
        if r.contains(.hot) { r.insert(.sweating) }
        if r.contains(.crying) { r.insert(.sleepy) }
        return r
    }
}
