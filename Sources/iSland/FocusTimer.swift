import Foundation

/// A pomodoro: focus, then a short break, and a longer one after every fourth focus. Breaks run by themselves; after a
/// break it waits for you to start the next focus.
@MainActor
final class FocusTimer: ObservableObject {
    enum Phase: Equatable {
        case focus, shortBreak, longBreak
        var isBreak: Bool { self != .focus }
    }

    struct Plan: Equatable {
        var focus: Int
        var shortBreak: Int
        var longBreak: Int
        /// A long break after this many focus periods.
        var rounds: Int
        static let classic = Plan(focus: 25, shortBreak: 5, longBreak: 15, rounds: 4)
        static let long = Plan(focus: 50, shortBreak: 10, longBreak: 30, rounds: 4)

        func minutes(of phase: Phase) -> Int {
            switch phase {
            case .focus: focus
            case .shortBreak: shortBreak
            case .longBreak: longBreak
            }
        }

        /// What you set up last, kept between runs.
        static var stored: Plan {
            let defaults = UserDefaults.standard
            func value(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
                let stored = defaults.object(forKey: key) as? Int ?? fallback
                return min(range.upperBound, max(range.lowerBound, stored))
            }
            return Plan(focus: value("pomodoroFocus", 25, 1...180), shortBreak: value("pomodoroShort", 5, 1...60),
                        longBreak: value("pomodoroLong", 15, 1...90), rounds: value("pomodoroRounds", 4, 2...10))
        }

        func store() {
            let defaults = UserDefaults.standard
            defaults.set(focus, forKey: "pomodoroFocus")
            defaults.set(shortBreak, forKey: "pomodoroShort")
            defaults.set(longBreak, forKey: "pomodoroLong")
            defaults.set(rounds, forKey: "pomodoroRounds")
        }
    }

    enum State: Equatable {
        case idle
        case running(phase: Phase, end: Date, total: TimeInterval)
        case paused(phase: Phase, remaining: TimeInterval, total: TimeInterval)
        /// A break ended: the next focus starts when you say so.
        case waiting
    }

    @Published private(set) var state: State = .idle
    /// Focus periods finished in this round.
    @Published private(set) var completedFocus = 0
    /// The rhythm to use. Changing it takes effect on the next start; it is remembered.
    @Published var plan = Plan.stored {
        didSet { if plan != oldValue { plan.store() } }
    }
    private var timer: Timer?
    /// Called when a phase reaches its end (not when you skip or stop).
    var onPhaseEnded: ((Phase) -> Void)?

    var isActive: Bool { state != .idle }
    var isPaused: Bool { if case .paused = state { true } else { false } }

    var phase: Phase? {
        switch state {
        case .running(let phase, _, _), .paused(let phase, _, _): phase
        case .waiting: .focus
        case .idle: nil
        }
    }

    // MARK: Controls

    func start(_ plan: Plan? = nil, now: Date = Date()) {
        if let plan { self.plan = plan }
        completedFocus = 0
        begin(.focus, now: now)
    }

    /// Stops the round altogether.
    func stop() {
        cancelTimer()
        completedFocus = 0
        state = .idle
    }

    func pause(now: Date = Date()) {
        guard case .running(let phase, let end, let total) = state else { return }
        cancelTimer()
        state = .paused(phase: phase, remaining: max(0, end.timeIntervalSince(now)), total: total)
    }

    func resume(now: Date = Date()) {
        guard case .paused(let phase, let remaining, let total) = state else { return }
        arm(phase, end: now.addingTimeInterval(remaining), total: total)
    }

    func togglePause(now: Date = Date()) {
        if isPaused { resume(now: now) } else { pause(now: now) }
    }

    /// Jumps to the next phase without counting the one you leave.
    func skip(now: Date = Date()) {
        switch state {
        case .running(let phase, _, _), .paused(let phase, _, _):
            if phase == .focus { begin(.shortBreak, now: now) } else { cancelTimer(); state = .waiting }
        case .waiting:
            begin(.focus, now: now)
        case .idle:
            break
        }
    }

    /// After a break: the next focus.
    func startNextFocus(now: Date = Date()) {
        if state == .waiting { begin(.focus, now: now) }
    }

    /// Moves on once the end of a phase has passed. Also called by the timer; a Mac that slept through the end ends it late.
    func tick(now: Date = Date()) {
        guard case .running(let phase, let end, _) = state, now >= end else { return }
        onPhaseEnded?(phase)
        if phase == .focus {
            completedFocus += 1
            begin(completedFocus % plan.rounds == 0 ? .longBreak : .shortBreak, now: now)
        } else {
            cancelTimer()
            state = .waiting
        }
    }

    // MARK: Reading

    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .running(_, let end, _): max(0, end.timeIntervalSince(now))
        case .paused(_, let remaining, _): remaining
        case .idle, .waiting: 0
        }
    }

    /// How much of the current phase has gone, 0...1.
    func fraction(at now: Date) -> Double {
        switch state {
        case .running(_, _, let total), .paused(_, _, let total): min(1, max(0, 1 - remaining(at: now) / total))
        case .idle, .waiting: 0
        }
    }

    // MARK: Private

    private func begin(_ phase: Phase, now: Date) {
        let total = TimeInterval(max(1, plan.minutes(of: phase)) * 60)
        arm(phase, end: now.addingTimeInterval(total), total: total)
    }

    private func arm(_ phase: Phase, end: Date, total: TimeInterval) {
        cancelTimer()
        state = .running(phase: phase, end: end, total: total)
        timer = Timer.scheduledTimer(withTimeInterval: max(0.01, end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }
}
