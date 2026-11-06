import Foundation

/// One activity selection for both Pookie's rim and the notch outline.
/// Face expressions and individual session pills remain independent of this light.
public enum ActivitySignal: Equatable, Sendable {
    case idle, working, waiting, permission, error, reminder, finished
    case focus(progress: Double, paused: Bool)
    case quiet(focusProgress: Double?)

    public static func resolve(nudge: AttentionRequest.Kind?, mood: AgentState?,
                               timer: FocusTimer, isQuiet: Bool, now: Date) -> ActivitySignal {
        let hasFocus = timer.phase == .running || timer.phase == .paused
        if isQuiet {
            return .quiet(focusProgress: hasFocus ? timer.progress(at: now) : nil)
        }
        switch nudge {
        case .error, .vitals: return .error
        case .permission: return .permission
        case .takeBreak, .watchGentle: return .reminder
        case .watchFirm: return .waiting
        case .focusFinished, .agentFinished: return .finished
        case nil: break
        }
        if hasFocus { return .focus(progress: timer.progress(at: now), paused: timer.phase == .paused) }
        switch mood {
        case .error: return .error
        case .needsPermission: return .permission
        case .working: return .working
        case .needsInput: return .waiting
        default: return .idle
        }
    }
}
