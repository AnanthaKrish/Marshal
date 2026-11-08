import AppKit
import MarshalCore

/// Confirms, then adds Marshal's hooks to an agent's config file. These two
/// alerts are the only Marshal UI that takes focus from the frontmost app.
@MainActor
enum SetupPresenter {
    static let didChange = Notification.Name("MarshalAgentSetupChanged")
    static func connectUsage() {
        let alert = NSAlert()
        do {
            let changed = try UsageInstaller.install()
            alert.messageText = changed ? "Claude usage is connected" : "Claude usage is already connected"
            alert.informativeText = "Claude Code sends usage and context readings directly to Marshal after its next response. No companion app is required. If you already have a status line, it is preserved."
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Couldn't connect Claude usage"
            alert.informativeText = "Check your Claude Code settings and try again."
        }
        NSApp.activate()
        alert.runModal()
    }

    static func install(_ agent: HookAgent) {
        let file = HookInstaller.defaultFile(for: agent)

        let confirm = NSAlert()
        confirm.messageText = "Set up \(agent.displayName)?"
        confirm.informativeText = "Marshal will add hooks to \(file.path). A backup is made first."
        confirm.addButton(withTitle: "OK")
        confirm.addButton(withTitle: "Cancel")
        // The panels never activate the app, so bring it forward for the alert.
        NSApp.activate()
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let result = NSAlert()
        do {
            switch try HookInstaller.write(agent: agent, shimPath: MarshalPaths.shim.path, into: file) {
            case .added:
                result.messageText = "\(agent.displayName) is set up"
                result.informativeText = "Hooks were added to \(file.path). New sessions will report to Marshal."
            case .updated:
                result.messageText = "\(agent.displayName) hooks are updated"
                result.informativeText = "Restart your agent session to use the reliability fixes. Existing hooks were kept in place."
            case .alreadyPresent:
                result.messageText = "\(agent.displayName) was already set up"
                result.informativeText = "\(file.path) already has Marshal's hooks. Nothing was changed."
            }
        } catch {
            result.alertStyle = .warning
            result.messageText = "Couldn't set up \(agent.displayName)"
            result.informativeText = "\(file.path) was not changed: \(error)"
        }
        if result.alertStyle != .warning, agent == .codex {
            result.informativeText += " Review and trust Marshal's updated hooks at the next interactive startup."
        }
        if result.alertStyle != .warning, agent == .cursor {
            result.informativeText += " Start a local Agent chat. If it doesn't appear, check Cursor's Hooks output or restart Cursor."
        }
        NotificationCenter.default.post(name: didChange, object: nil)
        result.runModal()
    }

}
