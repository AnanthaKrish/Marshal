import AppKit
import ImageIO
import MarshalCore
import SwiftUI
import UniformTypeIdentifiers

/// Reproducible repository artwork made from the shipping views and fictional data.
/// No monitors, sockets, hooks, live account data, or standard preferences are used.
@MainActor
enum ReadmeArtwork {
    static func run(directory: String) throws {
        let destination = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let demo = ArtworkDemo()
        defer { demo.cleanup() }
        try png(PookieFigure(size: 400, skin: .indigo, gaze: CGPoint(x: -0.15, y: 0.1),
                             isHappy: true, showsFloorShadow: false, animates: false).padding(60),
                size: CGSize(width: 580, height: 520), name: "pookie-reference.png", in: destination)
        try png(showcase(demo), size: CGSize(width: 1400, height: 1040), name: "showcase.png", in: destination)
        try png(signals, size: CGSize(width: 1400, height: 520), name: "signals.png", in: destination)
        try png(colours, size: CGSize(width: 1400, height: 450), name: "colours.png", in: destination)
        try png(social, size: CGSize(width: 1200, height: 630), name: "social-preview.png", in: destination)
        try png(trace(time: 1.8), size: CGSize(width: 800, height: 320), name: "trace-still.png", in: destination)
        try traceGIF(at: destination.appendingPathComponent("trace.gif"))
        print("README artwork written to \(destination.path)")
    }

