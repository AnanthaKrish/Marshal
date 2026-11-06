import AppKit
import MarshalCore
import SwiftUI

/// `Marshal --snapshot <dir>` renders every widget state to PNG and exits.
/// Handy for README images and for checking the UI without a display.
@MainActor
enum Snapshot {
    static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let state = MarshalState()
        let agents = AgentSessionStore()
        let vitals = VitalsMonitor()
        let clock = SnapshotClock()
        let focus = FocusCoordinator(clock: { clock.now })
        var usage = UsageStore()
        let watch = WatchStore(uptime: { clock.now.timeIntervalSinceReferenceDate })
        // Fixed numbers so the vitals line renders the same every time.
        let demoVitals = Vitals(cpu: 0.37, cpuRaw: 0.37,
                                memoryUsed: UInt64(18.2 * 1_073_741_824), memoryTotal: 36 << 30,
                                batteryLevel: 82, sampledAt: Date(timeIntervalSince1970: 0))
        vitals.ingest(demoVitals, now: demoVitals.sampledAt)
        let store = NotchGeometryStore(
            geometry: NotchGeometry(width: 185, height: 32, hasNotch: true)
        )
        let backdrop = Color(white: 0.9)

        render(
            PookieFigure(size: 84, skin: state.skin, gaze: CGPoint(x: 0.5, y: 0.2), animates: false)
                .padding(16)
                .background(backdrop),
            name: "robot", in: dir
        )

        render(
            PookieFigure(size: 84, skin: state.skin, gaze: CGPoint(x: 0.5, y: 0.2),
                         mood: .needsPermission, animates: false)
                .padding(16)
                .background(backdrop),
            name: "robot-needs-you", in: dir
        )

