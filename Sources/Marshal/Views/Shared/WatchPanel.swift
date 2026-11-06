import MarshalCore
import SwiftUI

struct WatchPanel: View {
    var style: SurfaceStyle
    @EnvironmentObject private var watch: WatchStore
    @EnvironmentObject private var state: MarshalState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle").foregroundStyle(MarshalTheme.focus)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(watch.previewLevel != nil ? "Preview · YouTube" : watch.currentRule?.name ?? "Watch time")
                            .font(.system(size: 12, weight: .semibold))
                        Text(watch.previewLevel != nil ? "Preview ends automatically" : watch.status)
                            .font(.system(size: 9)).foregroundStyle(style.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(watch.previewLevel.map { "≈\($0 == 2 ? 45 : 30):00" }
                             ?? watch.session.map { "≈" + WatchText.counter($0.elapsed) } ?? "—")
                            .font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if watch.previewLevel == nil, watch.session != nil {
                            HStack(spacing: 3) {
                                Circle().fill(watch.isCounting ? Color.green : Color.secondary).frame(width: 4, height: 4)
                                Text(watch.isCounting ? "Counting" : "Paused")
                            }
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(style.secondary)
                        }
                    }
                    .help(watch.settings.countInBackground
                          ? "Estimated watch time, updated every 5 seconds. Audio can keep counting while you use another app."
                          : "Estimated watch time, updated every 5 seconds while the watched app is in front.")
                }
                if let rule = watch.currentRule {
                    Text("First \(rule.gentleMinutes)m · Firmer \(rule.firmMinutes)m\(watch.isSnoozed ? " · Snoozed" : "")")
                        .font(.system(size: 9)).foregroundStyle(style.secondary)
                }
                HStack(spacing: 12) {
                    Button(watch.settings.enabled ? "Settings…" : "Set up watch time…") { state.showWatchSettings?() }
                    if watch.session != nil || watch.previewLevel != nil {
                        Button("10m snooze") { watch.snooze() }
                        Button(watch.previewLevel != nil ? "End preview" : "Reset") { watch.reset() }
                    }
                }
                .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                .foregroundStyle(style == .notch ? MarshalTheme.focus : Color(red: 0.40, green: 0.30, blue: 0.72))
            }
            .padding(9).foregroundStyle(style.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        }.frame(maxHeight: .infinity)
    }
}
