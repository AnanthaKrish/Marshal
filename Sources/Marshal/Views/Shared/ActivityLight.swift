import MarshalCore
import SwiftUI

/// Shared palette and motion rules. Each surface draws its own outline with this value.
struct ActivityLight: Equatable {
    var signal: ActivitySignal
    var color: Color

    init(signal: ActivitySignal, skin: PookieSkin, heat: Double = 0) {
        self.signal = signal
        switch signal {
        case .idle: color = skin.accent.blended(toward: RobotPalette.heat, by: heat)
        case .working: color = RobotPalette.working
        case .waiting, .permission: color = RobotPalette.attention
        case .error: color = RobotPalette.alert
        case .focus, .reminder: color = MarshalTheme.focus
        case .finished: color = RobotPalette.done
        case .quiet(let progress): color = progress == nil ? skin.accent : MarshalTheme.focus
        }
    }

    var progress: Double? {
        switch signal {
        case .focus(let progress, _), .quiet(.some(let progress)): progress
        default: nil
        }
    }

    var isQuiet: Bool {
        if case .quiet = signal { return true }
        return false
    }

    var period: Double {
        switch signal {
        case .idle: 14
        case .working: 3.2
        case .waiting: 7
        case .focus(_, let paused): paused ? 0 : 12
        case .permission, .error: 3
        case .reminder, .finished: 4
        case .quiet: 0
        }
    }

    var pulses: Bool {
        switch signal {
        case .permission, .error, .reminder: true
        default: false
        }
    }
}
