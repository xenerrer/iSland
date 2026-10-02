import Foundation
import Testing
@testable import iSland

@MainActor
@Suite("FocusTimer") struct FocusTimerTests {
    let t0 = Date(timeIntervalSince1970: 5_000)
    func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    @Test func aFocusRunsDownThenAShortBreakStartsByItself() {
        let timer = FocusTimer()
        var ended: [FocusTimer.Phase] = []
        timer.onPhaseEnded = { ended.append($0) }
        timer.start(.classic, now: t0)
        #expect(timer.isActive && timer.phase == .focus)
        #expect(timer.remaining(at: minutes(1)) == 24 * 60)
        #expect(abs(timer.fraction(at: minutes(12.5)) - 0.5) < 0.001)
        timer.tick(now: minutes(24))
        #expect(ended.isEmpty && timer.phase == .focus)
        timer.tick(now: minutes(25))
        #expect(ended == [.focus] && timer.phase == .shortBreak && timer.completedFocus == 1)
        #expect(timer.remaining(at: minutes(25)) == 5 * 60)
        timer.tick(now: minutes(30)) // the break ends: wait for you
        #expect(ended == [.focus, .shortBreak] && timer.state == .waiting)
        timer.startNextFocus(now: minutes(31))
        #expect(timer.phase == .focus && timer.remaining(at: minutes(31)) == 25 * 60)
    }

    @Test func everyFourthFocusEarnsALongBreak() {
        let timer = FocusTimer()
        timer.start(.classic, now: t0)
        var now = t0
        for round in 1...4 {
            now = now.addingTimeInterval(25 * 60)
            timer.tick(now: now)
            #expect(timer.phase == (round == 4 ? .longBreak : .shortBreak))
            #expect(timer.remaining(at: now) == (round == 4 ? 15 : 5) * 60)
            now = now.addingTimeInterval(TimeInterval(timer.plan.minutes(of: timer.phase!)) * 60)
            timer.tick(now: now)
            timer.startNextFocus(now: now)
        }
    }

    @Test func pausingFreezesTheTimeAndResumingContinues() {
        let timer = FocusTimer()
        timer.start(.classic, now: t0)
        timer.pause(now: minutes(10))
        #expect(timer.isPaused && timer.remaining(at: minutes(500)) == 15 * 60)
        timer.tick(now: minutes(500)) // a paused timer never ends
        #expect(timer.isPaused)
        timer.resume(now: minutes(20))
        #expect(!timer.isPaused && timer.remaining(at: minutes(21)) == 14 * 60)
    }

    @Test func skippingMovesOnWithoutCountingTheFocus() {
        let timer = FocusTimer()
        timer.start(.classic, now: t0)
        timer.skip(now: minutes(3))
        #expect(timer.phase == .shortBreak && timer.completedFocus == 0)
        timer.skip(now: minutes(4)) // skip the break
        #expect(timer.state == .waiting)
        timer.skip(now: minutes(5)) // from waiting: straight to focus
        #expect(timer.phase == .focus)
    }

    @Test func stoppingEndsTheRoundWithoutASound() {
        let timer = FocusTimer()
        var ended = 0
        timer.onPhaseEnded = { _ in ended += 1 }
        timer.start(.long, now: t0)
        #expect(timer.remaining(at: t0) == 50 * 60)
        timer.stop()
        timer.tick(now: minutes(100))
        #expect(timer.state == .idle && !timer.isActive && ended == 0 && timer.completedFocus == 0)
    }

    @Test func aCountdownReadsAsAClock() {
        #expect(DurationFormat.clock(1_499) == "24:59")
        #expect(DurationFormat.clock(5) == "0:05")
        #expect(DurationFormat.clock(3_900) == "1:05:00")
        #expect(DurationFormat.clock(-3) == "0:00")
    }
}
