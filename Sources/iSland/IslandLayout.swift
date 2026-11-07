import CoreGraphics
import IslandCore
import SwiftUI

/// Which widget cards the open island shows. The layout needs it to size the island.
struct WidgetPresence: Equatable {
    var music = false
    var calendar = false
    /// Something is playing right now (not merely paused): the closed pill then shows an equalizer.
    var musicPlaying = false
    /// The focus timer card (running, or just ended).
    var focus = false
    /// A focus run is counting down: the closed pill shows the minutes left.
    var focusRunning = false

    var any: Bool { music || calendar || focus }
}

/// What the open island is showing.
enum IslandMode: Equatable {
    case list
    case mirror
    /// The pomodoro's rhythm, to adjust and start.
    case pomodoro
    /// Recent folders to start a new chat in.
    case newChat(folders: Int)
}

/// Something the collapsed pill can show beside the notch.
enum PillItem: Equatable {
    case count      // how many sessions
    case equalizer  // music is playing
    case pomodoro   // a small ring of dots that go out as the phase runs down
    case status     // what the agents are doing

    /// Room it takes in a wing, beside the ear of the pill.
    var width: CGFloat { IslandLayout.indicatorWing - IslandLayout.closedEar }
    var prefersRight: Bool { self == .status }
}

/// Single source of truth for the island's size, shared by the view and the pointer tracking.
/// Every number here has a twin in IslandView; change them together.
struct IslandLayout: Equatable {
    let notch: CGSize
    var hasHardwareNotch = true
    /// A display without a notch next to one that has it: the pill is drawn all the time, a virtual notch to point the pointer at.
    var alwaysDrawsPill = false

    static let openWidth: CGFloat = 440
    /// A line of text: "No active agents", "+3 more".
    static let rowHeight: CGFloat = 28
    /// A session: the chat's name over the folder it works in.
    static let sessionRowHeight: CGFloat = 38
    /// The most room a row gives the status on its right ("Run: npm test? "): longer texts are cut in the middle.
    static let detailMaxWidth: CGFloat = 170
    static let rowSpacing: CGFloat = 6
    static let maxRows = 5
    /// Extra room on each side of the physical notch where status indicators live when collapsed (only while there is
    /// something to report: otherwise the pill is just the notch).
    static let indicatorWing: CGFloat = 30
    /// The collapsed pill's flared top corners take this much off each outer edge of its frame.
    static let closedEar: CGFloat = 6
    /// Clears the flared top corners.
    static let sidePadding: CGFloat = 22
    static let topGap: CGFloat = 8
    static let bottomPadding: CGFloat = 14
    /// A music or calendar card.
    static let widgetHeight: CGFloat = 56
    /// The focus card.
    static let compactWidgetHeight: CGFloat = 44
    static let panelWidth: CGFloat = openWidth + 80
    /// The transparent panel the island is drawn in; bigger than any state of the island.
    static let panelHeight: CGFloat = 600
    /// The "new chat" panel: a row per recent folder under the notch, then the way back.
    static let newChatWidth: CGFloat = 340
    static let folderRowHeight: CGFloat = 36
    static let folderRowSpacing: CGFloat = 4
    /// Focus, short break, long break, rounds.
    static let pomodoroRows = 4
    /// The camera mirror: a circle under the notch, then the way back.
    static let mirrorWidth: CGFloat = 280
    static let mirrorDiameter: CGFloat = 190
    static let mirrorSpacing: CGFloat = 10
    static let mirrorButtonHeight: CGFloat = 28

    // MARK: Approval card

    /// Everything in the card except the command text: header, spacing, buttons and padding.
    private static let cardChrome: CGFloat = 124
    private static let detailLineHeight: CGFloat = 15

    /// How many lines the command box shows (1...6), estimated from the text.
    static func detailLines(_ text: String) -> Int {
        min(PermissionPrompt.visibleLines, PermissionPrompt.estimatedLines(of: text))
    }

    static func cardHeight(for prompt: PermissionPrompt) -> CGFloat {
        cardChrome + CGFloat(detailLines(prompt.detail)) * detailLineHeight
    }

    // MARK: Collapsed pill

    /// Whether the collapsed pill is drawn at all. Over a hardware notch it always is (it fuses with it); with no notch it
    /// would be a black block on the menu bar, so it only shows while it has something to say.
    static func drawsClosedPill(hasHardwareNotch: Bool, alwaysDraws: Bool = false, items: [PillItem]) -> Bool {
        hasHardwareNotch || alwaysDraws || !items.isEmpty
    }

