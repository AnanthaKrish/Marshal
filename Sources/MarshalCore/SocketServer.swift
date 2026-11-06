import Foundation

/// Listens on a Unix domain socket for newline-delimited `AgentEvent` JSON.
/// Never replies. Oversize and malformed lines are dropped silently.
///
/// All mutable state is confined to `queue`; that is what makes the
/// `@unchecked Sendable` sound. `handler` is called on that queue.
public final class SocketServer: @unchecked Sendable {
    public static let maxLineBytes = 8192

    private let path: String
    private let handler: @Sendable (AgentEvent) -> Void
    private let queue = DispatchQueue(label: "marshal.socket-server", qos: .utility)

    // Confined to `queue`.
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]
    /// Inode of the socket file this server bound, so `stop` never unlinks another server's socket.
    private var boundInode: ino_t?

    private struct Connection {
        let source: DispatchSourceRead
        var buffer = Data()
    }

    public init(path: String, handler: @escaping @Sendable (AgentEvent) -> Void) {
        self.path = path
        self.handler = handler
    }

    /// Unlinks a stale socket file, binds (owner-only, 0600), listens, and
    /// starts reading on a background queue. Throws `EADDRINUSE` without touching
    /// the file if another server is already accepting on `path`.
    public func start() throws {
        guard var addr = SocketClient.unixAddress(path) else { throw POSIXError(.ENAMETOOLONG) }
        if SocketClient.ping(path: path) { throw POSIXError(.EADDRINUSE) }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Self.lastError() }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let error = Self.lastError()
            close(fd)
            unlink(path)
            throw error
        }
        Self.setNonBlocking(fd)
        let inode = Self.inode(of: path)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(on: fd) }
        source.setCancelHandler { close(fd) }
        queue.sync {
            acceptSource = source
            boundInode = inode
        }
        source.resume()
    }

    /// Stops listening, closes every connection and unlinks the socket file if it
    /// is still the one this server bound. Do not call from inside `handler`.
    public func stop() {
        queue.sync {
            guard let source = acceptSource else { return }
            source.cancel()
            acceptSource = nil
            for connection in connections.values { connection.source.cancel() }
            connections.removeAll()
            if let boundInode, Self.inode(of: path) == boundInode { unlink(path) }
            boundInode = nil
        }
    }

    private func acceptPending(on listenFD: Int32) {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }   // EAGAIN: nothing more to accept
            Self.setNonBlocking(fd)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readAvailable(from: fd) }
            source.setCancelHandler { close(fd) }
            connections[fd] = Connection(source: source)
            source.resume()
        }
    }

    private func readAvailable(from fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &chunk, chunk.count)
        if count < 0 && (errno == EAGAIN || errno == EINTR) { return }
        guard count > 0, var connection = connections[fd] else {
            closeConnection(fd)   // EOF or error
            return
        }
        connection.buffer.append(contentsOf: chunk[0..<count])
        while let newline = connection.buffer.firstIndex(of: 0x0A) {
            let line = connection.buffer[connection.buffer.startIndex..<newline]
            connection.buffer = connection.buffer[(newline + 1)...]
            deliver(line)
        }
        if connection.buffer.count > Self.maxLineBytes {
            closeConnection(fd)   // a line this long is dropped along with its connection
            return
        }
        connections[fd] = connection
    }

    private func deliver(_ line: Data) {
        guard !line.isEmpty, line.count <= Self.maxLineBytes,
              let event = try? AgentEvent.decode(line: Data(line)) else { return }
        handler(event)
    }

    private func closeConnection(_ fd: Int32) {
        connections.removeValue(forKey: fd)?.source.cancel()
    }

    private static func setNonBlocking(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    private static func inode(of path: String) -> ino_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_ino
    }

    private static func lastError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
