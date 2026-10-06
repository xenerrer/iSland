import AppKit
import CoreGraphics
import Foundation
import IslandCore
import Testing
@testable import iSland

// The store is synchronous, so everything here runs on the main actor.

@MainActor
@Suite("SessionStore") struct SessionStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func event(_ name: String, session: String = "s", at offset: TimeInterval, tool: String? = nil,
               toolUseId: String? = nil, pid: Int? = nil, cwd: String? = "/work/proj") -> AgentEvent {
        AgentEvent(agent: "claude", sessionId: session, cwd: cwd, event: name, tool: tool, message: nil,
                   pid: pid, toolUseId: toolUseId, timestamp: t0.addingTimeInterval(offset))
    }

    func notification(_ kind: String?, session: String = "s", at offset: TimeInterval) -> AgentEvent {
        AgentEvent(agent: "claude", sessionId: session, cwd: "/work/proj", event: "Notification", tool: nil,
                   message: "Claude is waiting", kind: kind, timestamp: t0.addingTimeInterval(offset))
    }

    func withMode(_ mode: String, at offset: TimeInterval) -> AgentEvent {
        AgentEvent(agent: "claude", sessionId: "s", cwd: "/work/proj", event: "PreToolUse", tool: "Bash", message: nil,
                   permissionMode: mode, timestamp: t0.addingTimeInterval(offset))
    }

    func question(session: String = "s", at offset: TimeInterval, toolUseId: String?) -> AgentEvent {
        AgentEvent(agent: "claude", sessionId: session, cwd: "/work/proj", event: "PermissionRequest", tool: "Bash",
                   message: nil, toolUseId: toolUseId,
                   permission: PermissionPrompt(tool: "Bash", title: "Run command", detail: "ls", waitSeconds: 20),
                   timestamp: t0.addingTimeInterval(offset))
    }

    // MARK: States

    @Test func eventsDriveTheState() {
        let store = SessionStore()
        store.apply(event("SessionStart", at: 0))
        #expect(store.sessions["s"]?.state == .idle)
        store.apply(event("UserPromptSubmit", at: 1))
        #expect(store.sessions["s"]?.state == .working)
        store.apply(event("PreToolUse", at: 2, tool: "Edit"))
        #expect(store.sessions["s"]?.detail == "Edit")
        store.apply(event("Stop", at: 3))
        #expect(store.sessions["s"]?.state == .idle)
        #expect(store.sessions["s"]?.detail == "Done")
        #expect(store.sessions["s"]?.project == "proj")
    }

    @Test func overallStatePrefersWhatNeedsYou() {
        let store = SessionStore()
        store.apply(event("Stop", session: "a", at: 0))
        #expect(store.overall == .idle)
        store.apply(event("PreToolUse", session: "b", at: 1))
        #expect(store.overall == .working)
        store.apply(event("Notification", session: "c", at: 2))
        #expect(store.overall == .needsAttention)
        #expect(store.ordered.first?.id == "c")
    }

    @Test func anIdleSessionWaitingForYourNextPromptIsNotAnAlarm() {
        let store = SessionStore()
        store.apply(event("Stop", at: 0))
        store.apply(notification("idle_prompt", at: 1))
        #expect(store.sessions["s"]?.state == .idle)
        #expect(store.overall == .idle)
        #expect(store.sessions["s"]?.detail == "Waiting for your input")
    }

    @Test func permissionNotificationsDoNeedYou() {
        let store = SessionStore()
        store.apply(notification("permission_prompt", at: 0))
        #expect(store.sessions["s"]?.state == .needsAttention)
        store.apply(notification(nil, session: "other", at: 0)) // an unknown kind is treated as needing you
        #expect(store.sessions["other"]?.state == .needsAttention)
    }

    @Test func authSuccessChangesNothing() {
        let store = SessionStore()
        store.apply(event("PreToolUse", at: 0, tool: "Edit"))
        store.apply(notification("auth_success", at: 1))
        #expect(store.sessions["s"]?.state == .working)
        #expect(store.sessions["s"]?.detail == "Edit")
    }

    // MARK: Turn timing

    @Test func aTurnIsTimedFromThePromptToTheStop() {
        let store = SessionStore()
        var finished: [AgentSession] = []
        store.onTurnFinished = { finished.append($0) }
        store.apply(event("UserPromptSubmit", at: 10))
        store.apply(event("PreToolUse", at: 20, tool: "Bash")) // must not restart the clock
        #expect(store.sessions["s"]?.turnStartedAt == t0.addingTimeInterval(10))
        store.apply(event("Stop", at: 85))
        #expect(store.sessions["s"]?.lastTurnSeconds == 75)
        #expect(store.sessions["s"]?.turnStartedAt == nil)
        #expect(finished.count == 1)
        #expect(finished.first?.lastTurnSeconds == 75)
    }

    @Test func aSessionJoinedMidTurnStartsItsClockAtTheFirstEventItSees() {
        let store = SessionStore()
        store.apply(event("PostToolUse", at: 50, tool: "Edit"))
        #expect(store.sessions["s"]?.turnStartedAt == t0.addingTimeInterval(50))
    }

    @Test func aStopWithoutAKnownStartReportsNoDuration() {
        let store = SessionStore()
        var finished = 0
        store.onTurnFinished = { _ in finished += 1 }
        store.apply(event("Stop", at: 5))
        #expect(store.sessions["s"]?.lastTurnSeconds == nil)
        #expect(finished == 0)
    }

    @Test func aNewPromptClearsTheLastDuration() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", at: 0))
        store.apply(event("Stop", at: 30))
        #expect(store.sessions["s"]?.lastTurnSeconds == 30)
        store.apply(event("UserPromptSubmit", at: 40))
        #expect(store.sessions["s"]?.lastTurnSeconds == nil)
    }

    @Test func thePermissionModeIsRemembered() {
        let store = SessionStore()
        store.apply(withMode("bypassPermissions", at: 0))
        #expect(store.sessions["s"]?.permissionMode == "bypassPermissions")
        store.apply(event("Stop", at: 1)) // an event without a mode keeps the last one
        #expect(store.sessions["s"]?.permissionMode == "bypassPermissions")
    }

    @Test func questionsNotifyTheApp() {
        let store = SessionStore()
        var asked = 0
        store.onQuestion = { asked += 1 }
        store.showPreview(question(at: 1, toolUseId: "tu1")) // previews are not real questions
        #expect(asked == 0)
    }

    @Test func durationsReadAtAGlance() {
        #expect(DurationFormat.short(0) == "0s")
        #expect(DurationFormat.short(45) == "45s")
        #expect(DurationFormat.short(125) == "2m 05s")
        #expect(DurationFormat.short(3_599) == "59m 59s")
        #expect(DurationFormat.short(3_720) == "1h 02m")
        #expect(DurationFormat.short(-5) == "0s")
    }

    @Test func onlyUnusualModesGetABadge() {
        #expect(L10n.modeBadge("default") == nil)
        #expect(L10n.modeBadge(nil) == nil)
        #expect(L10n.modeBadge("somethingNew") == nil)
        let bypass = L10n.modeBadge("bypassPermissions")
        #expect(L10n.modeBadge("acceptEdits") != nil && L10n.modeBadge("plan") != nil)
        // no raw jargon: the label and the explanation say it in words
        #expect(bypass?.text != "bypass")
        #expect(bypass?.help.isEmpty == false)
    }

    @Test func everyBadgeSymbolExistsOnThisSystem() {
        for mode in ["bypassPermissions", "acceptEdits", "plan"] {
            let symbol = L10n.modeBadge(mode)?.symbol ?? ""
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
        for symbol in ["gearshape.fill", "folder.fill", "person.crop.circle", "xmark", "square.and.pencil", "timer"] {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
    }

    // MARK: The closed pill

    @Test func aFinishedJobShowsAGreenDotForAWhileAndThenTheNotchIsPlain() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", at: 0))
        #expect(store.closedStatus == .working)
        store.apply(event("Stop", at: 5))
        #expect(store.closedStatus == .idle) // just finished: a glance
        store.expireFinished()
        #expect(store.closedStatus == nil) // and then nothing, however long the session stays around
        #expect(store.sessions.count == 1)
    }

    @Test func sessionsAtRestAndEmptyStoresReportNothing() {
        let store = SessionStore()
        #expect(store.closedStatus == nil)
        store.apply(event("SessionStart", at: 0))
        #expect(store.closedStatus == nil) // started, never ran: nothing finished
        store.apply(notification("idle_prompt", at: 1))
        #expect(store.closedStatus == nil)
    }

    @Test func workAndQuestionsAlwaysShow() {
        let store = SessionStore()
        store.apply(event("PreToolUse", at: 0, tool: "Bash"))
        #expect(store.closedStatus == .working)
        store.apply(notification(nil, at: 1)) // a permission prompt in the agent's own UI
        #expect(store.closedStatus == .needsAttention)
    }

    @Test func theGreenDotWaitsForTheLastJobToFinish() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", session: "one", at: 0))
        store.apply(event("UserPromptSubmit", session: "two", at: 1))
        store.apply(event("Stop", session: "one", at: 5))
        #expect(store.closedStatus == .working) // the other one is still going
        #expect(!store.justFinished)
        store.apply(event("Stop", session: "two", at: 6))
        #expect(store.closedStatus == .idle)
    }

    @Test func newWorkCancelsTheGreenDot() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", at: 0))
        store.apply(event("Stop", at: 1))
        #expect(store.justFinished)
        store.apply(event("UserPromptSubmit", at: 2))
        #expect(!store.justFinished)
        #expect(store.closedStatus == .working)
        store.apply(event("Stop", at: 3))
        #expect(store.closedStatus == .idle)
    }

    @Test func onlyARealFinishEarnsTheGreenDot() {
        let quiet = SessionStore()
        quiet.apply(event("UserPromptSubmit", at: 0))
        quiet.settleStaleSessions(after: 10, now: t0.addingTimeInterval(100)) // went silent, e.g. interrupted
        #expect(quiet.sessions["s"]?.state == .idle)
        #expect(quiet.closedStatus == nil)

        let ended = SessionStore()
        ended.apply(event("UserPromptSubmit", at: 0))
        ended.apply(event("SessionEnd", at: 1))
        #expect(ended.closedStatus == nil)

        let completed = SessionStore()
        completed.apply(event("UserPromptSubmit", at: 0))
        completed.apply(notification("agent_completed", at: 1))
        #expect(completed.closedStatus == .idle)
    }

    @Test func aGlanceOfZeroSecondsTurnsTheGreenDotOff() {
        let store = SessionStore(doneGlance: 0)
        store.apply(event("UserPromptSubmit", at: 0))
        store.apply(event("Stop", at: 1))
        #expect(store.closedStatus == nil)
    }

    // MARK: Approving what could not be shown

    @Test func aQuestionThatNeedsReviewCannotBeAllowedByAnyRoute() {
        let store = SessionStore()
        let risky = PermissionPrompt(tool: "Bash", title: "Run command", detail: "long…", alwaysLabel: "Always allow Bash(x)", waitSeconds: 20, needsReview: true)
        store.showPreview(AgentEvent(agent: "claude", sessionId: "s", cwd: "/w", event: "PermissionRequest", tool: "Bash", message: nil,
                                     permission: risky, timestamp: t0))
        guard let id = store.requests.first?.id else { Issue.record("no question"); return }
        store.answer(id, .allow)
        store.answer(id, .allowAlways)
        #expect(store.requests.count == 1) // neither went through
        store.answer(id, .deny) // saying no, or handing it to the terminal, always works
        #expect(store.requests.isEmpty)
    }

    // MARK: Full-screen video

    @Test func theCollapsedPillStepsAsideForAFullScreenVideoButNotTheOpenIsland() {
        let main = CGMainDisplayID()
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", at: 0))
        let layout = IslandLayout(notch: CGSize(width: 186, height: 38))
        let widgets = WidgetPresence(music: true, musicPlaying: true)
        #expect(layout.size(for: store, widgets: widgets, display: main).width > 186) // working: the pill has wings
        store.hiddenPillDisplays = [main]
        #expect(layout.size(for: store, widgets: widgets, display: main) == CGSize(width: 186, height: 38)) // just the notch
        store.showPreview(question(at: 1, toolUseId: "tu")) // a question still opens the island
        #expect(layout.size(for: store, widgets: widgets, display: main).width == IslandLayout.openWidth)
    }

    // MARK: Other agents

    func agentEvent(_ agent: String, session: String, _ name: String, at offset: TimeInterval) -> AgentEvent {
        AgentEvent(agent: agent, sessionId: session, cwd: "/work/\(session)", event: name, tool: nil, message: nil,
                   transcriptPath: "/t/\(session).jsonl", timestamp: t0.addingTimeInterval(offset))
    }

    @Test func eachSessionRemembersWhichAgentRunsIt() {
        let store = SessionStore()
        store.apply(agentEvent("codex", session: "x", "UserPromptSubmit", at: 0))
        store.apply(agentEvent("gemini", session: "g", "UserPromptSubmit", at: 1))
        store.apply(agentEvent("claude", session: "c", "UserPromptSubmit", at: 2))
        #expect(store.sessions["x"]?.agent == "codex")
        #expect(store.sessions["g"]?.agent == "gemini")
        #expect(store.sessions["c"]?.agent == "claude")
        // the collapsed pill shows the spinner of whoever worked last
        #expect(store.workingAgent == "claude")
        store.apply(agentEvent("claude", session: "c", "Stop", at: 3))
        #expect(store.workingAgent == "gemini")
        store.apply(agentEvent("codex", session: "x", "PreToolUse", at: 4))
        #expect(store.workingAgent == "codex")
        store.apply(agentEvent("codex", session: "x", "Stop", at: 5))
        store.apply(agentEvent("gemini", session: "g", "Stop", at: 6))
        #expect(store.workingAgent == "claude") // nobody is working: the default
    }

    @Test func onlyClaudeChatsAreLookedUpInTheClaudeApp() {
        let store = SessionStore()
        store.apply(agentEvent("claude", session: "c", "PreToolUse", at: 0))
        store.apply(agentEvent("codex", session: "x", "PreToolUse", at: 1))
        store.apply(agentEvent("gemini", session: "g", "PreToolUse", at: 2))
        #expect(store.identityTargets().map(\.id) == ["c"])
    }

    @Test func theSpinnersAreEachAgentsOwn() {
        #expect(GeminiSpinner.frames.count == 10 && Set(GeminiSpinner.frames).count == 10) // the braille dots of cli-spinners
        #expect(GeminiSpinner.frames.allSatisfy { $0.unicodeScalars.first.map { (0x2800...0x28FF).contains($0.value) } ?? false })
    }

    // MARK: Conversations

    @Test func aQuestionOrAPlanSaysWhatTheChatIsWaitingFor() {
        for (tool, expected) in [("AskUserQuestion", "Asking you a question"), ("ExitPlanMode", "Plan ready to approve"), ("Bash", "Needs approval")] {
            let store = SessionStore()
            store.apply(AgentEvent(agent: "claude", sessionId: "s", cwd: "/w", event: "PermissionRequest", tool: tool, message: nil, timestamp: t0))
            #expect(store.sessions["s"]?.state == .needsAttention)
            #expect(store.sessions["s"]?.detail == expected)
        }
    }

    // MARK: Tidying up

    @Test func aDismissedSessionLeavesTheListAndStaysGoneUntilItStartsSomethingNew() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", at: 0))
        store.apply(event("Stop", at: 1))
        store.dismiss("s")
        #expect(store.sessions.isEmpty)
        #expect(store.closedStatus == nil)
        // chatter from the idle chat does not bring it back
        store.apply(event("PostToolUse", at: 2, tool: "Bash"))
        store.apply(notification("idle_prompt", at: 3))
        store.apply(event("Stop", at: 4))
        #expect(store.sessions.isEmpty)
        // starting something new does
        store.apply(event("UserPromptSubmit", at: 5))
        #expect(store.sessions["s"]?.state == .working)
    }

    @Test func dismissingASessionWithAQuestionHandsTheQuestionBack() {
        let store = SessionStore()
        store.showPreview(question(at: 0, toolUseId: "tu"))
        #expect(store.requests.count == 1)
        store.dismiss("s")
        #expect(store.requests.isEmpty)
        #expect(store.sessions.isEmpty)
    }

    @Test func dismissingAnUnknownSessionDoesNothing() {
        let store = SessionStore()
        store.dismiss("ghost")
        store.apply(event("PreToolUse", at: 0, tool: "Bash"))
        #expect(store.sessions["s"] != nil) // "ghost" left no tombstone behind that could hide a real session later
    }

    @Test func theNewChatPanelKeepsTheIslandOpenAndTakesTheMirrorsPlaceWhenAsked() {
        let store = SessionStore()
        store.recentFolders = ["/a", "/b"]
        store.newChatOn = true
        #expect(store.isOpen)
        #expect(store.mode == .newChat(folders: 2))
        store.mirrorOn = true
        #expect(store.mode == .mirror) // the mirror wins if both were somehow on
        store.mirrorOn = false
        store.newChatOn = false
        #expect(store.mode == .list)
        #expect(!store.isOpen)
    }

    @Test func theMirrorKeepsTheIslandOpenUntilYouGoBack() {
        let store = SessionStore()
        store.mirrorOn = true
        #expect(store.isOpen)
        store.mirrorOn = false
        #expect(!store.isOpen)
    }

    // MARK: Chat names and where a click goes

    func eventWithTranscript(_ path: String, session: String = "s", at offset: TimeInterval = 0) -> AgentEvent {
        AgentEvent(agent: "claude", sessionId: session, cwd: "/work/proj", event: "PreToolUse", tool: "Bash", message: nil,
                   pid: 4242, transcriptPath: path, timestamp: t0.addingTimeInterval(offset))
    }

    @Test func aSessionShowsItsChatNameOnceFound() {
        let store = SessionStore()
        store.apply(event("PreToolUse", at: 0, tool: "Bash"))
        #expect(store.sessions["s"]?.title == nil)
        #expect(store.displayName(forSession: "s") == "proj") // the folder stands in
        store.applyIdentities(["s": SessionIdentity(title: "Revisar contrato", chatId: "local_abc")])
        #expect(store.displayName(forSession: "s") == "Revisar contrato")
        #expect(store.sessions["s"]?.project == "proj")
        // later events keep what was learned
        store.apply(event("PostToolUse", at: 1, tool: "Bash"))
        #expect(store.sessions["s"]?.title == "Revisar contrato")
        #expect(store.sessions["s"]?.chatId == "local_abc")
    }

    @Test func identitiesOfSessionsThatLeftAreIgnored() {
        let store = SessionStore()
        store.applyIdentities(["ghost": SessionIdentity(title: "Nope", chatId: nil)])
        #expect(store.sessions.isEmpty)
        #expect(store.displayName(forSession: "ghost") == nil)
    }

    @Test func theTranscriptPathIsRememberedForTheNameLookup() {
        let store = SessionStore()
        store.apply(eventWithTranscript("/Users/me/.claude/projects/p/s.jsonl"))
        let targets = store.identityTargets()
        #expect(targets.count == 1)
        #expect(targets.first?.transcriptPath == "/Users/me/.claude/projects/p/s.jsonl")
    }

    @Test func aClickOpensTheExactChatWhenTheClaudeAppOwnsIt() {
        let store = SessionStore()
        store.apply(eventWithTranscript("/t.jsonl"))
        // not known to the Claude app (a terminal session): the app that hosts the process
        #expect(store.focusTarget(for: "s") == .hostApp(pid: 4242))
        store.applyIdentities(["s": SessionIdentity(title: "Chat", chatId: "local_990a8afe-0286-4040-924d-25f96101ee06")])
        #expect(store.focusTarget(for: "s") == .chat(URL(string: "claude://code/continue?session=local_990a8afe-0286-4040-924d-25f96101ee06")!))
    }

    @Test func aMalformedChatIdFallsBackToTheHostApp() {
        let store = SessionStore()
        store.apply(eventWithTranscript("/t.jsonl"))
        store.applyIdentities(["s": SessionIdentity(title: "Chat", chatId: "not a chat id&x=1")])
        #expect(store.focusTarget(for: "s") == .hostApp(pid: 4242))
    }

    @Test func clickingNothingGoesNowhere() {
        let store = SessionStore()
        #expect(store.focusTarget(for: "missing") == .nowhere)
        store.apply(event("PreToolUse", at: 0, tool: "Bash")) // no pid, no chat
        #expect(store.focusTarget(for: "s") == .nowhere)
    }

    @Test func handingBackAQuestionSaysChatForChatsAndTerminalForTerminals() {
        for (chatId, expected) in [(nil as String?, "Asking in terminal"), ("local_abc", "Asking in chat")] {
            let store = SessionStore()
            store.apply(event("PreToolUse", at: 0, tool: "Bash"))
            if let chatId { store.applyIdentities(["s": SessionIdentity(title: "Chat", chatId: chatId)]) }
            store.showPreview(question(at: 1, toolUseId: "tu"))
            guard let id = store.requests.first?.id else { Issue.record("no question was queued"); return }
            store.answer(id, .terminal)
            #expect(store.sessions["s"]?.detail == expected)
        }
    }

    @Test func theSettingsMenuKeepsTheIslandOpen() {
        let store = SessionStore()
        #expect(!store.isOpen)
        store.menuOpen = true
        #expect(store.isOpen)
        store.menuOpen = false
        #expect(!store.isOpen)
    }

    // MARK: Ordering

    @Test func anOlderEventNeverOverwritesANewerState() {
        let store = SessionStore()
        store.apply(event("Stop", at: 2))
        store.apply(event("PostToolUse", at: 1, tool: "Bash")) // async hook that arrived late
        #expect(store.sessions["s"]?.state == .idle)
        #expect(store.sessions["s"]?.detail == "Done")
    }

    @Test func aLateEventDoesNotResurrectAnEndedSession() {
        let store = SessionStore()
        store.apply(event("PreToolUse", at: 0))
        store.apply(event("SessionEnd", at: 5))
        store.apply(event("PostToolUse", at: 4)) // delivered after the end
        #expect(store.sessions["s"] == nil)
        store.apply(event("SessionStart", at: 6)) // the same id resumed later
        #expect(store.sessions["s"] != nil)
    }

    // MARK: Questions

    @Test func aQuestionMakesTheIslandOpenAndTheSessionNeedYou() {
        let store = SessionStore()
        store.apply(event("PreToolUse", at: 0))
        store.showPreview(question(at: 1, toolUseId: "tu1"))
        #expect(store.requests.count == 1)
        #expect(store.isOpen) // open even though nobody hovers
        #expect(store.sessions["s"]?.state == .needsAttention)
    }

    @Test func answeringShowsTheOutcomeAndClosesTheCard() {
        let store = SessionStore()
        store.showPreview(question(at: 1, toolUseId: "tu1"))
        let id = store.requests[0].id
        store.answer(id, .deny)
        #expect(store.requests.isEmpty)
        #expect(!store.isOpen)
        #expect(store.sessions["s"]?.detail == "Denied")
        store.answer(id, .allow) // answering twice is harmless
        #expect(store.sessions["s"]?.detail == "Denied")
    }

    @Test func handingBackToTheTerminalKeepsTheSessionWaiting() {
        let store = SessionStore()
        store.showPreview(question(at: 1, toolUseId: "tu1"))
        store.answer(store.requests[0].id, .terminal)
        #expect(store.sessions["s"]?.state == .needsAttention)
    }

    @Test func theToolFinishingRetiresTheMatchingCardOnly() {
        let store = SessionStore()
        store.showPreview(question(at: 1, toolUseId: "tu1"))
        store.showPreview(question(at: 1.1, toolUseId: "tu2"))
        store.apply(event("PostToolUse", at: 2, tool: "Bash", toolUseId: "tu1")) // answered in the terminal
        #expect(store.requests.count == 1)
        #expect(store.requests.first?.toolUseId == "tu2")
    }

    // Real PermissionRequest payloads carry no tool_use_id (found in a real Claude Code session).
    func realQuestion(session: String = "s", tool: String = "Bash", at offset: TimeInterval) -> AgentEvent {
        AgentEvent(agent: "claude", sessionId: session, cwd: "/work/proj", event: "PermissionRequest", tool: tool, message: nil,
                   permission: PermissionPrompt(tool: tool, title: "Run command", detail: "ls", waitSeconds: 20),
                   timestamp: t0.addingTimeInterval(offset))
    }

    @Test func aFinishedToolRetiresTheCardEvenWithoutAToolUseId() {
        let store = SessionStore()
        store.showPreview(realQuestion(at: 1))
        #expect(store.requests.first?.toolUseId == nil)
        store.apply(event("PostToolUse", at: 3, tool: "Bash")) // answered in the terminal, the tool ran
        #expect(store.requests.isEmpty)
    }

    @Test func aDifferentToolOrSessionOrAnEarlierEventDoesNotRetireIt() {
        let store = SessionStore()
        store.showPreview(realQuestion(at: 5))
        store.apply(event("PostToolUse", at: 6, tool: "Edit"))                    // another tool
        store.apply(event("PostToolUse", session: "other", at: 6, tool: "Bash"))  // another session
        store.apply(event("PostToolUse", at: 4, tool: "Bash"))                    // finished before the question began
        #expect(store.requests.count == 1)
    }

    @Test func theHomeFolderIsCalledTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(SessionStore.projectName(for: home) == "~")
        #expect(SessionStore.projectName(for: home + "/") == "~")
        #expect(SessionStore.projectName(for: home + "/iSland") == "iSland")
        #expect(SessionStore.projectName(for: nil) == "session")
    }

    @Test func theAgentMovingOnRetiresEveryCardOfThatSession() {
        let store = SessionStore()
        store.showPreview(question(session: "a", at: 1, toolUseId: "x"))
        store.showPreview(question(session: "b", at: 1, toolUseId: "y"))
        store.apply(event("Stop", session: "a", at: 2))
        #expect(store.requests.map(\.sessionId) == ["b"])
        store.apply(event("SessionEnd", session: "b", at: 3))
        #expect(store.requests.isEmpty)
    }

    @Test func aHookThatLeftWithdrawsItsCard() {
        let store = SessionStore()
        store.showPreview(question(at: 1, toolUseId: "tu1"))
        store.withdraw(store.requests[0].id)
        #expect(store.requests.isEmpty)
    }

    // MARK: Housekeeping

    @Test func silentSessionsAreEventuallyPruned() {
        let store = SessionStore()
        store.apply(event("Stop", session: "old", at: 0))
        store.apply(event("Stop", session: "new", at: 3_500))
        store.prune(olderThan: 3_600, now: t0.addingTimeInterval(4_000))
        #expect(store.sessions["old"] == nil)
        #expect(store.sessions["new"] != nil)
    }

    @Test func aDeadAgentProcessRemovesItsSession() {
        let store = SessionStore()
        store.apply(event("PreToolUse", session: "alive", at: 0, pid: 111))
        store.apply(event("PreToolUse", session: "dead", at: 0, pid: 222))
        store.showPreview(question(session: "dead", at: 1, toolUseId: "tu"))
        store.dropDeadSessions { $0 == 111 }
        #expect(store.sessions["alive"] != nil)
        #expect(store.sessions["dead"] == nil)
        #expect(store.requests.isEmpty)
    }

    @Test func aChangingPidIsNeverTrusted() {
        // Hooks run inside throwaway shells here: every event brings a new pid, and the old ones are long dead.
        let store = SessionStore()
        store.apply(event("PreToolUse", at: 0, pid: 301))
        store.apply(event("PostToolUse", at: 1, pid: 302))
        store.dropDeadSessions { _ in false }
        #expect(store.sessions["s"] != nil)
    }

    @Test func sessionsWithoutAPidAreNeverDropped() {
        let store = SessionStore()
        store.apply(event("PreToolUse", at: 0))
        store.dropDeadSessions { _ in false }
        #expect(store.sessions["s"] != nil)
    }

    @Test func aSessionSilentWhileWorkingStopsSpinningButComesBack() {
        let store = SessionStore()
        store.apply(event("PreToolUse", at: 0, tool: "Bash"))
        store.settleStaleSessions(after: 300, now: t0.addingTimeInterval(299))
        #expect(store.sessions["s"]?.state == .working) // a long build is not a hang
        store.settleStaleSessions(after: 300, now: t0.addingTimeInterval(301))
        #expect(store.sessions["s"]?.state == .idle)
        #expect(store.sessions["s"]?.turnStartedAt == nil)
        #expect(store.sessions["s"]?.detail == "No activity")
        store.apply(event("PostToolUse", at: 302, tool: "Bash"))
        #expect(store.sessions["s"]?.state == .working)
    }

    @Test func settlingNeverTouchesASessionThatNeedsYou() {
        let store = SessionStore()
        store.apply(notification("permission_prompt", at: 0))
        store.settleStaleSessions(after: 300, now: t0.addingTimeInterval(1_000))
        #expect(store.sessions["s"]?.state == .needsAttention)
    }

    @Test func thisProcessIsAlive() {
        #expect(ProcessLiveness.isAlive(Int(getpid())))
        #expect(!ProcessLiveness.isAlive(Int(Int32.max)))
    }

    @Test func onlyTheDisplayYouRestedOnOpens() {
        let store = SessionStore()
        store.focusDisplay = 1
        store.expanded = true
        #expect(store.isOpen(on: 1))
        #expect(!store.isOpen(on: 2))
        store.focusDisplay = 2 // the pointer moved to the other monitor's notch
        #expect(!store.isOpen(on: 1))
        #expect(store.isOpen(on: 2))
    }

    @Test func aFullScreenVideoHidesThePillOnThatDisplayOnly() {
        let store = SessionStore()
        let layout = IslandLayout(notch: CGSize(width: 186, height: 38), hasHardwareNotch: true)
        let widgets = WidgetPresence(music: true, calendar: false, musicPlaying: true, focus: false, focusRunning: false)
        store.hiddenPillDisplays = [1]
        #expect(layout.size(for: store, widgets: widgets, display: 1) == CGSize(width: 186, height: 38))
        #expect(layout.size(for: store, widgets: widgets, display: 2).width > 186)
    }
}

@MainActor
@Suite("Long status texts") struct LongStatusTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func anMcpToolWithALongServerIdShowsOnlyTheTool() {
        let store = SessionStore()
        store.apply(AgentEvent(agent: "claude", sessionId: "s1", cwd: "/w", event: "PostToolUse",
                               tool: "mcp__4380726e-b365-47b2-8034-d111417648ac__search_threads", message: nil, timestamp: t0))
        #expect(store.sessions["s1"]?.detail == "search_threads done")
    }

    @Test func aHugeMessageIsCutToWhatARowCanShow() {
        let store = SessionStore()
        store.apply(AgentEvent(agent: "claude", sessionId: "s2", cwd: "/w", event: "Notification", tool: nil,
                               message: String(repeating: "m", count: 400), kind: "permission_prompt", timestamp: t0))
        #expect((store.sessions["s2"]?.detail.count ?? 0) <= 48)
    }
}
