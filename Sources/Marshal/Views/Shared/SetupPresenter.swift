import AppKit
import MarshalCore

/// Confirms, then adds Marshal's hooks to an agent's config file. These two
/// alerts are the only Marshal UI that takes focus from the frontmost app.
@MainActor
enum SetupPresenter {
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
        confirm.messageText = "Set up \(name(of: agent))?"
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
                result.messageText = "\(name(of: agent)) is set up"
                result.informativeText = "Hooks were added to \(file.path). New sessions will report to Marshal."
            case .alreadyPresent:
                result.messageText = "\(name(of: agent)) was already set up"
                result.informativeText = "\(file.path) already has Marshal's hooks. Nothing was changed."
            }
        } catch {
            result.alertStyle = .warning
            result.messageText = "Couldn't set up \(name(of: agent))"
            result.informativeText = "\(file.path) was not changed: \(error)"
        }
        result.runModal()
    }

    private static func name(of agent: HookAgent) -> String {
        switch agent {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}
