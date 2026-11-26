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
    /// A session: the chat's name over the folder it works in.
    static let sessionRowHeight: CGFloat = 36
    /// The most room a row gives the status on its right ("Run: npm test? "): longer texts are cut in the middle.
    static let detailMaxWidth: CGFloat = 170
    static let maxRows = 5

    // MARK: Bento tiles (the open island is a grid of rounded tiles)

    /// Tiles are continuous rounded rectangles; the island's own bottom corners are 28, so these sit concentric with it
    /// at an 8 pt margin.
    static let tileRadius: CGFloat = 20
    static let tileGap: CGFloat = 6
    /// Between the notch strip and the first tile, and under the last tile.
    static let bentoTop: CGFloat = 6
    static let bentoBottom: CGFloat = 8
    static let islandBottomRadius: CGFloat = 28
    /// The agents tile: a header with the count and the avatar rail, then the session rows.
    static let agentsHeaderHeight: CGFloat = 30
    static let agentsTileTop: CGFloat = 8
    static let agentsTileBottom: CGFloat = 6
    /// The agents rail on its own, shown under a waiting question.
    static let railTileHeight: CGFloat = 44
    /// Music and pomodoro share a row; side by side they are squarer, alone they are one wide strip.
    static let mediaPairHeight: CGFloat = 128
    static let mediaSingleHeight: CGFloat = 84
    static let calendarTileHeight: CGFloat = 64
    static let placeholderTileHeight: CGFloat = 44
    /// Favorites: a header and a grid of three chips per row; past two rows the grid scrolls.
    static let favoritesHeaderHeight: CGFloat = 18
    static let favoriteChipHeight: CGFloat = 28
    static let favoriteChipGap: CGFloat = 5
    static let favoriteColumns = 3
    static let favoriteMaxRows = 2
    /// With many sessions running the tile keeps to one row (the rest scrolls), so the island stays a sensible height.
    static func favoriteRows(sessions: Int) -> Int { sessions >= 4 ? 1 : favoriteMaxRows }
    /// `cells` counts the pinned projects plus the "+" chip, so the tile always has at least one row.
    static func favoritesTileHeight(cells: Int, maxRows: Int = favoriteMaxRows) -> CGFloat? {
        guard cells > 0 else { return nil }
        let rows = min(maxRows, (cells + favoriteColumns - 1) / favoriteColumns)
        return agentsTileTop + favoritesHeaderHeight + CGFloat(rows) * favoriteChipHeight + CGFloat(rows - 1) * favoriteChipGap + agentsTileBottom
    }
    /// The "finished" toast under the collapsed notch.
    static let toastWidth: CGFloat = 330
    static let toastHeight: CGFloat = 48
    /// Extra room on each side of the physical notch where status indicators live when collapsed (only while there is
    /// something to report: otherwise the pill is just the notch).
    static let indicatorWing: CGFloat = 30
    /// The collapsed pill's flared top corners take this much off each outer edge of its frame.
    static let closedEar: CGFloat = 6
    /// Clears the flared top corners.
    static let sidePadding: CGFloat = 22
    static let topGap: CGFloat = 8
    static let bottomPadding: CGFloat = 14
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

    // The card is a column of five parts with `approvalSpacing` between them, inside `approvalPadding` on every side. The view
    // draws with these same numbers, so the height below is what it needs by construction (it once drifted by 20 pt and the
    // buttons were cut off).
    static let approvalPadding: CGFloat = 12
    static let approvalSpacing: CGFloat = 10
    static let approvalHeaderHeight: CGFloat = 46
    /// The well around the command: tool pill (16) + gap (4) + vertical padding (16), without the text itself.
    static let approvalWellChrome: CGFloat = 36
    static let approvalHintsHeight: CGFloat = 18
    static let approvalButtonsHeight: CGFloat = 40
    private static let detailLineHeight: CGFloat = 15

    /// Everything in the card except the command text.
    static var cardChrome: CGFloat {
        2 * approvalPadding + approvalHeaderHeight + approvalWellChrome + approvalHintsHeight + approvalButtonsHeight
            + 4 * approvalSpacing
    }

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
    static func showsPlaceholder(sessions: Int, request: Bool, widgets: WidgetPresence, recents: Int = 0, favoriteCells: Int = 0) -> Bool {
        sessions == 0 && !request && !widgets.any && recents == 0 && favoriteCells == 0
    }

    /// Projects that were active before a restart: a small heading, then a row each, in a quiet tile.
    static let recentHeaderHeight: CGFloat = 22
    static let recentRowHeight: CGFloat = 36
    static let maxRecents = 4
    /// Live sessions and suggestions share the room: with this many sessions or more there are no suggestions.
    static let recentsBudget = 4
    static func recentsTileHeight(count: Int) -> CGFloat? {
        count > 0 ? agentsTileTop + recentHeaderHeight + CGFloat(count) * recentRowHeight + agentsTileBottom : nil
    }

    /// Past `maxRows` the rows scroll inside a window that shows `maxRows - 0.5` of them: the half row peeking out at the
    /// bottom says there is more.
    static var scrollingRowsHeight: CGFloat { (CGFloat(maxRows) - 0.5) * sessionRowHeight }

    static func rowsHeight(sessions: Int) -> CGFloat {
        sessions > maxRows ? scrollingRowsHeight : CGFloat(sessions) * sessionRowHeight
    }

    /// The agents tile, nil when there is no session.
    static func agentsTileHeight(sessions: Int) -> CGFloat? {
        sessions > 0 ? agentsTileTop + agentsHeaderHeight + rowsHeight(sessions: sessions) + agentsTileBottom : nil
    }

    /// The music / pomodoro row, nil when neither is showing.
    static func mediaRowHeight(widgets: WidgetPresence) -> CGFloat? {
        switch (widgets.music, widgets.focus) {
        case (true, true): mediaPairHeight
        case (false, false): nil
        default: mediaSingleHeight
        }
    }

    /// The tiles of the open island, top to bottom. A waiting question takes the grid: its tile, and under it only a slim
    /// rail of the agents; the music, pomodoro and calendar tiles give way.
    static func tileHeights(sessions: Int, request: PermissionPrompt?, widgets: WidgetPresence, recents: Int, favoriteCells: Int = 0) -> [CGFloat] {
        var tiles: [CGFloat] = []
        if let request {
            tiles.append(cardHeight(for: request))
            if sessions > 0 { tiles.append(railTileHeight) }
            return tiles
        }
        if showsPlaceholder(sessions: sessions, request: false, widgets: widgets, recents: recents, favoriteCells: favoriteCells) { tiles.append(placeholderTileHeight) }
        if let agents = agentsTileHeight(sessions: sessions) { tiles.append(agents) }
        if let favorites = favoritesTileHeight(cells: favoriteCells, maxRows: favoriteRows(sessions: sessions)) { tiles.append(favorites) }
        if let recent = recentsTileHeight(count: recents) { tiles.append(recent) }
        if let media = mediaRowHeight(widgets: widgets) { tiles.append(media) }
        if widgets.calendar { tiles.append(calendarTileHeight) }
        return tiles
    }

    /// The open island is a grid of tiles with equal gaps: the agents, what you were working on, music and pomodoro, the
    /// calendar. A waiting question takes the grid (see `tileHeights`).
    func size(open: Bool, sessions: Int, request: PermissionPrompt?, widgets: WidgetPresence, closedStatus: Bool,
              mode: IslandMode = .list, recents: Int = 0, favoriteCells: Int = 0, toast: Bool = false) -> CGSize {
        guard open else {
            let items = Self.pillItems(sessions: sessions, status: closedStatus, widgets: widgets)
            let width = notch.width + (items.isEmpty ? 0 : Self.pillWing(items) * 2)
            if toast { return CGSize(width: max(width, Self.toastWidth), height: notch.height + Self.toastHeight) }
            return CGSize(width: width, height: notch.height)
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
        let tiles = Self.tileHeights(sessions: sessions, request: request, widgets: widgets, recents: recents, favoriteCells: favoriteCells)
        let content = tiles.reduce(0, +) + CGFloat(max(0, tiles.count - 1)) * Self.tileGap
        return CGSize(width: Self.openWidth, height: notch.height + Self.bentoTop + content + Self.bentoBottom)
    }

    @MainActor
    func size(for store: SessionStore, widgets: WidgetPresence, display: CGDirectDisplayID) -> CGSize {
        // Stepping aside for a full-screen video: the collapsed pill has nothing to show (the open island is unaffected).
        let hidden = store.hiddenPillDisplays.contains(display)
        var shown = widgets
        if hidden { shown.musicPlaying = false; shown.focusRunning = false }
        return size(open: store.isOpen(on: display), sessions: store.sessions.count, request: store.requests.first?.prompt, widgets: shown,
                    closedStatus: store.closedStatus != nil && !hidden, mode: store.mode, recents: store.visibleRecents.count,
                    favoriteCells: store.favorites.items.count + 1, toast: store.toast != nil && !hidden)
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
