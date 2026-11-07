import Testing
@testable import IslandCore

@Suite("Finish alerts") struct AlertPolicyTests {
    @Test func onlyLongTurnsInOtherChatsAnnounce() {
        #expect(AlertPolicy.shouldAnnounceFinish(turnSeconds: 20, userIsLooking: false))
        #expect(AlertPolicy.shouldAnnounceFinish(turnSeconds: 600, userIsLooking: false))
        #expect(!AlertPolicy.shouldAnnounceFinish(turnSeconds: 19, userIsLooking: false))
        #expect(!AlertPolicy.shouldAnnounceFinish(turnSeconds: nil, userIsLooking: false))
        #expect(!AlertPolicy.shouldAnnounceFinish(turnSeconds: 300, userIsLooking: true))
    }
}
