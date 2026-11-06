import MarshalCore
import SwiftUI

enum SurfaceStyle {
    /// Light glass card under the robot.
    case card
    /// Black island under the notch.
    case notch

    var primary: Color { self == .notch ? .white : .primary }
    var secondary: Color { self == .notch ? .white.opacity(0.6) : .secondary }
}

/// A compact clock line, optionally followed by the vitals line
/// (CPU, memory, battery). Shared by both widgets so they feel like one app.
struct GlanceView: View {
    var style: SurfaceStyle
    var showsDetails = true

    /// The card reads left to right; the island's right column is trailing.
    private var alignment: HorizontalAlignment { style == .notch ? .trailing : .leading }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.secondary)
            }

            if showsDetails {
                VitalsLine(style: style)
            }
        }
    }
}

/// `CPU 37% · Mem 18.2 / 36 GB · Battery 82%` (a bolt when charging), with
/// `Hot` or `Memory pressure` on a second row when Pookie feels it. Reads
/// `demo: hot` while a "Try Vitals" override is set. In the notch's narrow
/// right column the battery wraps to a second row instead.
struct VitalsLine: View {
    var style: SurfaceStyle
    @EnvironmentObject private var monitor: VitalsMonitor

    var body: some View {
        Group {
            if let demo = monitor.override {
                Text("demo: \(demo.headline ?? "none")")
                    .fixedSize()
            } else if style == .notch {
                notchRows
                    .fixedSize()
            } else {
                cardRows
            }
        }
        .font(.system(size: style == .notch ? 10 : 11, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(style.secondary)
        .lineLimit(1)
        .modifier(TopProcessHelp(top: monitor.vitals.topProcess))
    }

    /// The numbers on one row, then the suffix in its own tinted row so the
    /// numbers never get pushed past the card's edge. As a last resort the
    /// numbers shrink a little rather than clip.
    private var cardRows: some View {
        let v = monitor.vitals
        return VStack(alignment: .leading, spacing: 1) {
            Group {
                if v.batteryLevel != nil, v.isCharging {
                    Text("\(VitalsFormat.numbers(v)) \(Image(systemName: "battery.100percent.bolt"))")
                } else {
                    Text(VitalsFormat.numbers(v))
                }
            }
            .minimumScaleFactor(0.85)
            suffix
        }
    }

    /// Two short rows that fit the island's right column without widening
    /// it: `CPU 37% · [battery] 82%` over `Mem 18.2 / 36 GB`. Instead of the
    /// suffix words, the CPU row turns amber/red when hot and the memory row
    /// when under pressure.
    private var notchRows: some View {
        let v = monitor.vitals
        let c = monitor.conditions
        return VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 0) {
                Text("CPU \(Int((v.cpu * 100).rounded()))%")
                    .foregroundStyle(Self.tint(hot: c.contains(.hot) || c.contains(.overheated),
                                               alert: c.contains(.overheated)) ?? style.secondary)
                if let level = v.batteryLevel {
                    Text(" · ")
                    Image(systemName: Self.batterySymbol(level: level, charging: v.isCharging))
                    Text(" \(level)%")
                }
            }
            Text(VitalsFormat.memory(used: v.memoryUsed, total: v.memoryTotal))
                .foregroundStyle(Self.tint(hot: c.contains(.stuffed) || c.contains(.dizzy),
                                           alert: c.contains(.dizzy)) ?? style.secondary)
        }
    }

    private static func batterySymbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private static func tint(hot: Bool, alert: Bool) -> Color? {
        guard hot else { return nil }
        return alert ? RobotPalette.alert : RobotPalette.attention
    }

    @ViewBuilder
    private var suffix: some View {
        if let suffix = Self.suffix(monitor.conditions) {
            Text(suffix.text)
                .foregroundStyle(suffix.isAlert ? RobotPalette.alert : RobotPalette.attention)
        }
    }

    /// `Hot` and/or `Memory pressure`: amber, or red for the whole suffix
    /// when overheated or dizzy.
    static func suffix(_ c: VitalsConditions) -> (text: String, isAlert: Bool)? {
        var parts: [String] = []
        if c.contains(.hot) || c.contains(.overheated) { parts.append("Hot") }
        if c.contains(.stuffed) || c.contains(.dizzy) { parts.append("Memory pressure") }
        guard !parts.isEmpty else { return nil }
        return (parts.joined(separator: " · "), c.contains(.overheated) || c.contains(.dizzy))
    }
}

/// The top process as a tooltip ("Xcode 212%"), only when one is known.
private struct TopProcessHelp: ViewModifier {
    var top: TopProcess?

    func body(content: Content) -> some View {
        if let top {
            content.help("\(top.name) \(Int((top.cpu * 100).rounded()))%")
        } else {
            content
        }
    }
}
