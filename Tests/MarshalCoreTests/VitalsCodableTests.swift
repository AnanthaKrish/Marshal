import Testing
import Foundation
@testable import MarshalCore

struct VitalsCodableTests {
    @Test func roundTripKeepsEveryField() throws {
        let v = Vitals(cpu: 0.4, cpuRaw: 0.9, memoryUsed: 10, memoryTotal: 20, swapUsed: 5,
                       memoryPressure: .warning, thermal: .serious, batteryLevel: 42,
                       isCharging: true, topProcess: TopProcess(name: "Xcode", cpu: 2.12),
                       sampledAt: Date(timeIntervalSince1970: 1_700_000_000))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(v)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"cpuRaw\""))
        #expect(json.contains("\"thermal\":\"serious\""))
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        #expect(try dec.decode(Vitals.self, from: data) == v)
    }

    @Test func defaultsAndDesktopRoundTrip() throws {
        let v = Vitals(sampledAt: Date(timeIntervalSince1970: 0))
        #expect(v.batteryLevel == nil && v.cpu == 0 && v.thermal == .nominal && v.memoryPressure == .normal)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        #expect(try dec.decode(Vitals.self, from: enc.encode(v)) == v)
    }

    @Test func thermalEncodesByNameAndDecodesEitherForm() throws {
        for level in [ThermalLevel.nominal, .fair, .serious, .critical] {
            let data = try JSONEncoder().encode(level)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(level.name)\"")
            #expect(try JSONDecoder().decode(ThermalLevel.self, from: data) == level)
            // older output wrote the Int raw value
            #expect(try JSONDecoder().decode(ThermalLevel.self, from: Data("\(level.rawValue)".utf8)) == level)
        }
        #expect(ThermalLevel.serious > .fair)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ThermalLevel.self, from: Data("\"warm\"".utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ThermalLevel.self, from: Data("7".utf8)) }
    }
}
