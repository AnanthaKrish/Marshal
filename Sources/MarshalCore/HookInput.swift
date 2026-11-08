import Darwin
import Foundation

/// Hooks are observers: a broken pipe or oversized payload must never hold up the host.
public enum HookInput {
    public static func read(fd: Int32 = STDIN_FILENO, maxBytes: Int = 1_048_576,
                            timeout: TimeInterval = 0.5) -> Data? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, 10)
            if ready < 0 { if errno == EINTR { continue }; return nil }
            if ready == 0 { continue }
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0 { if errno == EINTR { continue }; return nil }
            guard data.count + count <= maxBytes else { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
        return nil
    }
}
