import Foundation

/// Where Marshal keeps its socket and the hook shim, all under `~/.marshal`.
public enum MarshalPaths {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".marshal", isDirectory: true)
    }

    public static var socket: URL {
        directory.appendingPathComponent("marshal.sock")
    }

    public static var shimDirectory: URL {
        directory.appendingPathComponent("bin", isDirectory: true)
    }

    public static var shim: URL {
        shimDirectory.appendingPathComponent("marshal")
    }

    /// Creates `~/.marshal` (owner-only, 0700) and `~/.marshal/bin`.
    public static func ensureDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try fm.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
    }
}