    private static func overline(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold, design: .monospaced))
            .tracking(2.5).foregroundStyle(Color(red: 0.65, green: 0.64, blue: 1))
    }
    private static func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 19)).foregroundStyle(Color.white.opacity(0.55))
    }
    private static func showcase(_ demo: ArtworkDemo) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            overline("MEET YOUR DESKTOP'S NEW +1")
            HStack(alignment: .bottom) {
                Text("One companion.\nTwo places to land.")
                    .font(.system(size: 54, weight: .bold, design: .rounded)).tracking(-1.8)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                caption("Agent status. Focus. System health.\nRight where you need them.")
                    .multilineTextAlignment(.trailing).lineSpacing(5).padding(.bottom, 7)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    overline("01 / POOKIE")
                    caption("A little character. Anywhere on screen.")
                    RobotWidgetView(mover: NullMover())
                        .frame(width: 380, height: 480)
                        .scaleEffect(1.08).frame(width: 460, height: 520)
                        .environmentObject(demo.state)
                        .environmentObject(demo.agents).environmentObject(demo.vitals)
                        .environmentObject(demo.focus).environmentObject(demo.usage)
                        .environmentObject(demo.watch)
                }
                .padding(26).frame(width: 516, height: 672, alignment: .topLeading)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 26))
                VStack(alignment: .leading, spacing: 20) {
                    overline("02 / THE NOTCH")
                    caption("A quiet presence. A useful little island.")
                    VStack(spacing: 0) {
                        HStack {
                            Text("YOUR WORKSPACE").tracking(1.8)
                            Spacer()
                            Image(systemName: "wifi")
                            Image(systemName: "battery.100percent")
                        }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 22).frame(height: 34)
                        .background(.black.opacity(0.4))
                        NotchWidgetView()
                            .frame(width: 528, height: 318)
                            .scaleEffect(1.1, anchor: .top).frame(width: 584, height: 350)
                            .environmentObject(demo.state).environmentObject(demo.geometry)
                            .environmentObject(demo.agents).environmentObject(demo.vitals)
                            .environmentObject(demo.focus).environmentObject(demo.usage)
                            .environmentObject(demo.watch)
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            Circle().fill(Color.green.opacity(0.8)).frame(width: 6, height: 6)
                            Text("Everything in view. Your focus stays put.")
                                .font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
                        }.padding(.bottom, 24)
                    }
                    .frame(width: 648, height: 514)
                    .background(LinearGradient(colors: [Color(red: 0.085, green: 0.09, blue: 0.17), Color(red: 0.035, green: 0.04, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .padding(26).frame(width: 732, height: 672, alignment: .topLeading)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 26))
            }
        }
        .padding(64).frame(width: 1400, height: 1040, alignment: .topLeading)
        .foregroundStyle(.white).background(ArtworkBackdrop())
    }

    private static var signals: some View {
        let states: [(String, String, AgentState?, Bool, ActivitySignal)] = [
            ("Working", "Let it cook.", .working, false, .working),
            ("Needs you", "Your approval, please.", .needsPermission, false, .permission),
            ("Finished", "That one's a wrap.", .done, true, .finished),
            ("Focus", "Keep your flow.", nil, false, .focus(progress: 0.64, paused: false)),
            ("Error", "A little help here.", .error, false, .error)
        ]
        return VStack(alignment: .leading, spacing: 22) {
            overline("LESS CHECKING. MORE KNOWING.")
            Text("A face for every state.").font(.system(size: 46, weight: .bold, design: .rounded)).tracking(-1)
            HStack(spacing: 10) {
                ForEach(states, id: \.0) { label, detail, mood, celebrating, activity in
                    VStack(spacing: 12) {
                        PookieFigure(size: 174, skin: .indigo, mood: mood, isCelebrating: celebrating,
                                     lightFrame: 4.5, showsFloorShadow: false, activity: activity, animates: false)
                            .frame(height: 194)
                        Text(label).font(.system(size: 23, weight: .semibold, design: .rounded))
                        caption(detail).font(.system(size: 16))
                    }.frame(maxWidth: .infinity)
                }
            }
        }.padding(64).frame(width: 1400, height: 520, alignment: .topLeading)
            .foregroundStyle(.white).background(ArtworkBackdrop())
    }
    private static var colours: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    overline("YOUR DESK. YOUR VIBE.")
                    Text("Pick your Pookie.").font(.system(size: 46, weight: .bold, design: .rounded)).tracking(-1)
                }
                Spacer()
                caption("Six colours. A little personality in each.").padding(.bottom, 5)
            }
            HStack(spacing: 14) {
                ForEach(PookieSkin.all) { skin in
                    VStack(spacing: 10) {
                        PookieFigure(size: 153, skin: skin, gaze: CGPoint(x: 0.1, y: 0), isHappy: true,
                                     showsFloorShadow: false, animates: false).frame(height: 175)
                        Text(skin.name).font(.system(size: 19, weight: .medium, design: .rounded))
                    }.frame(maxWidth: .infinity)
                }
            }
        }.padding(64).frame(width: 1400, height: 450, alignment: .topLeading)
            .foregroundStyle(.white).background(ArtworkBackdrop())
    }
    private static var social: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 22) {
                overline("A LITTLE COMPANY FOR YOUR MAC")
                Text("Marshal.").font(.system(size: 110, weight: .bold, design: .rounded)).tracking(-6)
                Text("Your agents work.\nPookie keeps an eye out.")
                    .font(.system(size: 32, weight: .medium)).lineSpacing(5).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 18) {
                    Text("macOS"); Text("SwiftUI"); Text("Open source")
                }.font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4)).padding(.top, 12)
            }
            Spacer(minLength: 0)
            PookieFigure(size: 320, skin: .indigo, gaze: CGPoint(x: -0.2, y: 0), isHappy: true,
                         showsFloorShadow: false, activity: .working, animates: false)
                .rotationEffect(.degrees(-8)).padding(.trailing, 12)
        }.padding(76).frame(width: 1200, height: 630)
            .foregroundStyle(.white).background(ArtworkBackdrop())
    }
    private static func trace(time: Double) -> some View {
        HStack(spacing: 38) {
            PookieFigure(size: 215, skin: .indigo, isHappy: true, completionLightStyle: .trace,
                         lightFrame: time, showsFloorShadow: false, activity: .finished, animates: false)
            VStack(alignment: .leading, spacing: 14) {
                overline("THE TRACE LIGHT").font(.system(size: 12))
                Text("Done.\nNicely done.").font(.system(size: 43, weight: .bold, design: .rounded)).tracking(-1)
                Text("A little celebration, right on the edge.")
                    .font(.system(size: 16)).foregroundStyle(.white.opacity(0.6))
                Text("Native rim animation · looped preview")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
            }.frame(width: 380, alignment: .leading)
        }.padding(48).frame(width: 800, height: 320)
            .foregroundStyle(.white).background(ArtworkBackdrop())
    }
    private static func traceGIF(at url: URL) throws {
        let frames = 72
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { throw ArtworkError.encoding }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frames {
            let bitmap = try capture(trace(time: Double(frame) / 12), size: CGSize(width: 800, height: 320), settle: 0.02)
            guard let image = bitmap.cgImage else { throw ArtworkError.encoding }
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ArtworkError.encoding }
    }
    private static func png<V: View>(_ view: V, size: CGSize, name: String, in directory: URL) throws {
        let bitmap = try capture(view, size: size)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ArtworkError.encoding }
        try data.write(to: directory.appendingPathComponent(name))
    }
    private static func capture<V: View>(_ view: V, size: CGSize, settle: TimeInterval = 0.15) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .environment(\.isSnapshot, true).preferredColorScheme(.dark)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.contentView = host; window.orderFront(nil); host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        // Keep repository dimensions independent of the current screen's Retina scale.
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { window.close(); throw ArtworkError.capture }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        window.contentView = nil; window.close()
        return bitmap
    }
    private enum ArtworkError: Error { case capture, encoding }
}

