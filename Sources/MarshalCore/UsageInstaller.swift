import Foundation

/// Connects Claude Code directly to Marshal, including on a fresh installation.
/// If a status line already exists, preserve it as optional compatibility.
public enum UsageInstaller {
    public static var savedFile: URL { MarshalPaths.directory.appendingPathComponent("claude-statusline-original.json") }
    public enum InstallError: Error { case invalidSettings, missingOriginal, notOurWrapper }

    public static func install(settings: URL = HookInstaller.defaultFile(for: .claudeCode),
                               saved: URL = savedFile, shim: String = MarshalPaths.shim.path) throws -> Bool {
        let file = settings.resolvingSymlinksInPath()
        var root = try read(file)
        let command = shellQuote(shim) + " usage claude"
        if (root["statusLine"] as? [String: Any])?["command"] as? String == command {
            guard FileManager.default.fileExists(atPath: saved.path) else { throw InstallError.missingOriginal }
            return false
        }
        let original = root["statusLine"] ?? NSNull()
        guard original is NSNull || original is [String: Any] else { throw InstallError.invalidSettings }
        var status = original as? [String: Any] ?? [:]
        if let type = status["type"] as? String, type != "command" { throw InstallError.invalidSettings }
        try backup(file)
        try FileManager.default.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try write(["v": 1, "original": original, "wrapper": command], to: saved)
        status["type"] = "command"; status["command"] = command
        root["statusLine"] = status
        try write(root, to: file)
        return true
    }

    public static func remove(settings: URL = HookInstaller.defaultFile(for: .claudeCode),
                              saved: URL = savedFile) throws -> Bool {
        guard FileManager.default.fileExists(atPath: saved.path) else { return false }
        let record = try read(saved)
        let file = settings.resolvingSymlinksInPath()
        var root = try read(file)
        guard let wrapper = record["wrapper"] as? String,
              (root["statusLine"] as? [String: Any])?["command"] as? String == wrapper else {
            throw InstallError.notOurWrapper
        }
        try backup(file)
        if record["original"] is NSNull { root.removeValue(forKey: "statusLine") }
        else { root["statusLine"] = record["original"] }
        try write(root, to: file)
        try FileManager.default.removeItem(at: saved)
        return true
    }

    public static func originalCommand(saved: URL = savedFile) -> String? {
        guard let root = try? read(saved),
              let original = root["original"] as? [String: Any] else { return nil }
        return original["command"] as? String
    }

    public static func shellQuote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func read(_ file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] else {
            throw InstallError.invalidSettings
        }
        return root
    }
    private static func write(_ root: [String: Any], to file: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private static func backup(_ file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let target = file.appendingPathExtension("marshal-usage-backup-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: file, to: target)
    }
}

public enum StatusLineForwarder {
    /// Bounded forwarding prevents a broken old status line from hanging Claude.
    /// No shell interpolation: the previously configured command is passed verbatim.
    public static func run(command: String, input: Data, output: FileHandle = .standardOutput, timeout: TimeInterval = 5) {
        signal(SIGPIPE, SIG_IGN)
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardInput = pipe
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        guard (try? process.run()) != nil else { return }
        let fd = pipe.fileHandleForWriting.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        input.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count && process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                if poll(&descriptor, 1, 50) <= 0 { continue }
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count }
                else if errno != EAGAIN && errno != EINTR { break }
            }
        }
        try? pipe.fileHandleForWriting.close()
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            usleep(50_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
