import MarshalCore
import Testing
@testable import Marshal

@MainActor
struct WatchMonitorTests {
    @Test func youtubeKeepsCountingBesideAnotherAppOnlyWhenEnabled() async {
        let fixture = WatchMonitorFixture()
        let (watch, monitor) = fixture.makeMonitor()
        await monitor.sample()
        #expect(watch.session == nil && fixture.browserReads == 0)
        watch.configure { $0.countInBackground = true }
        await monitor.sample()
        fixture.now = 5; await monitor.sample()
        fixture.front = WatchApplication(pid: 3, bundleID: "com.example.editor")
        fixture.now = 10; await monitor.sample()
        #expect(watch.session?.elapsed == 10 && watch.isCounting)
        #expect(watch.currentRule?.name == "YouTube")
        #expect(watch.status == "Counting audio while you use another app")
        #expect(fixture.permissionRequests == 0)
    }
    @Test func backgroundAlwaysRequiresAudioAndSilentBrowsersAreNotRead() async {
        let fixture = WatchMonitorFixture()
        let (watch, monitor) = fixture.makeMonitor()
        watch.configure { $0.countInBackground = true; $0.requiresAudio = false }
        fixture.audio = .silent
        await monitor.sample()
        #expect(watch.session == nil && fixture.browserReads == 0)
        fixture.audio = .active; await monitor.sample()
        fixture.now = 5; await monitor.sample()
        #expect(watch.session?.elapsed == 5)
        fixture.audio = .silent; fixture.now = 10; await monitor.sample()
        #expect(watch.session?.elapsed == 5 && !watch.isCounting)
        let reads = fixture.browserReads
        fixture.audio = .unavailable; fixture.now = 15; await monitor.sample()
        #expect(fixture.browserReads == reads && !watch.isCounting)
    }
    @Test func foregroundCountingCanStillOptOutOfAudio() async {
        let fixture = WatchMonitorFixture()
        fixture.front = fixture.chrome; fixture.audio = .silent
        let (watch, monitor) = fixture.makeMonitor()
        watch.configure { $0.requiresAudio = false }
        await monitor.sample(); fixture.now = 5; await monitor.sample()
        #expect(watch.session?.elapsed == 5 && watch.isCounting)
    }
    @Test func disconnectedAndDeniedBrowsersCannotCountInBackground() async {
        let fixture = WatchMonitorFixture()
        let (watch, monitor) = fixture.makeMonitor()
        watch.configure { $0.countInBackground = true; $0.browsers.removeAll() }
        await monitor.sample()
        #expect(watch.session == nil && fixture.browserReads == 0)
        watch.configure { $0.browsers.insert(fixture.chrome.bundleID) }
        fixture.result = .denied
        await monitor.sample()
        #expect(watch.session == nil && !watch.isCounting)
        #expect(watch.browserStatus[fixture.chrome.bundleID] == "Browser access needed")
        #expect(fixture.permissionRequests == 0)
    }
    @Test func changingSettingsWhileBrowserReadIsPendingRejectsItsResult() async {
        let fixture = WatchMonitorFixture()
        let (watch, monitor) = fixture.makeMonitor()
        watch.configure { $0.countInBackground = true }
        fixture.onRead = { watch.configure { $0.browsers.removeAll() } }
        await monitor.sample()
        #expect(watch.session == nil && !watch.isCounting)
    }
}

@MainActor
private final class WatchMonitorFixture {
    let chrome = WatchApplication(pid: 2, bundleID: "com.google.Chrome")
    var front = WatchApplication(pid: 1, bundleID: "com.example.editor")
    var now = 0.0
    var audio = WatchAudioActivity.active
    var result = WatchBrowserResult.host("www.youtube.com")
    var browserReads = 0
    var permissionRequests = 0
    var onRead: (() -> Void)?
    func read(ask: Bool) -> WatchBrowserResult {
        browserReads += 1
        if ask { permissionRequests += 1 }
        onRead?()
        return result
    }
    func makeMonitor() -> (WatchStore, WatchMonitor) {
        let watch = WatchStore(uptime: { self.now })
        watch.configure { $0.enabled = true; $0.browsers = [chrome.bundleID] }
        let monitor = WatchMonitor(store: watch, frontmost: { self.front }, runningApps: { [self.front, self.chrome] },
                                   readBrowser: { _, _, ask in await self.read(ask: ask) },
                                   audioActivity: { _, _ in await self.audio })
        return (watch, monitor)
    }
}
