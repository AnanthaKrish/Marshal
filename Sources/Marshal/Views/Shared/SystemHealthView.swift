import MarshalCore
import SwiftUI

/// Calm labelled metrics; warnings use words as well as colour.
struct SystemHealthView: View {
    var style: SurfaceStyle
    @EnvironmentObject private var monitor: VitalsMonitor

    var body: some View {
        if style == .notch {
            notchStatus
        } else {
            cardStatus
        }
    }

    private var notchStatus: some View {
        HStack(spacing: 12) {
            inlineMetric("CPU", value: "\(Int((monitor.vitals.cpu * 100).rounded()))%")
                .help(monitor.vitals.topProcess.map { "\($0.name) · \(Int(($0.cpu * 100).rounded()))% of one core" } ?? "Total CPU use")
            inlineMetric("Memory", value: memory,
                         tint: monitor.conditions.contains(.dizzy) ? RobotPalette.alert : monitor.conditions.contains(.stuffed) ? RobotPalette.attention : nil)
                .help(VitalsFormat.memory(used: monitor.vitals.memoryUsed, total: monitor.vitals.memoryTotal))
            Spacer(minLength: 0)
            Label(thermal, systemImage: "thermometer.medium")
                .foregroundStyle(monitor.conditions.contains(.overheated) ? RobotPalette.alert : monitor.conditions.contains(.hot) ? RobotPalette.attention : style.secondary)
                .accessibilityLabel("Thermal: \(thermal)")
            if let level = monitor.vitals.batteryLevel {
                Label("\(level)%", systemImage: batterySymbol(level: level))
                    .foregroundStyle(monitor.conditions.contains(.crying) ? RobotPalette.alert : style.secondary)
                    .accessibilityLabel("\(monitor.vitals.isCharging ? "Charging" : "Battery"): \(level) percent")
            }
        }
        .font(.system(size: 10)).monospacedDigit().lineLimit(1)
        .padding(.top, 7)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.09)).frame(height: 1) }
        .help(monitor.override.map { "Preview: \($0.headline ?? "normal")" } ?? health)
    }

    private func inlineMetric(_ name: String, value: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(.white.opacity(0.4))
            Text(value).foregroundStyle(tint ?? style.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func batterySymbol(level: Int) -> String {
        if monitor.vitals.isCharging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var cardStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if monitor.override != nil || !monitor.conditions.isEmpty {
                HStack {
                    Text("System")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(monitor.override.map { "Preview: \($0.headline ?? "normal")" } ?? health)
                        .font(.system(size: 10))
                        .foregroundStyle(monitor.conditions.isEmpty ? style.secondary : RobotPalette.attention)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 0) {
                metric("CPU", value: "\(Int((monitor.vitals.cpu * 100).rounded()))%")
                    .help(monitor.vitals.topProcess.map { "\($0.name) · \(Int(($0.cpu * 100).rounded()))% of one core" } ?? "Total CPU use")
                metric("Memory", value: memory)
                    .help(VitalsFormat.memory(used: monitor.vitals.memoryUsed, total: monitor.vitals.memoryTotal))
                metric("Thermal", value: thermal)
                if let level = monitor.vitals.batteryLevel {
                    metric(monitor.vitals.isCharging ? "Charging" : "Battery", value: "\(level)%")
                }
            }
        }
        .foregroundStyle(style.primary)
        .padding(8)
        .background(style.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .help(health)
    }

    private func metric(_ name: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 9)).foregroundStyle(style.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var memory: String {
        guard monitor.vitals.memoryTotal > 0 else { return "—" }
        return "\(Int((Double(monitor.vitals.memoryUsed) / Double(monitor.vitals.memoryTotal) * 100).rounded()))%"
    }

    private var thermal: String {
        switch monitor.vitals.thermal {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        }
    }

    private var health: String {
        if monitor.conditions.contains(.dizzy) { return "High memory pressure" }
        if monitor.conditions.contains(.overheated) { return "Needs cooling" }
        if monitor.conditions.contains(.crying) { return "Low battery" }
        if monitor.conditions.contains(.hot) { return "Running warm" }
        if monitor.conditions.contains(.stuffed) { return "Memory pressure" }
        if monitor.conditions.contains(.sleepy) { return "Battery below 20%" }
        if monitor.conditions.contains(.sweating) { return "Working hard" }
        return "Looking good"
    }
}
