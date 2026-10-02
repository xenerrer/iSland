import Foundation
import Testing
@testable import IslandCore

@Suite("Agenda") struct AgendaTests {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Thursday 2026-10-01, 10:00 UTC.
    let now = AgendaTests.utc.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10))!

    func event(_ id: String, startsIn: TimeInterval, lasts: TimeInterval = 1_800,
               allDay: Bool = false, declined: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: now.addingTimeInterval(startsIn), end: now.addingTimeInterval(startsIn + lasts),
                      isAllDay: allDay, isDeclined: declined)
    }

    // MARK: Which events

    @Test func finishedAllDayAndDeclinedEventsAreLeftOut() {
        let events = [
            event("finished", startsIn: -7_200, lasts: 3_600),
            event("allday", startsIn: -3_600, lasts: 86_400, allDay: true),
            event("declined", startsIn: 600, declined: true),
            event("good", startsIn: 900),
        ]
        #expect(Agenda.upcoming(events, now: now).map(\.id) == ["good"])
    }

    @Test func theOneInProgressComesFirstThenByStart() {
        let events = [
            event("later", startsIn: 7_200),
            event("soon", startsIn: 600),
            event("now", startsIn: -600, lasts: 3_600),
        ]
        #expect(Agenda.upcoming(events, now: now, limit: 3).map(\.id) == ["now", "soon", "later"])
        #expect(Agenda.upcoming(events, now: now, limit: 2).map(\.id) == ["now", "soon"])
    }

    @Test func anEventEndingExactlyNowIsGone() {
        #expect(Agenda.upcoming([event("over", startsIn: -1_800, lasts: 1_800)], now: now).isEmpty)
    }

    // MARK: When

    @Test func timingReadsAtAGlance() {
        let calendar = Self.utc
        #expect(Agenda.timing(of: event("a", startsIn: -600, lasts: 3_600), now: now, calendar: calendar) == .ongoing(minutesLeft: 50))
        #expect(Agenda.timing(of: event("b", startsIn: 25 * 60), now: now, calendar: calendar) == .startsIn(minutes: 25))
        #expect(Agenda.timing(of: event("c", startsIn: 1), now: now, calendar: calendar) == .startsIn(minutes: 1))
        let later = event("d", startsIn: 4 * 3_600)
        #expect(Agenda.timing(of: later, now: now, calendar: calendar) == .today(at: later.start))
        let tomorrow = event("e", startsIn: 24 * 3_600)
        #expect(Agenda.timing(of: tomorrow, now: now, calendar: calendar) == .tomorrow(at: tomorrow.start))
        let nextWeek = event("f", startsIn: 5 * 24 * 3_600)
        #expect(Agenda.timing(of: nextWeek, now: now, calendar: calendar) == .later(at: nextWeek.start))
    }

    // MARK: Join links

    @Test func findsTheCallLinkWhereverItHides() {
        #expect(JoinLink.find(in: [nil, "https://meet.google.com/abc-defg-hij"])?.absoluteString == "https://meet.google.com/abc-defg-hij")
        let notes = "Join: <a href=\"https://us02web.zoom.us/j/123456789?pwd=abc\">link</a>. See you!"
        #expect(JoinLink.find(in: [notes])?.absoluteString == "https://us02web.zoom.us/j/123456789?pwd=abc")
        #expect(JoinLink.find(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y."])?.host == "teams.microsoft.com")
    }

    @Test func nothingToJoinMeansNil() {
        #expect(JoinLink.find(in: [nil, "", "Sala 3, 2º andar", "https://example.com/meet"]) == nil)
    }

    @Test func theFirstTextWithALinkWins() {
        let url = JoinLink.find(in: ["no link here", "https://meet.google.com/aaa-bbbb-ccc", "https://meet.google.com/zzz-yyyy-xxx"])
        #expect(url?.absoluteString == "https://meet.google.com/aaa-bbbb-ccc")
    }
}

@Suite("Agenda by day and month") struct AgendaDayTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        c.firstWeekday = 1 // Sunday
        return c
    }
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false, declined: Bool = false, color: [Double] = [1, 0, 0]) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start, end: end, isAllDay: allDay, isDeclined: declined, color: color)
    }

    @Test func aDayListsItsEventsInOrderWithAllDayFirst() {
        let events = [
            event("late", date(2026, 10, 2, 16), date(2026, 10, 2, 17)),
            event("allday", date(2026, 10, 2), date(2026, 10, 2, 23, 59), allDay: true),
            event("early", date(2026, 10, 2, 9), date(2026, 10, 2, 10)),
            event("tomorrow", date(2026, 10, 3, 9), date(2026, 10, 3, 10)),
            event("declined", date(2026, 10, 2, 11), date(2026, 10, 2, 12), declined: true),
        ]
        #expect(Agenda.events(on: date(2026, 10, 2, 13), in: events, calendar: calendar).map(\.id) == ["allday", "early", "late"])
    }

    @Test func anEventAcrossMidnightShowsOnBothDays() {
        let night = event("night", date(2026, 10, 2, 22), date(2026, 10, 3, 2))
        #expect(Agenda.events(on: date(2026, 10, 2), in: [night], calendar: calendar).count == 1)
        #expect(Agenda.events(on: date(2026, 10, 3), in: [night], calendar: calendar).count == 1)
        #expect(Agenda.events(on: date(2026, 10, 4), in: [night], calendar: calendar).isEmpty)
        // one that ends exactly at midnight does not leak into the next day
        let ends = event("ends", date(2026, 10, 2, 20), date(2026, 10, 3))
        #expect(Agenda.events(on: date(2026, 10, 3), in: [ends], calendar: calendar).isEmpty)
    }
}
