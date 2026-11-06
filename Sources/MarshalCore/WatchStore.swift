import Combine
import Darwin
import Foundation

@MainActor
public final class WatchStore: ObservableObject {
    public static let storageKey = "marshal.watch.v1"
    @Published public private(set) var settings = WatchSettings()
    @Published public private(set) var session: WatchSession?
    @Published public private(set) var isCounting = false
    @Published public private(set) var status = "Watch-time reminders are off"
    @Published public private(set) var request: AttentionRequest?
    @Published public private(set) var previewLevel: Int?
    @Published public var browserStatus: [String: String] = [:]
    @Published public var connectingBrowser: String?
    public var connectBrowser: ((String) -> Void)?
    private var engine = WatchEngine()
    private let defaults: UserDefaults?
    private let uptime: () -> TimeInterval
    private var previewTask: Task<Void, Never>?
    private var previewID = UUID().uuidString

    // Continuous monotonic time lets sleep expire episodes/snoozes without counting it as viewing.
    public init(defaults: UserDefaults? = nil, uptime: @escaping () -> TimeInterval = {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }) {
        self.defaults = defaults; self.uptime = uptime
        if let data = defaults?.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(WatchSettings.self, from: data), saved.isValid {
            settings = saved
        }
        if settings.enabled { status = "Waiting for a watched app or site" }
    }
    public var currentRule: WatchRule? { session.flatMap { s in settings.rules.first { $0.id == s.ruleID } } }
    public var isSnoozed: Bool { (session?.snoozedUntil ?? 0) > uptime() }

    @discardableResult
    public func configure(_ edit: (inout WatchSettings) -> Void) -> Bool {
        var value = settings
        edit(&value)
        guard value.isValid else { return false }
        settings = value
        if !value.enabled {
            engine = WatchEngine()
            isCounting = false; status = "Watch-time reminders are off"
            stopPreview()
        } else {
            engine.retainRules(Set(value.rules.filter(\.enabled).map(\.id)))
            engine.observe(ruleID: nil, at: uptime())
            isCounting = false; status = "Waiting for a watched app or site"
        }
        if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: Self.storageKey) }
        publish()
        return true
    }
    public func observe(ruleID: String?, status: String) {
        let validID = settings.enabled ? ruleID.flatMap { id in settings.rules.contains { $0.enabled && $0.id == id } ? id : nil } : nil
        engine.observe(ruleID: validID, at: uptime())
        isCounting = validID != nil
        self.status = settings.enabled ? status : "Watch-time reminders are off"
        publish()
    }
    public func snooze() {
        if previewLevel != nil { stopPreview(); return }
        engine.snooze(at: uptime()); publish()
    }
    public func reset() {
        if previewLevel != nil { stopPreview(); return }
        engine.resetCurrent(); isCounting = false
        status = settings.enabled ? "Waiting for a watched app or site" : "Watch-time reminders are off"
        publish()
    }
    public func dismiss() {
        if previewLevel != nil { stopPreview(); return }
        if let rule = currentRule { engine.dismiss(rule: rule) }
        publish()
    }
    public func preview(firm: Bool) {
        stopPreview()
        previewID = UUID().uuidString
        previewLevel = firm ? 2 : 1
        publish()
        previewTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.stopPreview()
        }
    }
    public func stopPreview() {
        previewTask?.cancel(); previewTask = nil
        previewLevel = nil
        publish()
    }
    private func publish() {
        session = engine.displayed
        if let previewLevel {
            request = AttentionRequest(id: "watch:preview:\(previewID):\(previewLevel)", kind: previewLevel == 2 ? .watchFirm : .watchGentle,
                                       title: previewLevel == 2 ? "Time for a screen break?" : "A little breather?",
                                       detail: "Preview · YouTube · \(previewLevel == 2 ? 45 : 30)m")
        } else if let rule = currentRule {
            request = engine.request(rule: rule, at: uptime())
        } else { request = nil }
    }
}
