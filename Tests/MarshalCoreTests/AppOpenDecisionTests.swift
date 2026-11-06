import Testing
@testable import MarshalCore

struct AppOpenDecisionTests {
    @Test func openerUsesBundleURLWhenPidIsGone() {
        #expect(AppOpenPolicy.decide(appPath: "/A.app", appPid: 999_999, bundleExists: { _ in true }) == .open(bundlePath: "/A.app"))
    }

    @Test func cardHasNoOpenWhenBundleMissing() {
        #expect(AppOpenPolicy.decide(appPath: "/Gone.app", appPid: 5, bundleExists: { _ in false }) == .none)
        #expect(AppOpenPolicy.decide(appPath: nil, appPid: nil, bundleExists: { _ in true }) == .none)
    }
}
