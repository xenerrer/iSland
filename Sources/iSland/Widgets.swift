import Combine
import Foundation
import IslandCore

/// Everything that is not an agent session: what is playing, and the next event on your calendar.
@MainActor
final class Widgets: ObservableObject {
    let music = NowPlayingManager()
    let calendar = CalendarManager()
    let focus = FocusTimer()
    private let appearance: Appearance
    private var subscriptions = Set<AnyCancellable>()

    init(appearance: Appearance) {
        self.appearance = appearance
        // The island redraws when any of them changes.
        Publishers.MergeMany(music.objectWillChange, calendar.objectWillChange, appearance.objectWillChange,
                             focus.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        // Switching music off also stops the Perl child process.
        appearance.$showMusic
            .dropFirst()
            .sink { [weak self] on in on ? self?.music.start() : self?.music.stop() }
            .store(in: &subscriptions)
    }

    /// Which cards the open island shows. The layout reads it to size the island.
    var presence: WidgetPresence {
        let music = appearance.showMusic && music.state.hasTrack
        return WidgetPresence(music: music,
                              calendar: appearance.showCalendar && calendar.showsCard,
                              musicPlaying: music && self.music.state.isPlaying,
                              focus: focus.isActive,
                              focusRunning: focus.isActive)
    }

    func start() {
        if appearance.showMusic { music.start() }
        calendar.start()
    }

    func stop() {
        music.stop()
        calendar.stop()
    }

    /// Made-up music and events, for demos and snapshots.
    func loadPreview() {
        var track = NowPlayingState()
        track.title = "Midnight City"
        track.artist = "M83"
        let paused = CommandLine.arguments.contains("--paused") // dev flag: preview the paused state
        track.isPlaying = !paused
        track.duration = 244
        track.elapsed = 83
        track.rate = paused ? 0 : 1
        track.timestamp = Date()
        track.bundleID = "com.spotify.client"
        music.preview(track, appName: "Spotify")

        let now = Date()
        if CommandLine.arguments.contains("--focus") { focus.start(now: Date().addingTimeInterval(-9 * 60)) } // 9 minutes in
        let day = Calendar.current.startOfDay(for: now)
        func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(byAdding: .minute, value: hour * 60 + minute, to: Calendar.current.date(byAdding: .day, value: days, to: day)!)!
        }
        let work = [0.2, 0.78, 0.45], personal = [0.95, 0.5, 0.3], other = [0.45, 0.45, 0.95]
        let demo = [
            CalendarEvent(id: "a", title: "Feriado: Dia da Padroeira", start: day, end: at(0, 23, 59), isAllDay: true, calendarName: "Feriados", color: other),
            CalendarEvent(id: "b", title: "Alinhamento semanal", start: now.addingTimeInterval(-3 * 3600), end: now.addingTimeInterval(-2 * 3600),
                          calendarName: "Trabalho", color: work),
            CalendarEvent(id: "c", title: "Daily com o time", start: now.addingTimeInterval(-10 * 60), end: now.addingTimeInterval(20 * 60),
                          calendarName: "Trabalho", color: work, joinURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            CalendarEvent(id: "d", title: "Dentista", start: now.addingTimeInterval(3 * 3600), end: now.addingTimeInterval(4 * 3600),
                          calendarName: "Pessoal", color: personal),
        ]
        calendar.preview(demo, sources: ["Google", "iCloud"])
    }
}
