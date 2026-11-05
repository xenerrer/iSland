import AppKit
import IslandCore
import SwiftUI

private let cardBackground = RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06))

/// Today's agenda in a card the height of one event: it opens on the one in progress (or the next), and scrolling up or
/// down moves through the rest of the day, one event at a time.
struct CalendarCard: View {
    @ObservedObject var calendar: CalendarManager
    /// "See how I look" on a meeting with a link: opens the mirror, with a way to join from there.
    var onMirror: (URL) -> Void = { _ in }

    var body: some View {
        Group {
            switch calendar.access {
            case .authorized:
                events
            case .notDetermined:
                prompt(L10n.t("Show your calendar here"), button: L10n.t("Connect")) { calendar.requestAccess() }
            case .denied:
                prompt(L10n.t("Calendar access is off"), button: L10n.t("Open Settings")) { calendar.openPrivacySettings() }
            case .unavailable:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: IslandLayout.widgetHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(cardBackground)
    }

    private var events: some View {
        let list = calendar.todayEvents
        let now = calendar.now
        // Opens on what is happening or comes next; if the day is over, on the last one.
        let start = list.first { !$0.isAllDay && $0.end > now } ?? list.last
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, event in
                        EventRow(event: event, now: now, position: list.count > 1 ? "\(index + 1)/\(list.count)" : nil, onMirror: onMirror)
                            .frame(height: IslandLayout.widgetHeight)
                            .id(event.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .onAppear { if let start { proxy.scrollTo(start.id, anchor: .top) } }
        }
    }

    private func prompt(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar").font(.system(size: 15)).foregroundStyle(ClaudeSpinner.orange)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(1)
            Spacer(minLength: 4)
            Button(button, action: action).buttonStyle(CapsuleButtonStyle(fill: Color.white.opacity(0.15), foreground: Color.white))
        }
        .padding(.horizontal, 12)
    }
}

/// One event: the bar in its calendar's colour, the time, the title, when it happens, and a way in when it has a link.
struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    /// "2/5": where this event sits in the day, shown when there is more than one so you know the card scrolls.
    var position: String?
    var onMirror: (URL) -> Void = { _ in }

    private var isOver: Bool { !event.isAllDay && event.end <= now }

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color(.sRGB, red: event.color[0], green: event.color[1], blue: event.color[2]))
                .frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.isAllDay ? L10n.t("All day") : event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isOver ? Color.white.opacity(0.5) : ClaudeSpinner.orange)
                    Text(event.title.isEmpty ? L10n.t("(untitled)") : event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let url = event.joinURL, !isOver {
                Button { onMirror(url) } label: {
                    MirrorGlyph(size: 13).frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(IconButtonStyle())
                .help(L10n.t("See how I look"))
                .accessibilityLabel(L10n.t("See how I look"))
                // Green only in the last 5 minutes before the call; before that it is a quiet grey (still there if you want in early).
                let urgent = Agenda.joinIsUrgent(event, now: now)
                Button(L10n.t("Join")) { NSWorkspace.shared.open(url) }
                    .buttonStyle(CapsuleButtonStyle(fill: urgent ? Color(red: 0.3, green: 0.85, blue: 0.45) : Color.white.opacity(0.12),
                                                    foreground: urgent ? Color.black.opacity(0.85) : Color.white.opacity(0.55)))
            }
        }
        .padding(.horizontal, 12)
        .opacity(isOver ? 0.55 : 1)
    }

    private var subtitle: String {
        let when = event.isAllDay ? "" : L10n.timing(Agenda.timing(of: event, now: now))
        return [when, event.calendarName, position ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
