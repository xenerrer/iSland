import AppKit
import CoreGraphics
import IslandCore
import Testing
@testable import iSland

// The view stacks its children with equal spacing, so the island's height is the sum of the children plus the gaps.
// These numbers must stay in step with IslandView.

@Suite("IslandLayout") struct IslandLayoutTests {
    let layout = IslandLayout(notch: CGSize(width: 186, height: 38))
    let none = WidgetPresence()
    let ask = PermissionPrompt(tool: "Bash", title: "Run command", detail: "ls", waitSeconds: 20)

    /// Header + top gap + tiles + the gaps between them + bottom margin.
    func height(_ tiles: [CGFloat]) -> CGFloat {
        38 + IslandLayout.bentoTop + tiles.reduce(0, +) + CGFloat(max(0, tiles.count - 1)) * IslandLayout.tileGap
            + IslandLayout.bentoBottom
    }

    func agents(_ sessions: Int) -> CGFloat { IslandLayout.agentsTileHeight(sessions: sessions)! }

    @Test func theClosedPillIsTheNotchUntilThereIsSomethingToReport() {
        let notch = CGSize(width: 186, height: 38)
        #expect(layout.size(open: false, sessions: 0, request: nil, widgets: none, closedStatus: false) == notch)
        // sessions that are all at rest report nothing: no wings, just the notch
        #expect(layout.size(open: false, sessions: 3, request: nil, widgets: none, closedStatus: false) == notch)
        // work, a question or a job that just finished: wings for the indicator
        #expect(layout.size(open: false, sessions: 2, request: nil, widgets: none, closedStatus: true).width
                == 186 + IslandLayout.indicatorWing * 2)
        // paused music shows nothing when closed; playing music gets an equalizer in the wing
        #expect(layout.size(open: false, sessions: 0, request: nil, widgets: WidgetPresence(music: true), closedStatus: false).width == 186)
        #expect(layout.size(open: false, sessions: 0, request: nil, widgets: WidgetPresence(music: true, musicPlaying: true), closedStatus: false).width
                == 186 + IslandLayout.indicatorWing * 2)
    }

    @Test func anEmptyIslandSaysSoOnlyWhenThereIsNothingElse() {
        #expect(layout.size(open: true, sessions: 0, request: nil, widgets: none, closedStatus: false).height == height([IslandLayout.placeholderTileHeight]))
        let music = WidgetPresence(music: true)
        #expect(layout.size(open: true, sessions: 0, request: nil, widgets: music, closedStatus: false).height == height([IslandLayout.mediaSingleHeight]))
    }

    @Test func widgetsStackUnderTheSessions() {
        let music = WidgetPresence(music: true, calendar: true, musicPlaying: true)
        let expected = height([agents(2), IslandLayout.mediaSingleHeight, IslandLayout.calendarTileHeight])
        let size = layout.size(open: true, sessions: 2, request: nil, widgets: music, closedStatus: false)
        #expect(size.height == expected)
        #expect(size.width == IslandLayout.openWidth)
    }

    @Test func aQuestionTakesTheIslandAndWidgetsGiveWay() {
        let both = WidgetPresence(music: true, calendar: true)
        let withWidgets = layout.size(open: true, sessions: 1, request: ask, widgets: both, closedStatus: false)
        let without = layout.size(open: true, sessions: 1, request: ask, widgets: none, closedStatus: false)
        #expect(withWidgets == without)
        // the question's tile, and under it only the slim rail of agents
        #expect(without.height == height([IslandLayout.cardHeight(for: ask), IslandLayout.railTileHeight]))
        #expect(layout.size(open: true, sessions: 0, request: ask, widgets: none, closedStatus: false).height == height([IslandLayout.cardHeight(for: ask)]))
    }

    @Test func manySessionsScrollInsideOneWindow() {
        #expect(IslandLayout.agentsTileHeight(sessions: 0) == nil)
        #expect(IslandLayout.rowsHeight(sessions: 5) == 5 * IslandLayout.sessionRowHeight)
        // past the cap, one window over all of them that shows the fifth row only in part, so it is clear it scrolls
        let row = IslandLayout.sessionRowHeight
        #expect(IslandLayout.rowsHeight(sessions: 9) == IslandLayout.scrollingRowsHeight)
        #expect(IslandLayout.scrollingRowsHeight < 5 * row) // less than five full rows
        #expect(IslandLayout.scrollingRowsHeight > 4 * row) // more than four: the fifth peeks out
        let tall = layout.size(open: true, sessions: 9, request: nil, widgets: none, closedStatus: false).height
        #expect(tall == height([agents(9)]))
    }

    @Test func theFavoritesTileGrowsToTwoRowsThenScrolls() {
        #expect(IslandLayout.favoritesTileHeight(cells: 0) == nil)
        let one = IslandLayout.favoritesTileHeight(cells: 1)!, three = IslandLayout.favoritesTileHeight(cells: 3)!
        let four = IslandLayout.favoritesTileHeight(cells: 4)!, many = IslandLayout.favoritesTileHeight(cells: 20)!
        #expect(one == three)
        #expect(four - three == IslandLayout.favoriteChipHeight + IslandLayout.favoriteChipGap)
        #expect(many == IslandLayout.favoritesTileHeight(cells: 6)!) // past two rows it scrolls, so it stops growing
    }

    @Test func theMusicAndPomodoroTilesShareARowOrStandAloneWide() {
        #expect(IslandLayout.mediaRowHeight(widgets: WidgetPresence()) == nil)
        #expect(IslandLayout.mediaRowHeight(widgets: WidgetPresence(music: true)) == IslandLayout.mediaSingleHeight)
        #expect(IslandLayout.mediaRowHeight(widgets: WidgetPresence(focus: true)) == IslandLayout.mediaSingleHeight)
        #expect(IslandLayout.mediaRowHeight(widgets: WidgetPresence(music: true, focus: true)) == IslandLayout.mediaPairHeight)
    }

    @Test func theFullestIslandStillFitsTheBudget() {
        let everything = WidgetPresence(music: true, calendar: true, musicPlaying: true, focus: true, focusRunning: true)
        for sessions in 0...12 {
            let recents = sessions == 0 ? IslandLayout.maxRecents : 0 // what SessionStore offers once something is pinned
            let size = layout.size(open: true, sessions: sessions, request: nil, widgets: everything, closedStatus: true, recents: recents,
                                   favoriteCells: 7) // six pinned and the "+": the tile at its tallest
            #expect(size.height <= 560, "\(sessions) sessions, \(recents) recents: \(size.height)")
            #expect(size.height <= IslandLayout.panelHeight)
        }
        // the approval tile with the longest command
        let long = PermissionPrompt(tool: "Bash", title: "Run command", detail: String(repeating: "x", count: 2000), waitSeconds: 20)
        #expect(layout.size(open: true, sessions: 5, request: long, widgets: everything, closedStatus: true).height <= 500)
    }

    @Test func theMirrorIsACircleUnderTheNotchAndAQuestionStillWins() {
        let mirror = layout.size(open: true, sessions: 3, request: nil, widgets: none, closedStatus: false, mode: .mirror)
        #expect(mirror.width == IslandLayout.mirrorWidth)
        #expect(mirror.height == 38 + IslandLayout.topGap + IslandLayout.mirrorDiameter + IslandLayout.mirrorSpacing
                    + IslandLayout.mirrorButtonHeight + IslandLayout.bottomPadding)
        #expect(mirror.height <= IslandLayout.panelHeight)
        // a waiting question takes the island back from the mirror
        let withQuestion = layout.size(open: true, sessions: 3, request: ask, widgets: none, closedStatus: false, mode: .mirror)
        #expect(withQuestion == layout.size(open: true, sessions: 3, request: ask, widgets: none, closedStatus: false))
        // closed, the flag changes nothing
        #expect(layout.size(open: false, sessions: 0, request: nil, widgets: none, closedStatus: false, mode: .mirror).width == 186)
    }

    @Test func theFocusCardAndPillAreSized() {
        let cards = WidgetPresence(music: true, calendar: true, focus: true)
        let expected = height([agents(1), IslandLayout.mediaPairHeight, IslandLayout.calendarTileHeight])
        #expect(layout.size(open: true, sessions: 1, request: nil, widgets: cards, closedStatus: false).height == expected)
        // a focus run puts the minutes left in the closed pill, so it gets its wings
        #expect(layout.size(open: false, sessions: 0, request: nil, widgets: WidgetPresence(focus: true, focusRunning: true),
                            closedStatus: false).width == 186 + IslandLayout.pillWing([.pomodoro]) * 2)
        #expect(layout.size(open: false, sessions: 0, request: nil, widgets: WidgetPresence(focus: true), closedStatus: false).width == 186)
    }

    @Test func thePillSharesItsItemsEvenlyOverTheTwoSides() {
        func sides(_ items: [PillItem]) -> (Int, Int) { let s = IslandLayout.pillSides(items); return (s.left.count, s.right.count) }
        #expect(sides([]) == (0, 0))
        #expect(IslandLayout.pillSides([.status]).right == [.status]) // alone, the status keeps to the right
        #expect(IslandLayout.pillSides([.equalizer]).left == [.equalizer])
        #expect(sides([.count, .status]) == (1, 1))
        #expect(sides([.equalizer, .status]) == (1, 1))
        let pair = IslandLayout.pillSides([.pomodoro, .status])
        #expect(pair.left == [.pomodoro] && pair.right == [.status])
        #expect(sides([.count, .equalizer, .pomodoro, .status]) == (2, 2)) // four icons: two and two
        #expect(abs(sides([.count, .equalizer, .pomodoro]).0 - sides([.count, .equalizer, .pomodoro]).1) <= 1)
        // one wing width for both sides, never narrower than before
        #expect(IslandLayout.pillWing([.status]) == IslandLayout.indicatorWing)
        #expect(IslandLayout.pillWing([.pomodoro, .status]) == IslandLayout.indicatorWing) // the tomato needs no more room than any other
    }

    @Test func theTomatoJoinsTheStatusWhileAPomodoroRuns() {
        let running = WidgetPresence(focus: true, focusRunning: true)
        #expect(IslandLayout.pillItems(sessions: 1, status: true, widgets: running) == [.pomodoro, .status])
        #expect(IslandLayout.pillItems(sessions: 3, status: true, widgets: WidgetPresence(musicPlaying: true)) == [.count, .equalizer, .status])
        #expect(IslandLayout.pillItems(sessions: 3, status: false, widgets: WidgetPresence()).isEmpty)
    }

    @Test func withoutAHardwareNotchTheClosedPillOnlyShowsWhenItHasSomethingToSay() {
        #expect(IslandLayout.drawsClosedPill(hasHardwareNotch: true, items: []))
        #expect(!IslandLayout.drawsClosedPill(hasHardwareNotch: false, items: []))
        #expect(IslandLayout.drawsClosedPill(hasHardwareNotch: false, items: [.status]))
        // the hover zone is the virtual notch either way
        let virtual = IslandLayout(notch: CGSize(width: 150, height: 24), hasHardwareNotch: false)
        #expect(virtual.size(open: false, sessions: 0, request: nil, widgets: none, closedStatus: false) == CGSize(width: 150, height: 24))
    }

    @Test func theNewChatPanelGrowsWithItsFolders() {
        func panel(_ folders: Int) -> CGSize {
            layout.size(open: true, sessions: 2, request: nil, widgets: none, closedStatus: false, mode: .newChat(folders: folders))
        }
        #expect(panel(3).width == IslandLayout.newChatWidth)
        #expect(panel(4).height - panel(3).height == IslandLayout.folderRowHeight + IslandLayout.folderRowSpacing)
        #expect(panel(0).height == panel(1).height) // the empty message takes one row
        #expect(panel(6).height <= IslandLayout.panelHeight)
        // a question still takes the island back
        let asked = layout.size(open: true, sessions: 2, request: ask, widgets: none, closedStatus: false, mode: .newChat(folders: 3))
        #expect(asked == layout.size(open: true, sessions: 2, request: ask, widgets: none, closedStatus: false))
    }

    @Test func thePomodoroSetupHasAFixedSizeAndFits() {
        let size = layout.size(open: true, sessions: 2, request: nil, widgets: none, closedStatus: false, mode: .pomodoro)
        #expect(size.width == IslandLayout.newChatWidth && size.height <= IslandLayout.panelHeight)
    }

    @Test func theTallestIslandFitsInThePanel() {
        // The panel is IslandLayout.panelHeight tall. A question plus a full list is the worst case, since widgets give way.
        let longCommand = PermissionPrompt(tool: "Bash", title: "t", detail: String(repeating: "x", count: 500), waitSeconds: 20)
        let worstWithQuestion = layout.size(open: true, sessions: 9, request: longCommand, widgets: none, closedStatus: false).height
        let worstWithWidgets = layout.size(open: true, sessions: 9, request: nil, widgets: WidgetPresence(music: true, calendar: true, focus: true), closedStatus: false).height
        #expect(worstWithQuestion <= IslandLayout.panelHeight)
        #expect(worstWithWidgets <= IslandLayout.panelHeight)
    }
}

@MainActor
@Suite("Bento visuals") struct BentoVisualTests {
    @Test func dangerousWordsInACommandAreMarked() {
        let marked = ApprovalCard.highlighted("npm test && rm -rf ./tmp && sudo reboot")
        let colored = marked.runs.filter { $0.foregroundColor != nil }.map { String(marked[$0.range].characters) }
        #expect(colored == ["rm -rf", "sudo"])
        #expect(ApprovalCard.highlighted("ls -la").runs.allSatisfy { $0.foregroundColor == nil })
    }

    @Test func aCoverTintStaysReadable() throws {
        let tint = try #require(NSImage.demoCover().averageTint())
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #expect(s >= 0.35)            // never grey
        #expect((0.5...0.85).contains(b)) // never so bright that white text washes out, nor so dark it vanishes
    }
}
