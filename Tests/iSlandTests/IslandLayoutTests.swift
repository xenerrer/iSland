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

    /// Header + top gap + children + the gaps between them + bottom padding.
    func height(_ children: [CGFloat]) -> CGFloat {
        38 + IslandLayout.topGap + children.reduce(0, +) + CGFloat(max(0, children.count - 1)) * IslandLayout.rowSpacing
            + IslandLayout.bottomPadding
    }

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
        #expect(layout.size(open: true, sessions: 0, request: nil, widgets: none, closedStatus: false).height == height([IslandLayout.rowHeight]))
        let music = WidgetPresence(music: true)
        #expect(layout.size(open: true, sessions: 0, request: nil, widgets: music, closedStatus: false).height == height([IslandLayout.widgetHeight]))
    }

    @Test func widgetsStackUnderTheSessions() {
        let music = WidgetPresence(music: true, calendar: true, musicPlaying: true)
        let expected = height([IslandLayout.sessionRowHeight, IslandLayout.sessionRowHeight, IslandLayout.widgetHeight, IslandLayout.widgetHeight])
        let size = layout.size(open: true, sessions: 2, request: nil, widgets: music, closedStatus: false)
        #expect(size.height == expected)
        #expect(size.width == IslandLayout.openWidth)
    }

    @Test func aQuestionTakesTheIslandAndWidgetsGiveWay() {
        let both = WidgetPresence(music: true, calendar: true)
        let withWidgets = layout.size(open: true, sessions: 1, request: ask, widgets: both, closedStatus: false)
        let without = layout.size(open: true, sessions: 1, request: ask, widgets: none, closedStatus: false)
        #expect(withWidgets == without)
        #expect(without.height == height([IslandLayout.cardHeight(for: ask), IslandLayout.sessionRowHeight]))
    }

    @Test func manySessionsScrollInsideOneWindow() {
        #expect(IslandLayout.sessionRowHeights(sessions: 0).isEmpty)
        #expect(IslandLayout.sessionRowHeights(sessions: 5) == Array(repeating: IslandLayout.sessionRowHeight, count: 5))
        // past the cap, one window over all of them that shows the fifth row only in part, so it is clear it scrolls
        let capped = IslandLayout.sessionRowHeights(sessions: 9)
        #expect(capped == [IslandLayout.scrollingListHeight])
        #expect(IslandLayout.scrollingListHeight < height(IslandLayout.sessionRowHeights(sessions: 5)))
        #expect(IslandLayout.scrollingListHeight > height(IslandLayout.sessionRowHeights(sessions: 4)))
        let tall = layout.size(open: true, sessions: 9, request: nil, widgets: none, closedStatus: false).height
        #expect(tall == height(capped))
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
        let expected = height([IslandLayout.sessionRowHeight, IslandLayout.compactWidgetHeight, IslandLayout.widgetHeight, IslandLayout.widgetHeight])
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
