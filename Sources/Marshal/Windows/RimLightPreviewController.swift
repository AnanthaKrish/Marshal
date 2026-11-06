import AppKit
import SwiftUI

/// A small, explicit playground; the normal widgets retain their existing sizes.
@MainActor
final class RimLightPreviewController: NSObject, NSWindowDelegate {
    static let shared = RimLightPreviewController()
    private var window: NSWindow?
    private var preview: RimLightPreviewModel?

    func show(state: MarshalState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let preview = RimLightPreviewModel(selected: state.completionLightStyle)
        let host = NSHostingView(rootView: RimLightPreviewView(state: state, preview: preview) { [weak self] in
            self?.window?.close()
        })
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pookie rim light"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.delegate = self
        window.level = .floating
        window.center()
        self.preview = preview
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        preview?.stop()
        preview = nil
        window = nil
    }
}
