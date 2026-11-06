import Testing
@testable import MarshalCore

struct VitalsLookTests {
    func look(_ base: VitalsConditions, mood: AgentState? = nil, celebrating: Bool = false) -> VitalsLook {
        VitalsLook.derive(conditions: VitalsConditions.implied(base), mood: mood, isCelebrating: celebrating)
    }

    @Test func noConditionsIsNone() {
        #expect(look([]) == .none)
        #expect(look([], mood: .error, celebrating: true) == .none)
    }

    @Test func sweating() {
        #expect(look(.sweating) == VitalsLook(sweat: 1))
    }

    @Test func hot() {
        #expect(look(.hot) == VitalsLook(sweat: 2, heat: 0.45))
    }

    @Test func overheated() {
        #expect(look(.overheated) == VitalsLook(sweat: 2, heat: 0.85, squint: true, pant: true))
    }

    @Test func stuffed() {
        #expect(look(.stuffed) == VitalsLook(puffCheeks: true))
    }

    @Test func dizzy() {
        #expect(look(.dizzy) == VitalsLook(spiralEyes: true, wobble: true))
    }

    @Test func sleepy() {
        #expect(look(.sleepy) == VitalsLook(sleepyLids: true, rimDim: true))
    }

    @Test func crying() {
        // crying implies sleepy
        #expect(look(.crying) == VitalsLook(sleepyLids: true, coldTears: true, rimDim: true))
    }

    @Test func errorBeatsColdTears() {
        #expect(!look(.crying, mood: .error).coldTears)
        #expect(look(.crying, mood: .working).coldTears)
        #expect(look(.crying, mood: .needsPermission).coldTears)
    }

    @Test func celebratingBeatsSpiralsAndLids() {
        let l = look([.dizzy, .sleepy], mood: .done, celebrating: true)
        #expect(!l.spiralEyes)
        #expect(!l.sleepyLids)
        // the wobble and dim rim are not eye drawings, so they stay
        #expect(l.wobble)
        #expect(l.rimDim)
    }

    @Test func overheatedSquintBeatsLids() {
        let l = look([.overheated, .sleepy])
        #expect(l.squint)
        #expect(!l.sleepyLids)
        #expect(l.rimDim)
        // without overheat, lids are back
        #expect(look([.hot, .sleepy]).sleepyLids)
    }

    @Test func sweatHeatCheeksLayerWithMoods() {
        for mood in [nil] + AgentState.allCases.map(Optional.some) {
            for celebrating in [false, true] {
                let l = look([.hot, .stuffed], mood: mood, celebrating: celebrating)
                #expect(l.sweat == 2)
                #expect(l.heat == 0.45)
                #expect(l.puffCheeks)
            }
        }
    }
}
