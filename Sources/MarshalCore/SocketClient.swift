import Foundation

/// Sends agent events to the Marshal app. Never blocks for long and never prints.
public enum SocketClient {
    static let timeout = timeval(tv_sec: 0, tv_usec: 200_000)

    /// Writes one event as a JSON line. Returns false if Marshal is not listening.
    @discardableResult
    public static func send(_ event: AgentEvent, to path: String = MarshalPaths.socket.path) -> Bool {
        guard let line = try? event.encodedLine() else { return false }
        guard let fd = connectedSocket(to: path) else { return false }
        defer { close(fd) }
        return line.withUnsafeBytes { buffer in
            var offset = 0
            let deadline = ProcessInfo.processInfo.systemUptime + 0.2
            while offset < buffer.count {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 && (errno == EAGAIN || errno == EINTR) {
                    var pending = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&pending, 1, 10)
                    continue
                }
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    /// True if something is accepting connections on the socket.
    public static func ping(path: String = MarshalPaths.socket.path) -> Bool {
        guard let fd = connectedSocket(to: path) else { return false }
        close(fd)
        return true
    }

    /// Nonblocking connection and writes have deadlines; a wedged receiver cannot stall hooks.
    private static func connectedSocket(to path: String) -> Int32? {
        guard var addr = unixAddress(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeout
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { close(fd); return nil }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { close(fd); return nil }
            var pending = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard poll(&pending, 1, 200) > 0,
                  getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else {
                close(fd); return nil
            }
        }
        return fd
    }

    /// A `sockaddr_un` for `path`, or nil if the path does not fit (104 bytes on macOS).
    static func unixAddress(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }
}