    /// What the collapsed pill shows, in a fixed order.
    static func pillItems(sessions: Int, status: Bool, widgets: WidgetPresence) -> [PillItem] {
        var items: [PillItem] = []
        if status && sessions > 1 { items.append(.count) }
        if widgets.musicPlaying { items.append(.equalizer) }
        if widgets.focusRunning { items.append(.pomodoro) }
        if status { items.append(.status) }
        return items
    }

    /// Splits the items over the two sides of the notch so each side gets the same number, give or take one: the widest
    /// first, each to the side with fewer, and on a tie to the side it prefers (the left, except for the status and ring).
    static func pillSides(_ items: [PillItem]) -> (left: [PillItem], right: [PillItem]) {
        var left: [PillItem] = [], right: [PillItem] = []
        for item in items.enumerated().sorted(by: { ($0.element.width, -$0.offset) > ($1.element.width, -$1.offset) }).map(\.element) {
            if left.count < right.count { left.append(item) }
            else if right.count < left.count { right.append(item) }
            else if item.prefersRight { right.append(item) } else { left.append(item) }
        }
        return (left, right)
    }

    /// Both wings are as wide as the fuller one, so the pill stays centred on the notch.
    static func pillWing(_ items: [PillItem]) -> CGFloat {
        let sides = pillSides(items)
        let fuller = max(sides.left.reduce(0) { $0 + $1.width }, sides.right.reduce(0) { $0 + $1.width })
        return max(indicatorWing, fuller + closedEar)
    }

    // MARK: Island

    /// "No active agents" is only said when there is nothing else to show.
    static func showsPlaceholder(sessions: Int, request: Bool, widgets: WidgetPresence, recents: Int = 0) -> Bool {
        sessions == 0 && !request && !widgets.any && recents == 0
    }

    /// Past `maxRows` the list scrolls inside a window that shows `maxRows - 0.5` rows: the half row peeking out at the bottom
    /// says there is more.
    static var scrollingListHeight: CGFloat {
        (CGFloat(maxRows) - 0.5) * sessionRowHeight + CGFloat(maxRows - 1) * rowSpacing
    }

    /// Projects that were active before a restart: a small heading, then a row each.
    static let recentHeaderHeight: CGFloat = 20
    static let recentRowHeight: CGFloat = 38
    static let maxRecents = 4
    static func recentHeights(count: Int) -> [CGFloat] {
        count > 0 ? [recentHeaderHeight] + Array(repeating: recentRowHeight, count: count) : []
    }

    /// The session list: a row per session up to `maxRows`, then one scrolling window over all of them.
    static func sessionRowHeights(sessions: Int) -> [CGFloat] {
        if sessions > maxRows { return [scrollingListHeight] }
        return Array(repeating: sessionRowHeight, count: sessions)
    }

    /// The open island stacks its children with equal spacing: the question, the sessions, then music and calendar.
    /// Widgets give way while a question is waiting, so the card has the island's full attention.
    func size(open: Bool, sessions: Int, request: PermissionPrompt?, widgets: WidgetPresence, closedStatus: Bool,
              mode: IslandMode = .list, recents: Int = 0) -> CGSize {
        guard open else {
            let items = Self.pillItems(sessions: sessions, status: closedStatus, widgets: widgets)
            return CGSize(width: notch.width + (items.isEmpty ? 0 : Self.pillWing(items) * 2), height: notch.height)
        }
        if request == nil { // a question takes the island back from the mirror and the folder list
            switch mode {
            case .list:
                break
            case .mirror:
                let content = Self.mirrorDiameter + Self.mirrorSpacing + Self.mirrorButtonHeight
                return CGSize(width: Self.mirrorWidth, height: notch.height + Self.topGap + content + Self.bottomPadding)
            case .pomodoro:
                let list = CGFloat(Self.pomodoroRows) * Self.folderRowHeight + CGFloat(Self.pomodoroRows - 1) * Self.folderRowSpacing
                let content = list + Self.mirrorSpacing + Self.mirrorButtonHeight
                return CGSize(width: Self.newChatWidth, height: notch.height + Self.topGap + content + Self.bottomPadding)
            case .newChat(let folders):
                let rows = max(1, folders)
                let list = CGFloat(rows) * Self.folderRowHeight + CGFloat(rows - 1) * Self.folderRowSpacing
                let content = list + Self.mirrorSpacing + Self.mirrorButtonHeight
                return CGSize(width: Self.newChatWidth, height: notch.height + Self.topGap + content + Self.bottomPadding)
            }
        }
        var children: [CGFloat] = []
        if let request { children.append(Self.cardHeight(for: request)) }
        if Self.showsPlaceholder(sessions: sessions, request: request != nil, widgets: widgets, recents: recents) { children.append(Self.rowHeight) }
        children += Self.sessionRowHeights(sessions: sessions)
        if request == nil {
            children += Self.recentHeights(count: recents)
            if widgets.focus { children.append(Self.compactWidgetHeight) }
            if widgets.music { children.append(Self.widgetHeight) }
            if widgets.calendar { children.append(Self.widgetHeight) }
        }
        let content = children.reduce(0, +) + CGFloat(max(0, children.count - 1)) * Self.rowSpacing
        return CGSize(width: Self.openWidth, height: notch.height + Self.topGap + content + Self.bottomPadding)
    }

