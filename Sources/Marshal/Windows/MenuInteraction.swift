import AppKit

/// Menu windows belong to their widget, even though NSEvent.window is different.
/// Keep the final selection event protected until the next event-loop turn too.
@MainActor
final class MenuInteraction: NSObject {
    private let center: NotificationCenter
    private var menus: [ObjectIdentifier: UInt] = [:]
    private var generation: UInt = 0

    var isTracking: Bool { !menus.isEmpty }

    init(center: NotificationCenter = .default) {
        self.center = center
        super.init()
        center.addObserver(self, selector: #selector(began), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(ended), name: NSMenu.didEndTrackingNotification, object: nil)
    }

    deinit { center.removeObserver(self) }

    func shouldDismiss(isExpanded: Bool, clickedInside: Bool) -> Bool {
        isExpanded && !clickedInside && !isTracking
    }

    @objc private func began(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        generation &+= 1
        menus[ObjectIdentifier(menu)] = generation
    }

    @objc private func ended(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        let id = ObjectIdentifier(menu)
        let endedGeneration = menus[id]
        DispatchQueue.main.async { [weak self] in
            guard let self, self.menus[id] == endedGeneration else { return }
            self.menus.removeValue(forKey: id)
        }
    }
}
