import AppKit
import Combine
import MarshalCore

struct WatchApplication: Equatable, Sendable {
    let pid: Int32
    let bundleID: String
    init(pid: Int32, bundleID: String) { self.pid = pid; self.bundleID = bundleID }
    init?(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, !app.isTerminated else { return nil }
        self.init(pid: app.processIdentifier, bundleID: id)
    }
}

@MainActor
final class WatchMonitor {
    private let store: WatchStore
    private let frontmost: () -> WatchApplication?
    private let runningApps: () -> [WatchApplication]
    private let readBrowser: @Sendable (WatchBrowser, Int32, Bool) async -> WatchBrowserResult
    private let audioActivity: @Sendable (Int32, String) async -> WatchAudioActivity
    private var task: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var suspensionReasons: Set<String> = []
    private var suspended: Bool { !suspensionReasons.isEmpty }
    private var generation = 0
    private var lastCountedApp: WatchApplication?
    private var subscription: AnyCancellable?

    init(store: WatchStore,
         frontmost: @escaping () -> WatchApplication? = { NSWorkspace.shared.frontmostApplication.flatMap(WatchApplication.init) },
         runningApps: @escaping () -> [WatchApplication] = { NSWorkspace.shared.runningApplications.compactMap(WatchApplication.init) },
         readBrowser: (@Sendable (WatchBrowser, Int32, Bool) async -> WatchBrowserResult)? = nil,
         audioActivity: @escaping @Sendable (Int32, String) async -> WatchAudioActivity = { pid, bundle in
             await Task.detached(priority: .utility) { WatchAudioSampler.activity(pid: pid, bundleID: bundle) }.value
         }) {
        self.store = store; self.frontmost = frontmost; self.runningApps = runningApps
        let reader = WatchBrowserReader()
        self.readBrowser = readBrowser ?? { browser, pid, ask in await reader.read(browser, pid: pid, ask: ask) }
        self.audioActivity = audioActivity
    }
    func start() {
        guard task == nil else { return }
        store.connectBrowser = { [weak self] id in self?.connect(id) }
        subscription = store.$settings.dropFirst().sink { [weak self] _ in self?.generation += 1 }
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "system"),
                               (NSWorkspace.screensDidSleepNotification, "display"),
                               (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend(true, reason: reason) }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "system"),
                               (NSWorkspace.screensDidWakeNotification, "display"),
                               (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend(false, reason: reason) }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.generation += 1
                // Background audio can remain eligible through a foreground-app switch.
                if let self, !self.store.settings.countInBackground {
                    self.store.observe(ruleID: nil, status: "Checking the frontmost app")
                }
            }
        })
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    func stop() {
        task?.cancel(); task = nil
        connectionTask?.cancel(); connectionTask = nil
        subscription = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        store.connectBrowser = nil
        store.stopPreview()
    }
    private func suspend(_ value: Bool, reason: String) {
        if value { suspensionReasons.insert(reason) } else { suspensionReasons.remove(reason) }
        generation += 1
        store.observe(ruleID: nil, status: suspended ? "Paused while the screen or session is inactive" : "Waiting for a watched app or site")
    }
    private func connect(_ id: String) {
        guard connectionTask == nil, let browser = WatchBrowser.all.first(where: { $0.id == id }) else { return }
        guard let app = runningApps().first(where: { $0.bundleID == id }) else {
            store.browserStatus[id] = "Open \(browser.name), then connect"
            return
        }
        let pid = app.pid
        store.connectingBrowser = id
        let readBrowser = readBrowser
        connectionTask = Task { [weak self] in
            let result = await readBrowser(browser, pid, true)
            guard let self else { return }
            defer { self.store.connectingBrowser = nil; self.connectionTask = nil }
            guard !Task.isCancelled else { return }
            if case .host = result {
                self.store.configure { $0.browsers.insert(id) }
                self.store.browserStatus[id] = "Connected"
            } else {
                self.store.browserStatus[id] = "Allow Marshal in System Settings → Privacy → Automation"
            }
        }
    }
    // Injectable observations exercise the same live sampling path in regression tests.
    func sample() async {
        guard store.settings.enabled, !suspended else { return }
        guard let front = frontmost() else {
            store.observe(ruleID: nil, status: "No active app"); return
        }
        let version = generation
        let settings = store.settings
        let apps = runningApps()
        var candidates = [front]
        if settings.countInBackground {
            candidates += apps.filter { app in
                app.pid != front.pid && (settings.browsers.contains(app.bundleID) ||
                    settings.rules.contains { $0.enabled && $0.kind == .app && $0.target == app.bundleID })
            }.sorted {
                if ($0 == lastCountedApp) != ($1 == lastCountedApp) { return $0 == lastCountedApp }
                return $0.bundleID < $1.bundleID
            }
        }
        var reason: String?
        for app in candidates {
            let browser = WatchBrowser.all.first { $0.id == app.bundleID }
            let isForeground = app == front
            if let browser, !settings.browsers.contains(app.bundleID) {
                if isForeground { reason = "Connect \(browser.name) in Watch-time settings" }
                continue
            }
            let appRule = settings.match(host: nil, app: app.bundleID)
            guard browser != nil || appRule != nil else { continue }
            let name = browser?.name ?? appRule?.name ?? "app"

            // Never read an inactive browser's tab unless it has output audio.
            // Background counting always requires audio, even if foreground counting doesn't.
            if !isForeground || settings.requiresAudio {
                let audio = await audioActivity(app.pid, app.bundleID)
                guard valid(front, version: version, settings: settings), runningApps().contains(app) else { return }
                switch audio {
                case .silent: reason = "Paused · no audio activity in \(name)"; continue
                case .unavailable: reason = "Audio detection unavailable · check Watch-time settings"; continue
                case .active: break
                }
            }
            var rule = appRule
            if let browser {
                let result = await readBrowser(browser, app.pid, false)
                guard valid(front, version: version, settings: settings), runningApps().contains(app) else { return }
                switch result {
                case .host(let host):
                    store.browserStatus[app.bundleID] = "Connected"
                    rule = host.flatMap { settings.match(host: $0, app: app.bundleID) }
                case .denied, .permissionNeeded:
                    store.browserStatus[app.bundleID] = "Browser access needed"
                    reason = "\(name) access needed · open Watch-time settings"; continue
                case .unavailable:
                    reason = "Can't read \(name)'s selected tab"; continue
                }
            }
            guard let rule else { continue }
            guard valid(front, version: version, settings: settings), runningApps().contains(app) else { return }
            lastCountedApp = app
            store.observe(ruleID: rule.id, status: !isForeground ? "Counting audio while you use another app"
                          : settings.requiresAudio ? "Counting foreground time with audio" : "Counting foreground time")
            return
        }
        guard valid(front, version: version, settings: settings) else { return }
        let waiting = settings.countInBackground ? "Waiting for audio in a watched app or site"
            : store.session == nil ? "Bring a watched app or site to the front"
            : "Paused · bring your watched app or site to the front"
        store.observe(ruleID: nil, status: reason ?? waiting)
    }
    private func valid(_ front: WatchApplication, version: Int, settings: WatchSettings) -> Bool {
        !Task.isCancelled && store.settings.enabled && !suspended && version == generation &&
            store.settings == settings && frontmost() == front
    }
}