    @MainActor
    func size(for store: SessionStore, widgets: WidgetPresence, display: CGDirectDisplayID) -> CGSize {
        // Stepping aside for a full-screen video: the collapsed pill has nothing to show (the open island is unaffected).
        let hidden = store.hiddenPillDisplays.contains(display)
        var shown = widgets
        if hidden { shown.musicPlaying = false; shown.focusRunning = false }
        return size(open: store.isOpen(on: display), sessions: store.sessions.count, request: store.requests.first?.prompt, widgets: shown,
                    closedStatus: store.closedStatus != nil && !hidden, mode: store.mode, recents: store.visibleRecents.count)
    }
}

/// How the island moves. *Smooth* is the default and follows Apple's own motion: a soft spring that opens with barely a hint
/// of bounce and closes with none, and content that fades in out of a light blur once the container has begun to grow
/// (and leaves quickly, so it is never squashed). *Bouncy* is the livelier motion of the original boring.notch.
enum MotionStyle: String, CaseIterable {
    case smooth, bouncy
}

enum Motion {
    static func open(_ style: MotionStyle) -> Animation {
        switch style {
        case .smooth: .spring(duration: 0.5, bounce: 0.12)
        case .bouncy: .spring(response: 0.42, dampingFraction: 0.8)
        }
    }

    static func close(_ style: MotionStyle) -> Animation {
        switch style {
        // Closing is in order: the content leaves first (`closeHold` is its fade), then the container shrinks, then the glass dissolves.
        case .smooth: .spring(duration: 0.34, bounce: 0).delay(closeHold)
        // boring.notch's own: one spring for the whole container, no hold, the content leaving at the same time.
        case .bouncy: .spring(response: 0.45, dampingFraction: 1.0)
        }
    }

    static let closeHold = 0.1
    /// When the glass starts to dissolve after a close begins: the container has all but settled by then.
    static let glassLeaves = 0.0
    /// When the glass starts to arrive on opening: the black shape has grown out of the notch first, then turns to glass.
    static let glassArrives = 0.1
    /// A glass inserted together with the toggle fades in only after the container has all but settled.
    static let glassInserted = 0.3

    /// The content drops in from the top, behind the growing shape, and leaves quickly; it never moves sideways.
    static func content(_ style: MotionStyle) -> AnyTransition {
        switch style {
        case .smooth:
            .asymmetric(
                insertion: AnyTransition.blur(6).combined(with: .dropIn).combined(with: .opacity)
                    .animation(.smooth(duration: 0.3).delay(0.18)),
                removal: AnyTransition.opacity.animation(.easeOut(duration: 0.14)))
        case .bouncy:
            // boring.notch's timing (smooth 0.35 s, no delay); leaves in 0.1 s so no ghost of it is left in the shrinking pill.
            .asymmetric(insertion: AnyTransition.dropIn.combined(with: .opacity).animation(.smooth(duration: 0.35)),
                        removal: .opacity.animation(.easeOut(duration: 0.1)))
        }
    }
}

private struct DropIn: ViewModifier {
    let offset: CGFloat
    func body(content: Content) -> some View { content.offset(y: offset) }
}

private struct BlurAmount: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// Arrives from a little above, never from the sides.
    static var dropIn: AnyTransition { .modifier(active: DropIn(offset: -14), identity: DropIn(offset: 0)) }

    /// Arrives out of a blur that clears.
    static func blur(_ radius: CGFloat) -> AnyTransition {
        .modifier(active: BlurAmount(radius: radius), identity: BlurAmount(radius: 0))
    }
}
