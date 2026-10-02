import Testing
@testable import IslandCore

@Suite("Display choice") struct DisplayChoiceTests {
    @Test func theMainDisplayIsTheDefault() {
        #expect(DisplayChoice(raw: nil) == .main)
        #expect(DisplayChoice(raw: "garbage") == .main)
        #expect(DisplayChoice(raw: "id:abc") == .main)
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
