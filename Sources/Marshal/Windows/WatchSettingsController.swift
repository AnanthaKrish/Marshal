import AppKit
import MarshalCore
import SwiftUI

@MainActor
final class WatchSettingsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store: WatchStore
    init(store: WatchStore) { self.store = store }
    func show() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let host = NSHostingView(rootView: WatchSettingsView(watch: store, close: { [weak self] in self?.window?.close() }))
        let window = WatchSettingsPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                        styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Watch-time reminders"; window.isReleasedWhenClosed = false
        window.contentView = host; window.delegate = self
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.level = .floating; window.center(); self.window = window
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { store.stopPreview(); window = nil }
}

/// Editing watch settings must not disqualify the browser being watched.
/// A nonactivating panel can accept text input without making Marshal the foreground app.
private final class WatchSettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
