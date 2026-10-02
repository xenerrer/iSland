import AppKit
import EventKit
import IslandCore

/// Your agenda, read from the calendars macOS already syncs: iCloud, Exchange and Google (add the Google
/// account in System Settings > Internet Accounts and turn Calendars on).
@MainActor
final class CalendarManager: ObservableObject {
    enum Access: Equatable { case unavailable, notDetermined, denied, authorized }

    @Published private(set) var access: Access = .unavailable
    @Published private(set) var events: [CalendarEvent] = []
    /// Names of the accounts that provide calendars ("iCloud", "Google"...).
    @Published private(set) var sourceNames: [String] = []
    /// Ticks every 30 s so the list drops finished events and "in 25 min" stays true.
    @Published private(set) var now = Date()
    private var store: EKEventStore?
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var lastFetch = Date.distantPast
    private var loadedDay = Date.distantPast

    /// A command-line build runs under the app that launched it (Terminal, Claude...), so macOS would ask for that
    /// app's calendar access, or crash for want of a usage description. Only a real .app asks for its own.
    static var canAskForAccess: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// The card is worth showing: something today has not ended yet, or there is something the user can do about access.
    var showsCard: Bool {
        switch access {
        case .authorized: !Agenda.upcoming(events, now: now, limit: 1).isEmpty
        case .notDetermined, .denied: true
        case .unavailable: false
        }
    }

    /// Everything today, all-day events first, then by time: the card scrolls through it.
    var todayEvents: [CalendarEvent] { Agenda.events(on: now, in: events) }

    var hasGoogleAccount: Bool { sourceNames.contains { $0.localizedCaseInsensitiveContains("google") } }

    // MARK: Lifecycle

    func start() {
        guard Self.canAskForAccess, store == nil else { return }
        let store = EKEventStore()
        self.store = store
        refreshAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        timer = nil
        observer = nil
        store = nil
    }

    /// Asks macOS for permission. Only ever called from a click, never on its own.
    func requestAccess() {
        guard let store else { return }
        Task { @MainActor in
            _ = try? await store.requestFullAccessToEvents()
            refreshAccess()
        }
    }

    func openPrivacySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    }

    func openInternetAccounts() {
        open("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")
    }

    /// For demos and snapshots.
    func preview(_ events: [CalendarEvent], sources: [String]) {
        access = .authorized
        self.events = events
        sourceNames = sources
        now = Date()
    }

    // MARK: Reading

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    private func tick() {
        now = Date()
        // The user may have flipped the switch in System Settings while the app was running.
        if access != .authorized { refreshAccess() }
        else if now.timeIntervalSince(lastFetch) > 300 || !Calendar.current.isDate(now, inSameDayAs: loadedDay) { reload() } // new day: new list
    }

    private func refreshAccess() {
        let current: Access
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: current = .authorized
        case .notDetermined: current = .notDetermined
        default: current = .denied // denied, restricted, or write-only: not enough to read events
        }
        if current != access {
            access = current
            NSLog("iSland: calendar access is %@", String(describing: current))
        }
        if access == .authorized { reload() }
    }

    /// Today's events. A few dozen at most, so reading on the main thread is fine.
    private func reload() {
        guard access == .authorized, let store else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).compactMap(Self.map)
        var names: [String] = []
        for source in store.sources where !names.contains(source.title) { names.append(source.title) }
        sourceNames = names
        lastFetch = Date()
        loadedDay = start
        now = Date()
    }

    private static func map(_ event: EKEvent) -> CalendarEvent? {
        guard let start = event.startDate, let end = event.endDate, event.status != .canceled else { return nil }
        let declined = event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
        var rgb: [Double] = [0.35, 0.6, 1]
        if let cg = event.calendar?.cgColor, let color = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
            rgb = [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)]
        }
        return CalendarEvent(
            id: (event.eventIdentifier ?? UUID().uuidString) + "@\(Int(start.timeIntervalSince1970))",
            title: event.title ?? "",
            start: start, end: end,
            isAllDay: event.isAllDay, isDeclined: declined,
            calendarName: event.calendar?.title ?? "", color: rgb,
            joinURL: JoinLink.find(in: [event.url?.absoluteString, event.location, event.notes]))
    }
}
