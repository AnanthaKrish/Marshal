import AppKit
import Combine
import MarshalCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = MarshalState()
    let agents = AgentSessionStore()
    /// Machine vitals for Pookie and the notch. Started once after launch.
    let vitals = VitalsMonitor()
    let focus = FocusCoordinator(defaults: .standard)
    let usage = UsageStore()
    let watch = WatchStore(defaults: FeatureAvailability.watchTime ? .standard : nil)
    private var watchMonitor: WatchMonitor?
    private var watchSettings: WatchSettingsController?
    private var usageMonitor: UsageMonitor?
    private var focusSubscriptions = Set<AnyCancellable>()
    private var server: SocketServer?
    private var expiryTask: Task<Void, Never>?
    private var robot: RobotWindowController?
    private var notch: NotchWindowController?
    private var statusBar: StatusBarController?
    private var eventMonitors: [Any] = []
    private let menuInteraction = MenuInteraction()

    func applicationDidFinishLaunching(_ notification: Notification) {
        agents.$sessions.combineLatest(vitals.$conditions)
            .sink { [weak self] sessions, conditions in
                self?.focus.update(sessions: sessions, conditions: conditions)
            }
            .store(in: &focusSubscriptions)
        focus.start()
        startAgentServer()
        robot = RobotWindowController(state: state, agents: agents, vitals: vitals, focus: focus, usage: usage, watch: watch)
        notch = NotchWindowController(state: state, agents: agents, vitals: vitals, focus: focus, usage: usage, watch: watch)
        statusBar = StatusBarController(state: state, robot: robot!, focus: focus)
        installClickOutsideMonitors()
        vitals.start()
        let monitor = UsageMonitor(store: usage, agents: agents)
        usageMonitor = monitor
        state.refreshUsage = { [weak monitor] in monitor?.refresh() }
        monitor.start()
        if FeatureAvailability.watchTime {
            let watchMonitor = WatchMonitor(store: watch)
            self.watchMonitor = watchMonitor
            let settings = WatchSettingsController(store: watch)
            watchSettings = settings
            state.showWatchSettings = { [weak settings] in settings?.show() }
            focus.dismissWatch = { [weak watch] in watch?.dismiss() }
            watch.$request.removeDuplicates().sink { [weak focus] request in focus?.updateWatch(request) }
                .store(in: &focusSubscriptions)
            watchMonitor.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        expiryTask?.cancel()
        vitals.stop()
        focus.stop()
        usageMonitor?.stop()
        watchMonitor?.stop()
        server?.stop()
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    /// Installs the CLI shim and listens on the socket for agent events.
    /// Failures here never stop the app; a server error is shown in the list.
    private func startAgentServer() {
        try? MarshalPaths.ensureDirectories()

        let agents = self.agents
        let server = SocketServer(path: MarshalPaths.socket.path) { event in
            Task { @MainActor in agents.apply(event) }
        }
        var anotherInstance = false
        do {
            try server.start()
            self.server = server
        } catch let error as POSIXError where error.code == .EADDRINUSE {
            anotherInstance = true
            agents.serverError = "Another Marshal is already running."
        } catch {
            agents.serverError = error.localizedDescription
        }

        // The running instance owns the shim; a second copy must not repoint it.
        if !anotherInstance, let executable = Bundle.main.executableURL {
            let cli = executable.deletingLastPathComponent().appendingPathComponent("marshal-cli")
            try? ShimInstaller.install(binaryPath: cli.path)
        }

        expiryTask = Task { [agents] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                agents.expire()
            }
        }
    }

    /// Collapse an expanded widget when the user clicks anywhere else.
    /// The global monitor sees clicks in other apps; the local monitor sees
    /// clicks inside Marshal's own windows.
    private func installClickOutsideMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            MainActor.assumeIsolated {
                guard !self.menuInteraction.isTracking else { return }
                self.state.collapseAll()
            }
        }) {
            eventMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated {
                if self.menuInteraction.shouldDismiss(isExpanded: self.state.isRobotExpanded,
                                                       clickedInside: event.window === self.robot?.panel) {
                    self.state.isRobotExpanded = false
                }
                if self.menuInteraction.shouldDismiss(isExpanded: self.state.isNotchExpanded,
                                                       clickedInside: event.window === self.notch?.panel) {
                    self.state.isNotchExpanded = false
                }
            }
            return event
        }) {
            eventMonitors.append(local)
        }
    }
}
