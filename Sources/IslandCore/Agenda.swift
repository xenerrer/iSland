import Foundation

/// An event from the user's calendars, stripped down to what the island shows.
public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isDeclined: Bool
    public var calendarName: String
    /// sRGB red, green, blue in 0...1.
    public var color: [Double]
    public var joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, isDeclined: Bool = false,
                calendarName: String = "", color: [Double] = [0.35, 0.6, 1], joinURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.calendarName = calendarName
        self.color = color
        self.joinURL = joinURL
    }
}

public enum Agenda {
    /// What happens on a day: all-day events first, then by start time. Declined events are left out. An event that spans
    /// midnight shows on both days.
    public static func events(on day: Date, in events: [CalendarEvent], calendar: Calendar = .current) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events
            .filter { !$0.isDeclined && $0.start < end && ($0.end > start || $0.start >= start) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// What is worth showing now: events that have not ended, are not all-day and were not declined.
    /// The one in progress comes first, then the rest by start time.
    public static func upcoming(_ events: [CalendarEvent], now: Date, limit: Int = 2) -> [CalendarEvent] {
        let candidates = events.filter { !$0.isAllDay && !$0.isDeclined && $0.end > now }
        let sorted = candidates.sorted { a, b in
            let aOngoing = a.start <= now
            let bOngoing = b.start <= now
            if aOngoing != bOngoing { return aOngoing }
            return aOngoing ? a.end < b.end : a.start < b.start
        }
        return Array(sorted.prefix(limit))
    }

    public enum Timing: Equatable {
        case ongoing(minutesLeft: Int)
        case startsIn(minutes: Int)
        case today(at: Date)
        case tomorrow(at: Date)
        case later(at: Date)
    }

    /// How close to the start the join button turns green: before that it stays quiet, so it does not compete for attention.
    public static let joinLead: TimeInterval = 5 * 60

    /// True from `joinLead` before the start until the event ends.
    public static func joinIsUrgent(_ event: CalendarEvent, now: Date) -> Bool {
        !event.isAllDay && now >= event.start.addingTimeInterval(-joinLead) && now < event.end
    }

    public static func timing(of event: CalendarEvent, now: Date, calendar: Calendar = .current) -> Timing {
        if event.start <= now {
            return .ongoing(minutesLeft: max(1, Int((event.end.timeIntervalSince(now) / 60).rounded(.up))))
        }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return .startsIn(minutes: max(1, minutes)) }
        if calendar.isDate(event.start, inSameDayAs: now) { return .today(at: event.start) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(event.start, inSameDayAs: tomorrow) {
            return .tomorrow(at: event.start)
        }
        return .later(at: event.start)
    }
}

/// Finds the video-call link hidden in an event's location, URL or notes.
public enum JoinLink {
    private static let patterns = [
        #"https://meet\.google\.com/[A-Za-z0-9\-]+(?:\?[^\s"'<>]*)?"#,
        #"https://(?:[A-Za-z0-9\-]+\.)*zoom\.us/j/[^\s"'<>]+"#, // zoom.us itself or a subdomain, never "evilzoom.us"
        #"https://teams\.microsoft\.com/l/meetup-join/[^\s"'<>]+"#,
        #"https://teams\.live\.com/meet/[^\s"'<>]+"#,
    ]

    public static func find(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range, in: text) else { continue }
                let cleaned = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)>]"))
                if let url = URL(string: cleaned) { return url }
            }
        }
        return nil
    }
}
