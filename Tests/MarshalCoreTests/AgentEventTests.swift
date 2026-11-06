import Testing
import Foundation
@testable import MarshalCore

@Test func roundTripsAllFields() throws {
    let at = AgentEvent.parseDate("2026-11-04T10:12:03.123Z")!
    let event = AgentEvent(agent: "claude-code", session: "abc", state: .needsPermission,
                           title: "FlowApp", project: "/Users/ak/FlowApp", message: "Bash", at: at)
    let decoded = try AgentEvent.decode(line: try event.encodedLine())
    #expect(decoded == event)
    #expect(decoded.v == 1)
}

@Test func decodesFractionalSecondAt() throws {
    let line = Data(#"{"v":1,"agent":"x","session":"1","state":"idle","at":"2026-11-04T10:12:03.123Z"}"#.utf8)
    let at = try #require(try AgentEvent.decode(line: line).at)
    let whole = AgentEvent.parseDate("2026-11-04T10:12:03Z")!
    #expect(abs(at.timeIntervalSince(whole) - 0.123) < 0.001)
}

@Test func unparseableAtBecomesNilNotError() throws {
    for raw in [#""yesterday""#, "42"] {
        let line = Data(#"{"v":1,"agent":"x","session":"1","state":"idle","at":\#(raw)}"#.utf8)
        let event = try AgentEvent.decode(line: line)
        #expect(event.at == nil && event.session == "1")
    }
}

@Test func encodedLineEndsWithNewlineAndUsesWireNames() throws {
    let data = try AgentEvent(agent: "codex", session: "s", state: .needsInput).encodedLine()
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.hasSuffix("\n"))
    #expect(text.contains("\"needs_input\""))
}

@Test func unknownFieldsAreIgnored() throws {
    let line = Data(#"{"v":1,"agent":"x","session":"1","state":"idle","future":42}"#.utf8)
    #expect(try AgentEvent.decode(line: line).state == .idle)
}

@Test func unknownStateFailsToDecode() {
    let line = Data(#"{"v":1,"agent":"x","session":"1","state":"dancing"}"#.utf8)
    #expect(throws: (any Error).self) { try AgentEvent.decode(line: line) }
}

@Test func missingRequiredFieldFailsToDecode() {
    let line = Data(#"{"v":1,"agent":"x","state":"idle"}"#.utf8)
    #expect(throws: (any Error).self) { try AgentEvent.decode(line: line) }
}

@Test func priorityOrderMatchesSpec() {
    let ordered: [AgentState] = [.error, .needsPermission, .working, .needsInput, .done, .idle, .ended]
    #expect(ordered.map(\.priority) == [6, 5, 4, 3, 2, 1, 0])
    #expect(AgentState.needsPermission.isHardAttention && AgentState.error.isHardAttention)
    #expect(!AgentState.needsInput.isHardAttention)
}

@Test func roundTripsAppFields() throws {
    let e = AgentEvent(agent: "codex", session: "s", state: .working, appPath: "/Applications/Codex.app", appPid: 4242)
    let d = try AgentEvent.decode(line: try e.encodedLine())
    #expect(d.appPath == "/Applications/Codex.app" && d.appPid == 4242)
}

@Test func appFieldsAbsentDecodeAsNil() throws {
    let d = try AgentEvent.decode(line: Data(#"{"v":1,"agent":"x","session":"1","state":"idle"}"#.utf8))
    #expect(d.appPath == nil && d.appPid == nil)
}

@Test func unreadableAppPidDecodesEventWithNilPid() throws {
    for raw in ["99999999999", #""abc""#, "-5000000000"] {
        let line = Data(#"{"v":1,"agent":"x","session":"1","state":"needs_permission","appPid":\#(raw)}"#.utf8)
        let e = try AgentEvent.decode(line: line)
        #expect(e.state == .needsPermission && e.appPid == nil)
    }
}
