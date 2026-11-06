import Foundation
import Testing
@testable import MarshalCore

struct NotchVitalsLabelTests {
    private let vitals = Vitals(cpu: 0.93, memoryUsed: 34 << 30, memoryTotal: 36 << 30,
                                batteryLevel: 8, topProcess: TopProcess(name: "Xcode", cpu: 2.12))

    private func label(_ c: VitalsConditions, _ v: Vitals? = nil, demo: Bool = false) -> (text: String, isAlert: Bool)? {
        NotchVitalsLabel.label(conditions: .implied(c), vitals: v ?? vitals, isDemo: demo)
    }

    @Test func nilWithoutACondition() {
        #expect(label([]) == nil)
        #expect(label(.sweating) == nil)
    }

    @Test func texts() {
        #expect(label(.hot)?.text == "Hot: Xcode")
        #expect(label(.overheated)?.text == "Hot: Xcode")
        #expect(label(.stuffed)?.text == "Mem 34/36")
        #expect(label(.dizzy)?.text == "Mem 34/36")
        #expect(label(.sleepy)?.text == "Battery 8%")
        #expect(label(.crying)?.text == "Battery 8%")
    }

    @Test func memoryTextIsShortEnoughForTheStrip() {
        let big = Vitals(memoryUsed: UInt64(120.4 * 1_073_741_824), memoryTotal: 128 << 30)
        #expect(label(.stuffed, big)?.text == "Mem 120/128")
        #expect(label(.dizzy)?.text == "Mem 34/36")
    }

    @Test func fallbacksWithoutNumbers() {
        let bare = Vitals(cpu: 0.9)
        #expect(label(.hot, bare)?.text == "Hot 90%")
        #expect(label(.sleepy, bare)?.text == "Battery low")
    }

    @Test func demoTexts() {
        #expect(label(.overheated, demo: true)?.text == "Hot: demo")
        #expect(label(.hot, demo: true)?.text == "Hot: demo")
        #expect(label(.stuffed, demo: true)?.text == "Mem: demo")
        #expect(label(.dizzy, demo: true)?.text == "Mem: demo")
        #expect(label(.sleepy, demo: true)?.text == "Battery: demo")
        #expect(label(.crying, demo: true)?.text == "Battery: demo")
    }

    @Test func alertColour() {
        #expect(label(.overheated)?.isAlert == true)
        #expect(label(.dizzy)?.isAlert == true)
        #expect(label(.crying)?.isAlert == true)
        #expect(label(.hot)?.isAlert == false)
        #expect(label(.stuffed)?.isAlert == false)
        #expect(label(.sleepy)?.isAlert == false)
    }

    @Test func priority() {
        // overheated > dizzy > crying > hot > stuffed > sleepy
        #expect(label([.overheated, .dizzy, .crying])?.text == "Hot: Xcode")
        #expect(label([.dizzy, .crying, .hot])?.text == "Mem 34/36")
        #expect(label([.dizzy, .crying, .hot])?.isAlert == true)
        #expect(label([.crying, .hot, .stuffed])?.text == "Battery 8%")
        #expect(label([.crying, .hot, .stuffed])?.isAlert == true)
        #expect(label([.hot, .stuffed, .sleepy])?.text == "Hot: Xcode")
        #expect(label([.stuffed, .sleepy])?.text == "Mem 34/36")
        #expect(label([.stuffed, .sleepy])?.isAlert == false)
    }

    @Test func headline() {
        #expect(VitalsConditions.implied(.hot).headline == "hot")
        #expect(VitalsConditions.implied(.overheated).headline == "overheated")
        #expect(VitalsConditions.implied(.crying).headline == "crying")
        #expect(VitalsConditions.sweating.headline == "sweating")
        #expect(VitalsConditions().headline == nil)
    }

    @Test func vitalsLineUsesBinaryGigabytes() {
        let v = Vitals(cpu: 0.37, memoryUsed: UInt64(18.2 * 1_073_741_824), memoryTotal: 36 << 30, batteryLevel: 82)
        #expect(VitalsFormat.line(v) == "CPU 37% · Mem 18.2 / 36 GB · Battery 82%")
        // a 36 GB Mac reports 38.65e9 bytes; it must still read 36
        #expect(VitalsFormat.memory(used: 0, total: 38_654_705_664) == "Mem 0.0 / 36 GB")
        var charging = v
        charging.isCharging = true
        #expect(VitalsFormat.battery(charging) == "Battery 82% charging")
        charging.batteryLevel = nil
        #expect(VitalsFormat.line(charging) == "CPU 37% · Mem 18.2 / 36 GB")
    }

    @Test func cardNumbersCarryNoChargingWordOrSuffix() {
        var v = Vitals(cpu: 0.37, memoryUsed: UInt64(120.4 * 1_073_741_824), memoryTotal: 128 << 30,
                       batteryLevel: 82, isCharging: true)
        #expect(VitalsFormat.numbers(v) == "CPU 37% · Mem 120.4 / 128 GB · Battery 82%")
        v.batteryLevel = nil
        #expect(VitalsFormat.numbers(v) == "CPU 37% · Mem 120.4 / 128 GB")
    }
}
