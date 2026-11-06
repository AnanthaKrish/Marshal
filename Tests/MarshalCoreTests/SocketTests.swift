import Foundation
import Testing
@testable import MarshalCore

private func tempSocketPath() -> String {
    "/tmp/marshal-test-\(UUID().uuidString.prefix(8)).sock"   // short on purpose
}

private actor EventBox {
    private(set) var events: [AgentEvent] = []
    func append(_ event: AgentEvent) { events.append(event) }
}

/// Starts a server that records events, and returns a waiter that polls until
/// `count` events arrived or `timeout` elapsed, then returns what it has.
private func collect(_ path: String, count: Int, timeout: TimeInterval = 2) async throws -> (SocketServer, () async -> [AgentEvent]) {
    let box = EventBox()
    // The stream keeps delivery order; one consumer task moves events into the actor.
    let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    Task { for await event in stream { await box.append(event) } }
    let server = SocketServer(path: path) { event in continuation.yield(event) }
    try server.start()
    let waiter: () async -> [AgentEvent] = {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await box.events.count >= count { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        continuation.finish()
        return await box.events
    }
    return (server, waiter)
}

/// Writes raw bytes to the socket with the same POSIX calls as SocketClient.
private func rawSend(_ data: Data, to path: String) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        let bytes = Array(path.utf8.prefix(raw.count - 1))
        raw.copyBytes(from: bytes)
    }
    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { return }
    data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
            if n <= 0 { return }
            offset += n
        }
    }
}

struct SocketTests {
    @Test func roundTripOneEvent() async throws {
        let path = tempSocketPath()
        let (server, received) = try await collect(path, count: 1); defer { server.stop() }
        #expect(SocketClient.send(AgentEvent(agent: "codex", session: "s", state: .working), to: path))
        #expect(await received().first?.session == "s")
    }

    @Test func sendReturnsFalseAndPingFalseWithoutServer() {
        let path = tempSocketPath()
        #expect(SocketClient.send(AgentEvent(agent: "x", session: "s", state: .idle), to: path) == false)
        #expect(SocketClient.ping(path: path) == false)
    }

    @Test func startsWhenStaleSocketFileExists() throws {
        let path = tempSocketPath()
        FileManager.default.createFile(atPath: path, contents: Data())
        let server = SocketServer(path: path) { _ in }
        try server.start(); defer { server.stop() }
        #expect(SocketClient.ping(path: path))
    }

    @Test func twoLinesInOneConnectionDeliverTwoEvents() async throws {
        let path = tempSocketPath()
        let (server, received) = try await collect(path, count: 2); defer { server.stop() }
        let a = try AgentEvent(agent: "x", session: "1", state: .working).encodedLine()
        let b = try AgentEvent(agent: "x", session: "2", state: .done).encodedLine()
        rawSend(a + b, to: path)
        #expect(await received().map(\.session) == ["1", "2"])
    }

    @Test func oversizeLineIsDropped() async throws {
        let path = tempSocketPath()
        let (server, received) = try await collect(path, count: 1, timeout: 1); defer { server.stop() }
        let big = Data(repeating: UInt8(ascii: "a"), count: 9000) + Data("\n".utf8)
        rawSend(big, to: path)
        #expect(await received().isEmpty)
    }

    @Test func malformedLineIsDroppedAndServerSurvives() async throws {
        let path = tempSocketPath()
        let (server, received) = try await collect(path, count: 1); defer { server.stop() }
        rawSend(Data("{not json}\n".utf8), to: path)
        #expect(SocketClient.send(AgentEvent(agent: "x", session: "ok", state: .idle), to: path))
        #expect(await received().map(\.session) == ["ok"])
    }

    @Test func socketFileIsOwnerOnly() throws {
        let path = tempSocketPath()
        let server = SocketServer(path: path) { _ in }; try server.start(); defer { server.stop() }
        let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func secondServerOnSamePathThrowsAndFirstKeepsReceiving() async throws {
        let path = tempSocketPath()
        let (a, received) = try await collect(path, count: 1); defer { a.stop() }
        let b = SocketServer(path: path) { _ in }
        #expect(throws: POSIXError(.EADDRINUSE)) { try b.start() }
        #expect(SocketClient.send(AgentEvent(agent: "x", session: "still-a", state: .working), to: path))
        #expect(await received().map(\.session) == ["still-a"])
        b.stop()
        #expect(SocketClient.ping(path: path))
    }

    @Test func stopLeavesASocketItDidNotBind() throws {
        let path = tempSocketPath()
        let a = SocketServer(path: path) { _ in }; try a.start()
        unlink(path)   // A's file is gone; a newer server takes the path
        let b = SocketServer(path: path) { _ in }; try b.start(); defer { b.stop() }
        a.stop()
        #expect(SocketClient.ping(path: path))
    }
}
