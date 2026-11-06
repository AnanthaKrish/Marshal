import Testing
import Foundation
@testable import MarshalCore

struct ShimInstallerTests {
    @Test func scriptEmbedsPathAndFallsBackToExitZero() {
        let s = ShimInstaller.script(binaryPath: "/Apps/Marshal.app/Contents/MacOS/marshal")
        #expect(s.hasPrefix("#!/bin/sh\n"))
        #expect(s.contains("BIN=\"/Apps/Marshal.app/Contents/MacOS/marshal\""))
        #expect(s.hasSuffix("exit 0\n"))
    }

    @Test func installWritesExecutableFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shim-\(UUID())/marshal")
        try ShimInstaller.install(binaryPath: "/nonexistent/marshal", at: file)
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o755)
    }

    @Test func shimWithMissingBinaryExitsZeroSilently() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("shim-\(UUID())/marshal")
        try ShimInstaller.install(binaryPath: "/nonexistent/marshal", at: file)
        let p = Process(); p.executableURL = file; p.arguments = ["hook", "codex"]
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        #expect(out.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }
}
