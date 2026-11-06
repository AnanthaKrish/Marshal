/// What Pookie's face shows for a set of vitals conditions, after the
/// composition rules with agent moods. A pure function of its inputs so the
/// rules can be tested without drawing anything.
public struct VitalsLook: Equatable, Sendable {
    /// Sweat drops on the temples: 0, 1 or 2.
    public var sweat: Int
    /// How far the shell (and the idle rim) blends toward the heat colour: 0, 0.45 or 0.85.
    public var heat: Double
    /// Eyes narrowed to a squint.
    public var squint: Bool
    /// Mouth becomes a small pulsing oval.
    public var pant: Bool
    /// Cheeks grown and tinted to the body colour.
    public var puffCheeks: Bool
    /// Pupils replaced by rotating spirals.
    public var spiralEyes: Bool
    /// Lids over the top of each eye.
    public var sleepyLids: Bool
    /// Ice-blue tears and a frown.
    public var coldTears: Bool
    /// The whole head wobbles.
    public var wobble: Bool
    /// The idle rim light at half opacity.
    public var rimDim: Bool

    public init(
        sweat: Int = 0, heat: Double = 0, squint: Bool = false, pant: Bool = false,
        puffCheeks: Bool = false, spiralEyes: Bool = false, sleepyLids: Bool = false,
        coldTears: Bool = false, wobble: Bool = false, rimDim: Bool = false
    ) {
        self.sweat = sweat
        self.heat = heat
        self.squint = squint
        self.pant = pant
        self.puffCheeks = puffCheeks
        self.spiralEyes = spiralEyes
        self.sleepyLids = sleepyLids
        self.coldTears = coldTears
        self.wobble = wobble
        self.rimDim = rimDim
    }

    /// Nothing to show.
    public static let none = VitalsLook()

    /// The look for `conditions`, given the agent `mood` and whether Pookie
    /// is celebrating. Conflicts resolve in this order: agent error tears beat
    /// cold tears; heart eyes beat spirals and lids; the overheated squint
    /// beats lids. Sweat, heat and puffed cheeks layer with any mood.
    public static func derive(conditions: VitalsConditions, mood: AgentState?, isCelebrating: Bool) -> VitalsLook {
        var look = VitalsLook()
        let overheated = conditions.contains(.overheated)
        let hot = conditions.contains(.hot)

        if hot || overheated {
            look.sweat = 2
        } else if conditions.contains(.sweating) {
            look.sweat = 1
        }

        if overheated {
            look.heat = 0.85
        } else if hot {
            look.heat = 0.45
        }

        look.squint = overheated
        look.pant = overheated
        look.puffCheeks = conditions.contains(.stuffed)

        let dizzy = conditions.contains(.dizzy)
        look.spiralEyes = dizzy && !isCelebrating
        look.wobble = dizzy

        let sleepy = conditions.contains(.sleepy)
        look.sleepyLids = sleepy && !isCelebrating && !overheated
        look.rimDim = sleepy

        look.coldTears = conditions.contains(.crying) && mood != .error
        return look
    }
}

extension VitalsConditions {
    /// The single most telling condition's name, for "demo: hot":
    /// overheated > dizzy > crying > hot > stuffed > sleepy > sweating.
    /// nil when empty.
    public var headline: String? {
        let order: [(VitalsConditions, String)] = [
            (.overheated, "overheated"), (.dizzy, "dizzy"), (.crying, "crying"), (.hot, "hot"),
            (.stuffed, "stuffed"), (.sleepy, "sleepy"), (.sweating, "sweating"),
        ]
        return order.first { contains($0.0) }?.1
    }
}

/// Chooses the short status the collapsed notch strip shows when no agent
/// label applies. Pure, so the priority and texts can be tested.
public enum NotchVitalsLabel {
    /// The label for `conditions`, or nil when none of them earns one
    /// (sweating alone does not). Priority: overheated > dizzy > crying
    /// (alert, red) > hot > stuffed > sleepy (amber). While a demo override
    /// is set (`isDemo`) the numbers read "demo".
    public static func label(conditions: VitalsConditions, vitals: Vitals, isDemo: Bool) -> (text: String, isAlert: Bool)? {
        if conditions.contains(.overheated) { return (hotText(vitals, isDemo), true) }
        if conditions.contains(.dizzy) { return (memoryText(vitals, isDemo), true) }
        if conditions.contains(.crying) { return (batteryText(vitals, isDemo), true) }
        if conditions.contains(.hot) { return (hotText(vitals, isDemo), false) }
        if conditions.contains(.stuffed) { return (memoryText(vitals, isDemo), false) }
        if conditions.contains(.sleepy) { return (batteryText(vitals, isDemo), false) }
        return nil
    }

    private static func hotText(_ v: Vitals, _ isDemo: Bool) -> String {
        if isDemo { return "Hot: demo" }
        if let top = v.topProcess { return "Hot: \(top.name)" }
        // The top process is sampled every 10 s once sweating; until the
        // first one lands, say how busy the CPU is.
        return "Hot \(percent(v.cpu))%"
    }

    private static func memoryText(_ v: Vitals, _ isDemo: Bool) -> String {
        if isDemo { return "Mem: demo" }
        return "Mem \(gigabytes(v.memoryUsed))/\(gigabytes(v.memoryTotal))"
    }

    private static func batteryText(_ v: Vitals, _ isDemo: Bool) -> String {
        if isDemo { return "Battery: demo" }
        if let level = v.batteryLevel { return "Battery \(level)%" }
        return "Battery low"
    }

    private static func percent(_ share: Double) -> Int { Int((share * 100).rounded()) }
    private static func gigabytes(_ bytes: UInt64) -> Int { Int(VitalsFormat.gigabytes(bytes).rounded()) }
}

/// Text for the vitals line. Memory is binary (`hw.memsize` reports 36 GiB
/// as 38.65e9 bytes), so "GB" here means GiB, as Activity Monitor shows it.
public enum VitalsFormat {
    public static func gigabytes(_ bytes: UInt64) -> Double { Double(bytes) / 1_073_741_824 }

    /// `CPU 37% · Mem 18.2 / 36 GB`
    public static func cpuAndMemory(_ v: Vitals) -> String {
        "CPU \(Int((v.cpu * 100).rounded()))% · \(memory(used: v.memoryUsed, total: v.memoryTotal))"
    }

    /// `Mem 18.2 / 36 GB`: one decimal for used, none for total.
    public static func memory(used: UInt64, total: UInt64) -> String {
        "Mem \(String(format: "%.1f", gigabytes(used))) / \(String(format: "%.0f", gigabytes(total))) GB"
    }

    /// `Battery 82%`, `Battery 82% charging`, or nil without a battery.
    public static func battery(_ v: Vitals) -> String? {
        guard let level = v.batteryLevel else { return nil }
        return "Battery \(level)%" + (v.isCharging ? " charging" : "")
    }

    /// `CPU 37% · Mem 18.2 / 36 GB · Battery 82%`: the card's numbers row,
    /// with no "charging" word (the card draws a bolt instead).
    public static func numbers(_ v: Vitals) -> String {
        [cpuAndMemory(v), v.batteryLevel.map { "Battery \($0)%" }].compactMap { $0 }.joined(separator: " · ")
    }

    /// The whole line on one row, "charging" spelled out (as text, e.g. a tooltip or log).
    public static func line(_ v: Vitals) -> String {
        [cpuAndMemory(v), battery(v)].compactMap { $0 }.joined(separator: " · ")
    }
}
