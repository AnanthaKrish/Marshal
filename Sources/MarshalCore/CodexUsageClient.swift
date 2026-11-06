import Foundation

public enum CodexUsageError: Error, Sendable {
    case notInstalled, timedOut, unavailable, signIn, malformed
    public var message: String {
        switch self {
        case .notInstalled: "Codex CLI not found"
        case .timedOut: "Codex didn't respond · try refresh"
        case .signIn: "Sign in to Codex to see limits"
        case .unavailable: "Codex limits unavailable · try refresh"
        case .malformed: "Usage format unavailable"
        }
    }
}

public enum CodexUsageClient {
    public static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let paths = [home.appendingPathComponent(".local/bin/codex").path,
                     "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                     "/Applications/Codex.app/Contents/Resources/codex"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// No turns or chats are started. Codex manages its own existing authentication.
    public static func read(executable: URL? = executable(), timeout: TimeInterval = 10) throws -> UsageSample {
        guard let executable else { throw CodexUsageError.notInstalled }
        let process = Process()
        let input = Pipe(), output = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let outputFD = output.fileHandleForReading.fileDescriptor
        _ = fcntl(outputFD, F_SETFL, fcntl(outputFD, F_GETFL) | O_NONBLOCK)
        do { try process.run() } catch { throw CodexUsageError.unavailable }
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let end = ProcessInfo.processInfo.systemUptime + 0.3
            while process.isRunning && ProcessInfo.processInfo.systemUptime < end { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "marshal_usage", "title": "Marshal", "version": "0.1"]]])
        var buffer = Data()
        var received = 0
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline && !Task.isCancelled {
            var fd = pollfd(fd: outputFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&fd, 1, 100)
            guard ready >= 0 else { throw CodexUsageError.unavailable }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(outputFD, &bytes, bytes.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count > 0 else { throw CodexUsageError.unavailable }
            received += count
            guard received <= 2_097_152 else { throw CodexUsageError.malformed }
            buffer.append(contentsOf: bytes.prefix(count))
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let id = object["id"] as? Int, id == 1 || id == 2 else { continue }
                if let error = object["error"] as? [String: Any] {
                    let message = (error["message"] as? String ?? "").lowercased()
                    throw message.contains("auth") || message.contains("sign in") || message.contains("login")
                        ? CodexUsageError.signIn : CodexUsageError.unavailable
                }
                if id == 1 {
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else {
                    guard let result = object["result"],
                          let data = try? JSONSerialization.data(withJSONObject: result),
                          let sample = UsageParsing.codexLimits(data) else { throw CodexUsageError.malformed }
                    return sample
                }
            }
        }
        throw CodexUsageError.timedOut
    }
}