private struct ArtworkBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.025, green: 0.028, blue: 0.055)
                RadialGradient(colors: [Color(red: 0.22, green: 0.17, blue: 0.52).opacity(0.48), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 0.85)
                Canvas { context, size in
                    var path = Path()
                    for x in stride(from: 0.0, through: size.width, by: 48) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                    for y in stride(from: 0.0, through: size.height, by: 48) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                    context.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 0.5)
                }
            }
        }
    }
}

@MainActor
private final class ArtworkDemo {
    private let suite = "Marshal.ReadmeArtwork.\(UUID().uuidString)"
    private let defaults: UserDefaults
    let state: MarshalState
    let agents = AgentSessionStore()
    let vitals = VitalsMonitor()
    let usage = UsageStore()
    let watch = WatchStore()
    let geometry = NotchGeometryStore(geometry: NotchGeometry(width: 185, height: 32, hasNotch: true))
    let focus: FocusCoordinator
    init() {
        defaults = UserDefaults(suiteName: suite)!
        state = MarshalState(defaults: defaults)
        let origin = Date.now
        focus = FocusCoordinator(clock: { origin })
        state.skinID = "indigo"; state.isRobotExpanded = true; state.isNotchExpanded = true
        state.detailTab = .chats
        agents.apply(AgentEvent(agent: "codex", session: "sample-api", state: .working,
                                title: "Build the settings screen", appPath: "/System/Applications/Utilities/Terminal.app"))
        agents.apply(AgentEvent(agent: "claude-code", session: "sample-review", state: .needsPermission,
                                title: "Review the latest changes", message: "Run tests", appPath: "/System/Applications/Utilities/Terminal.app"))
        vitals.ingest(Vitals(cpu: 0.24, cpuRaw: 0.24, memoryUsed: 16 << 30, memoryTotal: 36 << 30,
                             batteryLevel: 86, sampledAt: origin), now: origin)
        focus.startFocus(minutes: 25)
        focus.update(sessions: agents.sessions, conditions: [])
        for (agent, id, percent) in [("codex", "sample-api", 42.0), ("claude-code", "sample-review", 76.0)] {
            usage.apply(UsageSample(agent: agent, session: id,
                                    context: ContextUsage(usedPercent: percent, capacity: 200_000, updatedAt: origin),
                                    windows: [UsageWindow(id: "5h", title: "5h", usedPercent: percent, resetsAt: origin.addingTimeInterval(7200))],
                                    updatedAt: origin))
        }
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite) }
}
