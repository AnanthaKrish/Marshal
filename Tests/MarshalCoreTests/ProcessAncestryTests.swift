import Darwin
import Testing
@testable import MarshalCore

struct ProcessAncestryTests {
    @Test func bundlePathParsing() {
        #expect(ProcessAncestry.bundlePath(fromExecutablePath: "/Applications/Codex.app/Contents/MacOS/Codex") == "/Applications/Codex.app")
        #expect(ProcessAncestry.bundlePath(fromExecutablePath: "/Applications/Claude.app/Contents/Helpers/disclaimer") == nil)
        #expect(ProcessAncestry.bundlePath(fromExecutablePath: "/bin/zsh") == nil)
        #expect(ProcessAncestry.bundlePath(fromExecutablePath: "/Users/x/Library/Application Support/Claude/claude-code/2.1.317/abc/claude.app/Contents/MacOS/claude") == "/Users/x/Library/Application Support/Claude/claude-code/2.1.317/abc/claude.app")
    }

    @Test func nestedBundleReturnsInnermost() {
        #expect(ProcessAncestry.bundlePath(fromExecutablePath: "/A.app/Contents/MacOS/x.app/Contents/MacOS/y") == "/A.app/Contents/MacOS/x.app")
    }

    @Test func walkTerminatesAndReturnsNilOrAppPath() {
        let app = ProcessAncestry.owningApp()
        if let app { #expect(app.bundlePath.hasSuffix(".app")); #expect(app.pid > 1) }
    }

    @Test func parentOfInitIsNilOrZeroAndPathOfCurrentProcessExists() {
        #expect(ProcessAncestry.executablePath(of: getpid()) != nil)
        #expect((ProcessAncestry.parentPid(of: 1) ?? 0) <= 1)
    }

    @Test func walkSkipsTheStartingProcess() {
        let parents: [Int32: Int32] = [10: 9, 9: 1]
        let paths: [Int32: String] = [10: "/Apps/Marshal.app/Contents/MacOS/marshal-cli", 9: "/usr/bin/tmux"]
        let app = ProcessAncestry.owningApp(startingAt: 10, parent: { parents[$0] }, path: { paths[$0] })
        #expect(app == nil)
    }

    @Test func walkPicksHighestApp() {
        let parents: [Int32: Int32] = [20: 19, 19: 18, 18: 17, 17: 16, 16: 1]
        let paths: [Int32: String] = [
            20: "/Apps/Marshal.app/Contents/MacOS/marshal-cli",
            19: "/bin/zsh",
            18: "/Users/x/Library/Application Support/Claude/claude-code/abc/claude.app/Contents/MacOS/claude",
            17: "/Applications/Claude.app/Contents/Helpers/x",
            16: "/Applications/Claude.app/Contents/MacOS/Claude",
        ]
        let app = ProcessAncestry.owningApp(startingAt: 20, parent: { parents[$0] }, path: { paths[$0] })
        #expect(app == ProcessAncestry.OwningApp(bundlePath: "/Applications/Claude.app", pid: 16))
    }

    @Test func walkStopsAtThirtyTwoHops() {
        var pathCalls = 0
        let app = ProcessAncestry.owningApp(startingAt: 10, parent: { $0 + 1 }, path: { _ in
            pathCalls += 1
            return "/usr/bin/tool"
        })
        #expect(app == nil)
        #expect(pathCalls <= 32)
    }
}