        // Every skin side by side.
        render(
            HStack(spacing: 18) {
                ForEach(PookieSkin.all) { skin in
                    VStack(spacing: 6) {
                        PookieFigure(size: 72, skin: skin, gaze: CGPoint(x: 0.2, y: 0.1), animates: false)
                        Text(skin.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .background(backdrop),
            name: "pookie-skins", in: dir
        )

        // Every mood side by side.
        let moods: [(String, AgentState?, Bool)] = [
            ("Idle", nil, false), ("Working", .working, false), ("Needs you", .needsPermission, false),
            ("Waiting", .needsInput, false), ("Finished", .done, true), ("Error", .error, false),
        ]
        render(
            HStack(spacing: 18) {
                ForEach(moods, id: \.0) { label, mood, celebrating in
                    VStack(spacing: 6) {
                        PookieFigure(size: 72, skin: state.skin, gaze: CGPoint(x: 0.1, y: 0.1),
                                     mood: mood, isCelebrating: celebrating, animates: false)
                        Text(label)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .background(backdrop),
            name: "pookie-moods", in: dir
        )

        // Every vitals condition side by side, with what it implies.
        let conditions: [(String, VitalsConditions)] = [
            ("Sweating", .sweating), ("Hot", .hot), ("Overheated", .overheated), ("Stuffed", .stuffed),
            ("Dizzy", .dizzy), ("Sleepy", .sleepy), ("Crying", .crying),
        ]
        render(
            HStack(spacing: 18) {
                ForEach(conditions, id: \.0) { label, condition in
                    VStack(spacing: 6) {
                        PookieFigure(size: 72, skin: state.skin, gaze: CGPoint(x: 0.1, y: 0.1),
                                     vitals: VitalsLook.derive(conditions: VitalsConditions.implied(condition),
                                                               mood: nil, isCelebrating: false),
                                     animates: false)
                        Text(label)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .background(backdrop),
            name: "pookie-vitals", in: dir
        )

        focus.update(sessions: agents.sessions, conditions: vitals.conditions)
        state.isRobotExpanded = true
        render(
            RobotWidgetView(mover: NullMover())
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(agents)
                .environmentObject(vitals)
                .frame(width: RobotWindowController.expandedSize.width,
                       height: RobotWindowController.expandedSize.height)
                .background(backdrop),
            name: "robot-expanded", in: dir
        )
        state.isRobotExpanded = false

        let collapsed = NotchWindowController.collapsedSize(for: store.geometry)
        render(
            NotchWidgetView()
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(agents)
                .environmentObject(vitals)
                .environmentObject(store)
                .frame(width: collapsed.width, height: collapsed.height)
                .background(backdrop),
            name: "notch", in: dir
        )

        // A long process name truncates before it reaches the eyes.
        let hotVitals = VitalsMonitor()
        let hot = Vitals(cpu: 0.93, cpuRaw: 0.93, memoryUsed: 34 << 30, memoryTotal: 36 << 30,
                         thermal: .serious, batteryLevel: 82,
                         topProcess: TopProcess(name: "com.apple.WebKit.WebContent", cpu: 2.12),
                         sampledAt: Date(timeIntervalSince1970: 0))
        hotVitals.ingest(hot, now: hot.sampledAt) // thermal serious: hot at once
        render(
            NotchWidgetView()
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(agents)
                .environmentObject(hotVitals)
                .environmentObject(store)
                .frame(width: collapsed.width, height: collapsed.height)
                .background(backdrop),
            name: "notch-long-label", in: dir
        )

        state.isNotchExpanded = true
        let expanded = NotchWindowController.expandedSize(for: store.geometry)
        render(
            NotchWidgetView()
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(agents)
                .environmentObject(vitals)
                .environmentObject(store)
                .frame(width: expanded.width, height: NotchWindowController.expandedSize(for: store.geometry, hasNudge: focus.nudge != nil).height)
                .background(backdrop),
            name: "notch-expanded", in: dir
        )

        // The same two panels with three agents reporting.
        let now = clock.now
        let projects = NSHomeDirectory() + "/Desktop/Mywork"
        agents.apply(AgentEvent(agent: "claude-code", session: "docs", state: .done, title: "docs",
                                project: projects + "/docs"),
                     now: now.addingTimeInterval(-12 * 60))
        agents.apply(AgentEvent(agent: "codex", session: "marshal", state: .working, title: "Marshal",
                                project: projects + "/Marshal"),
                     now: now.addingTimeInterval(-65 * 60))
        // The first row (worst state first) has an app, so its card can open it.
        agents.apply(AgentEvent(agent: "claude-code", session: "flowapp", state: .needsPermission,
                                title: "FlowApp", project: projects + "/FlowApp", message: "Bash",
                                appPath: "/System/Applications/Utilities/Terminal.app"),
                     now: now.addingTimeInterval(-2 * 60))

        focus.update(sessions: agents.sessions, conditions: vitals.conditions)
        state.isRobotExpanded = true
        render(
            RobotWidgetView(mover: NullMover())
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(agents)
                .environmentObject(vitals)
                .frame(width: RobotWindowController.expandedSize.width,
                       height: RobotWindowController.expandedSize.height)
                .background(backdrop),
            name: "robot-expanded-agents", in: dir
        )

        // Hover cannot be rendered offscreen, so this variant forces the
        // "Open ↗" chip on cards that can open their app.
        render(
            RobotWidgetView(mover: NullMover())
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(agents)
                .environmentObject(vitals)
                .environment(\.showsOpenChipAlways, true)
                .frame(width: RobotWindowController.expandedSize.width,
                       height: RobotWindowController.expandedSize.height)
                .background(backdrop),
            name: "robot-expanded-agents-hover", in: dir
        )

        // The widest the card's vitals get: a large memory figure, a charging
        // bolt and a two-word suffix row, above three agent cards.
        let worstVitals = VitalsMonitor()
        let worst = Vitals(cpu: 0.93, cpuRaw: 0.93,
                           memoryUsed: UInt64(120.4 * 1_073_741_824), memoryTotal: 128 << 30,
                           memoryPressure: .warning, thermal: .serious,
                           batteryLevel: 82, isCharging: true,
                           sampledAt: Date(timeIntervalSince1970: 0))
        worstVitals.ingest(worst, now: worst.sampledAt) // [sweating, hot, stuffed] at once
        render(
            RobotWidgetView(mover: NullMover())
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(agents)
                .environmentObject(worstVitals)
                .frame(width: RobotWindowController.expandedSize.width,
                       height: RobotWindowController.expandedSize.height)
                .background(backdrop),
            name: "robot-expanded-vitals-worst", in: dir
        )
        state.isRobotExpanded = false

        render(
            NotchWidgetView()
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(store)
                .environmentObject(agents)
                .environmentObject(vitals)
                .frame(width: expanded.width, height: NotchWindowController.expandedSize(for: store.geometry, hasNudge: focus.nudge != nil).height)
                .background(backdrop),
            name: "notch-expanded-agents", in: dir
        )

        // Collapsed, the strip says how many agents need you.
        state.isNotchExpanded = false
        render(
            NotchWidgetView()
                .environmentObject(state)
                .environmentObject(focus).environmentObject(usage).environmentObject(watch)
                .environmentObject(store)
                .environmentObject(agents)
                .environmentObject(vitals)
                .frame(width: collapsed.width, height: collapsed.height)
                .background(backdrop),
            name: "notch-needs-you", in: dir
        )

        // Phase 3: both surfaces share the same focus and quiet state.
        func panels(_ name: String, dark: Bool = false, monitor: VitalsMonitor? = nil) {
            let panelVitals = monitor ?? vitals
            focus.update(sessions: agents.sessions, conditions: panelVitals.conditions)
            state.isRobotExpanded = true
            render(
                RobotWidgetView(mover: NullMover())
                    .environmentObject(state).environmentObject(agents)
                    .environmentObject(panelVitals).environmentObject(focus).environmentObject(usage).environmentObject(watch)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: RobotWindowController.expandedSize.width,
                           height: RobotWindowController.expandedSize.height)
                    .background(dark ? Color(white: 0.12) : backdrop),
                name: "robot-" + name, in: dir)
            state.isNotchExpanded = true
            render(
                NotchWidgetView()
                    .environmentObject(state).environmentObject(agents)
                    .environmentObject(panelVitals).environmentObject(focus).environmentObject(usage).environmentObject(watch).environmentObject(store)
                    .frame(width: expanded.width, height: NotchWindowController.expandedSize(for: store.geometry, hasNudge: focus.nudge != nil).height).background(backdrop),
                name: "notch-" + name, in: dir)
        }

        focus.startFocus(minutes: 25)
        clock.now += 378
        focus.tick()
        usage.apply(UsageSample(agent: "claude-code", session: "flowapp",
                                context: ContextUsage(usedPercent: 76, capacity: 200000, updatedAt: .now),
                                windows: [UsageWindow(id: "5h", title: "5h", usedPercent: 76, resetsAt: Date.now.addingTimeInterval(7200)),
                                          UsageWindow(id: "weekly", title: "Weekly", usedPercent: 34, resetsAt: Date.now.addingTimeInterval(172800))],
                                updatedAt: .now))
        usage.apply(UsageSample(agent: "codex", session: "marshal",
                                context: ContextUsage(usedPercent: 42, usedTokens: 108528, capacity: 258400, updatedAt: .now, isEstimate: true),
                                windows: [UsageWindow(id: "5h", title: "5h", usedPercent: 92, resetsAt: Date.now.addingTimeInterval(1500)),
                                          UsageWindow(id: "weekly", title: "Weekly", usedPercent: 54, resetsAt: Date.now.addingTimeInterval(259200))],
                                updatedAt: .now))
        panels("focus-approval")
        state.detailTab = .usage
        panels("usage")
        state.detailTab = .chats
        render(
            HStack(alignment: .top, spacing: 16) {
                RobotWidgetView(mover: NullMover())
                    .frame(width: RobotWindowController.expandedSize.width,
                           height: RobotWindowController.expandedSize.height)
                NotchWidgetView()
                    .frame(width: expanded.width,
                           height: NotchWindowController.expandedSize(for: store.geometry, hasNudge: true).height)
            }
            .environmentObject(state).environmentObject(agents)
            .environmentObject(vitals).environmentObject(focus).environmentObject(usage).environmentObject(watch).environmentObject(store)
            .environment(\.colorScheme, .light)
            .background(backdrop),
            name: "compact-panels", in: dir)
        agents.dismiss("claude-code:flowapp")
        panels("focus")
        state.isNotchExpanded = false
        render(
            NotchWidgetView()
                .environmentObject(state).environmentObject(agents)
                .environmentObject(vitals).environmentObject(focus).environmentObject(usage).environmentObject(watch).environmentObject(store)
                .frame(width: collapsed.width, height: collapsed.height).background(backdrop),
            name: "notch-focus-collapsed", in: dir)
        focus.pauseFocus()
        panels("focus-paused")
        focus.quiet(forMinutes: 30)
        panels("focus-quiet", dark: true)
        focus.endQuiet()
        focus.resumeFocus()
        clock.now += 1122
        focus.tick()
        panels("focus-complete")
        focus.dismissNudge()
        for _ in 0..<60 { clock.now += 60; focus.tick() }
        panels("break")
        focus.acknowledgeBreak()
        for index in 0..<7 {
            agents.apply(AgentEvent(agent: "codex", session: "long-\(index)", state: .working,
                                    title: "A very long project name with more detail \(index)",
                                    project: "/tmp/project-\(index)", appPath: "/System/Applications/Utilities/Terminal.app"))
            usage.apply(UsageSample(agent: "codex", session: "long-\(index)",
                                    context: ContextUsage(usedPercent: Double(66 + index * 5), updatedAt: .now, isEstimate: true),
                                    updatedAt: .now))
        }
        panels("many-sessions")

        agents.clearAll()
        agents.apply(AgentEvent(agent: "codex", session: "single-chat", state: .needsInput,
                                title: "Polish the notch layout and chat controls",
                                project: "/tmp/Marshal", appPath: "/System/Applications/Utilities/Terminal.app"))
        panels("single-chat")

        let critical = Vitals(cpu: 0.93, cpuRaw: 0.93, memoryUsed: 34 << 30, memoryTotal: 36 << 30,
                              memoryPressure: .critical, thermal: .critical, batteryLevel: 8,
                              sampledAt: clock.now)
        let criticalMonitor = VitalsMonitor()
        criticalMonitor.ingest(critical, now: clock.now)
        panels("critical-vitals", monitor: criticalMonitor)

        var desktopVitals = demoVitals
        desktopVitals.batteryLevel = nil
        let desktopMonitor = VitalsMonitor()
        desktopMonitor.ingest(desktopVitals, now: clock.now)
        panels("no-battery", monitor: desktopMonitor)

        state.detailTab = .usage
        usage.apply(UsageSample(agent: "codex", windows: [], updatedAt: .now))
        usage.setMessage("Sign in to Codex to see limits", for: "codex")
        panels("usage-unavailable")
        usage = UsageStore()
        usage.apply(UsageSample(agent: "claude-code",
                                windows: [UsageWindow(id: "5h", title: "5h", usedPercent: 100, resetsAt: Date.now.addingTimeInterval(-60))],
                                updatedAt: Date.now.addingTimeInterval(-600)))
        usage.apply(UsageSample(agent: "codex",
                                windows: [UsageWindow(id: "weekly", title: "Weekly", usedPercent: 82, resetsAt: Date.now.addingTimeInterval(86400))],
                                updatedAt: Date.now.addingTimeInterval(-600)))
        panels("usage-stale")
        state.detailTab = .chats

        agents.clearAll()
        agents.apply(AgentEvent(agent: "codex", session: "border-error", state: .error,
                                title: "Marshal", appPath: "/System/Applications/Utilities/Terminal.app"))
        panels("error")

        // A compact palette reference; live sweeps/pulses are frozen for review.
        let borderModes: [(String, ActivitySignal)] = [
            ("Idle · slow sweep", .idle),
            ("Working · green sweep", .working),
            ("Focus · violet progress", .focus(progress: 0.55, paused: false)),
            ("Approval · amber pulse", .permission),
            ("Error · red pulse", .error),
            ("Quiet · still, dim rim", .quiet(focusProgress: 0.55)),
        ]
        render(
            VStack(spacing: 24) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(0..<3, id: \.self) { column in
                            let entry = borderModes[row * 3 + column]
                            VStack(spacing: 12) {
                                NotchShape(flare: 8, bottomRadius: 12)
                                    .fill(.black)
                                    .overlay {
                                        NotchBorder(light: ActivityLight(signal: entry.1, skin: state.skin), flare: 8, bottomRadius: 12,
                                                    expanded: false, hovered: false, animates: false)
                                    }
                                    .frame(width: 185, height: 46)
                                Text(entry.0)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }
            .padding(24)
            .background(Color(white: 0.08)),
            name: "notch-borders", in: dir)

        // Both surfaces draw from exactly the same palette and selected activity.
        let activities: [(String, ActivitySignal, AgentState?)] = [
            ("Idle", .idle, nil),
            ("Working", .working, .working),
            ("Waiting", .waiting, .needsInput),
            ("Approval", .permission, .needsPermission),
            ("Error / critical vitals", .error, .error),
            ("Focus", .focus(progress: 0.55, paused: false), nil),
            ("Break reminder", .reminder, nil),
            ("Finished", .finished, .done),
            ("Quiet + focus", .quiet(focusProgress: 0.55), nil),
        ]
        render(
            VStack(spacing: 24) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(0..<3, id: \.self) { column in
                            let entry = activities[row * 3 + column]
                            VStack(spacing: 10) {
                                PookieFigure(size: 64, skin: state.skin, mood: entry.2,
                                             isCelebrating: entry.1 == .finished,
                                             isYawning: entry.1 == .reminder,
                                             showsFloorShadow: false, activity: entry.1, animates: false)
                                NotchShape(flare: 8, bottomRadius: 12)
                                    .fill(.black)
                                    .overlay {
                                        NotchBorder(light: ActivityLight(signal: entry.1, skin: state.skin),
                                                    flare: 8, bottomRadius: 12,
                                                    expanded: false, hovered: false, animates: false)
                                    }
                                    .frame(width: 185, height: 36)
                                Text(entry.0)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }
            }
            .padding(24)
            .background(Color(white: 0.08)),
            name: "activity-colors", in: dir)

        let lightPreview = RimLightPreviewModel(selected: .default)
        lightPreview.play()
        render(RimLightPreviewView(state: state, preview: lightPreview, close: {})
            .preferredColorScheme(.light), name: "rim-light-picker", in: dir)
        render(RimLightPreviewView(state: state, preview: lightPreview, close: {})
            .preferredColorScheme(.dark), name: "rim-light-picker-dark", in: dir)
        lightPreview.stop()
        render(
            VStack(alignment: .leading, spacing: 24) {
                Text("Pookie · rim light only").font(.system(size: 20, weight: .semibold, design: .rounded))
                ForEach(CompletionLightStyle.allCases) { style in
                    HStack(spacing: 22) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(style.name).font(.system(size: 13, weight: .semibold))
                            Text(style.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(width: 150, alignment: .leading)
                        ForEach([0.0, 1.0, 2.0, 4.0], id: \.self) { time in
                            VStack(spacing: 5) {
                                PookieFigure(size: 66, skin: state.skin,
                                             completionLightStyle: style, lightFrame: time,
                                             activity: .finished, animates: false)
                                    .frame(height: 85)
                                Text(String(format: "%.2gs", time)).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24).background(Color(white: 0.94)).preferredColorScheme(.light),
            name: "rim-light-options", in: dir)
        render(
            VStack(alignment: .leading, spacing: 16) {
                Text("Light trace · follows the shell").font(.system(size: 16, weight: .semibold))
                HStack(spacing: 24) {
                    ForEach([0.7, 1.6, 2.6, 3.6], id: \.self) { time in
                        VStack(spacing: 8) {
                            PookieFigure(size: 130, skin: state.skin,
                                         completionLightStyle: .trace, lightFrame: time,
                                         showsFloorShadow: false, activity: .finished, animates: false)
                            Text(String(format: "%.1fs", time)).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(24).background(Color(white: 0.94)).preferredColorScheme(.light),
            name: "rim-trace-border", in: dir)

        // Parked prototype renders are retained for a future iteration.
        if FeatureAvailability.watchTime {
            // Phase 4: simulated foreground intervals, with no browser access or real history.
            agents.clearAll()
            focus.endFocus(); focus.endQuiet(); focus.setBreaksEnabled(false)
            state.detailTab = .watch
            panels("watch-off")
            watch.configure { $0.enabled = true; $0.browsers.insert("com.google.Chrome") }
            watch.browserStatus["com.google.Chrome"] = "Connected"
            let watchedID = watch.settings.rules[0].id
            watch.observe(ruleID: watchedID, status: "Counting foreground time with audio")
            for _ in 0..<96 { clock.now += 5; watch.observe(ruleID: watchedID, status: "Counting foreground time with audio") }
            focus.updateWatch(watch.request)
            panels("watch-active")
            watch.configure { $0.countInBackground = true }
            watch.observe(ruleID: watchedID, status: "Counting audio while you use another app")
            panels("watch-multitasking")
            for _ in 0..<264 { clock.now += 5; watch.observe(ruleID: watchedID, status: "Counting foreground time with audio") }
            focus.updateWatch(watch.request)
            panels("watch-yawn")
            for _ in 0..<180 { clock.now += 5; watch.observe(ruleID: watchedID, status: "Counting foreground time with audio") }
            focus.updateWatch(watch.request)
            panels("watch-firm")
            focus.quiet(forMinutes: 15)
            panels("watch-quiet", dark: true)
            focus.endQuiet()
            watch.snooze(); focus.updateWatch(watch.request)
            panels("watch-snoozed")
            watch.observe(ruleID: nil, status: "Browser access needed · open Watch-time settings")
            focus.updateWatch(watch.request)
            panels("watch-access-needed")
            render(WatchSettingsView(watch: watch).preferredColorScheme(.light), name: "watch-settings", in: dir)
            render(WatchSettingsView(watch: watch).preferredColorScheme(.dark), name: "watch-settings-dark", in: dir)
        }

        print("Snapshots written to \(dir.path)")
    }

    private static func render<V: View>(_ view: V, name: String, in dir: URL) {
        // Native hosting captures ScrollView and Menu as well as SwiftUI drawing.
        // ImageRenderer omits AppKit-backed controls (empty lists and yellow placeholders).
        let host = NSHostingView(rootView: view
            .environment(\.isSnapshot, true)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            })
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            window.close()
            print("Could not render \(name)")
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        window.contentView = nil
        window.close()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            print("Could not encode \(name)")
            return
        }
        do {
            try png.write(to: dir.appendingPathComponent("\(name).png"))
        } catch {
            print("Could not write \(name): \(error)")
        }
    }
}

/// A mover that goes nowhere; used when rendering offscreen.
@MainActor
final class NullMover: PanelMover {
    var currentOrigin: CGPoint { .zero }
    func move(to origin: CGPoint) {}
    func endMove() {}
}

@MainActor
private final class SnapshotClock {
    var now = Date.now
}

extension EnvironmentValues {
    @Entry var isSnapshot = false
}
