import Testing
@testable import IslandCore

@Suite("Display choice") struct DisplayChoiceTests {
    @Test func everyDisplayIsTheDefault() {
        #expect(DisplayChoice(raw: nil) == .all)
        #expect(DisplayChoice(raw: "garbage") == .all)
        #expect(DisplayChoice(raw: "id:abc") == .all)
        #expect(DisplayChoice(raw: "main") == .main)
        #expect(DisplayChoice.main.targets(available: [10, 20]) == [10])
    }

    @Test func allAndSpecificRoundTrip() {
        for choice in [DisplayChoice.main, .all, .specific(42)] { #expect(DisplayChoice(raw: choice.raw) == choice) }
        #expect(DisplayChoice.all.targets(available: [10, 20, 30]) == [10, 20, 30])
        #expect(DisplayChoice.specific(20).targets(available: [10, 20]) == [20])
    }

    @Test func anUnpluggedDisplayFallsBackToTheMainOne() {
        #expect(DisplayChoice.specific(99).targets(available: [10, 20]) == [10])
        #expect(DisplayChoice.main.targets(available: []).isEmpty)
    }
}
