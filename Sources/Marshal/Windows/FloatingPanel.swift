import AppKit
import SwiftUI

/// A borderless, transparent, non-activating panel. Clicking it never steals
/// focus from the app the user is working in.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect, level: NSWindow.Level) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// NSHostingView that accepts the first click even though its window is not key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSRect {
    /// Shift the rect so it lies fully inside `bounds` (if it fits).
    func clamped(to bounds: NSRect) -> NSRect {
        var rect = self
        if rect.maxX > bounds.maxX { rect.origin.x = bounds.maxX - rect.width }
        if rect.minX < bounds.minX { rect.origin.x = bounds.minX }
        if rect.maxY > bounds.maxY { rect.origin.y = bounds.maxY - rect.height }
        if rect.minY < bounds.minY { rect.origin.y = bounds.minY }
        return rect
    }
}
