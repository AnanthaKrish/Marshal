import AppKit
import Foundation
import Combine

enum FeatureAvailability {
    // Parked at AK's request. Keep the prototype available for a later iteration.
    static let watchTime = false
}

/// Single source of truth for what the two widgets are doing.
/// Window controllers observe this; SwiftUI views bind to it.
@MainActor
final class MarshalState: ObservableObject {
    private let defaults: UserDefaults
    private enum Keys {
        static let robotVisible = "marshal.robot.visible"
        static let notchVisible = "marshal.notch.visible"
        static let skin = "marshal.pookie.skin"
        static let completionLight = "marshal.pookie.completionLight"
    }

    @Published var isRobotExpanded = false
    @Published var isNotchExpanded = false
    enum DetailTab { case chats, usage, watch }
    @Published var detailTab: DetailTab = .chats
    var refreshUsage: (() -> Void)?
    var showWatchSettings: (() -> Void)?

    @Published var isRobotVisible: Bool {
        didSet { defaults.set(isRobotVisible, forKey: Keys.robotVisible) }
    }

    @Published var isNotchVisible: Bool {
        didSet { defaults.set(isNotchVisible, forKey: Keys.notchVisible) }
    }

    /// Pookie's colour scheme. Stored by id so new skins can be added freely.
    @Published var skinID: String {
        didSet { defaults.set(skinID, forKey: Keys.skin) }
    }

    var skin: PookieSkin { PookieSkin.named(skinID) }

    @Published var completionLightStyle: CompletionLightStyle {
        didSet { defaults.set(completionLightStyle.rawValue, forKey: Keys.completionLight) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isRobotVisible = defaults.object(forKey: Keys.robotVisible) as? Bool ?? true
        isNotchVisible = defaults.object(forKey: Keys.notchVisible) as? Bool ?? true
        skinID = defaults.string(forKey: Keys.skin) ?? PookieSkin.default.id
        completionLightStyle = defaults.string(forKey: Keys.completionLight).flatMap(CompletionLightStyle.init(rawValue:)) ?? .default
    }

    func toggleRobotExpanded() {
        isRobotExpanded.toggle()
        if isRobotExpanded { isNotchExpanded = false }
    }

    func toggleNotchExpanded() {
        isNotchExpanded.toggle()
        if isNotchExpanded { isRobotExpanded = false }
    }

    func collapseAll() {
        isRobotExpanded = false
        isNotchExpanded = false
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

