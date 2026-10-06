import CoreGraphics
import Foundation
import IslandCore

enum SessionState { case working, needsAttention, idle }

struct AgentSession: Identifiable {
    let id: String
    /// Which agent runs it: "claude", "codex" or "gemini" (the spinner is each one's own).
    var agent = "claude"
    var project: String
    var state: SessionState
    var detail: String
    var updated: Date
    /// The agent process, as seen by the hook. Only trusted for liveness while it never changes (see `pidIsStable`).
    var pid: Int?
    /// False once two events of the same session reported different pids: the hook then runs inside a throwaway
    /// shell, and a dead pid says nothing about the agent.
    var pidIsStable = true
    /// "default", "acceptEdits", "plan", "bypassPermissions"...
    var permissionMode: String?
    /// When the current turn began; nil while idle.
    var turnStartedAt: Date?
    /// How long the last finished turn took.
    var lastTurnSeconds: Int?
    /// The name of the chat, as the Claude app (or `/rename`) shows it. nil until found; the folder name stands in.
    var title: String?
    /// The Claude app's own id for this chat (`local_...`). Only chats that live in the Claude app have one.
    var chatId: String?
    /// Where the agent writes this conversation; the name can be read from there when the Claude app does not know it.
    var transcriptPath: String?
}

/// What the island learned about a session beyond its events.
struct SessionIdentity: Equatable {
    var title: String?
    var chatId: String?
}

/// Where a click on a session should take you.
enum FocusTarget: Equatable {
    /// The chat itself, in the Claude app.
    case chat(URL)
    /// The app that hosts the session (Terminal, VS Code...), found from the agent's process.
    case hostApp(pid: Int)
    case nowhere
}

/// A question an agent is waiting on, shown as a card in the island.
struct PendingRequest: Identifiable {
    let id: UUID
    let sessionId: String
    let project: String
    let toolUseId: String?
    let prompt: PermissionPrompt
    /// When the hook started waiting (the event's own timestamp).
    let receivedAt: Date
    /// When the hook gives up and the agent asks in its own terminal.
    let deadline: Date
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [String: AgentSession] = [:]
    @Published private(set) var requests: [PendingRequest] = []
    /// True while the pointer is over the island.
    @Published var expanded = false
    /// True while the global approval shortcuts are registered, so the card can advertise them.
    @Published var hotkeysActive = false
    /// True while the settings menu is open: the island stays put even though the pointer has left it.
    @Published var menuOpen = false
    /// True for a few seconds after the last running job finished. The collapsed pill shows a green dot for that long
    /// and then goes back to being a plain notch.
    @Published private(set) var justFinished = false
    /// With several displays there is one island per display, but only the one you last rested the pointer on is the "open" one
    /// (a question, the mirror and the menus open there too).
    @Published var focusDisplay: CGDirectDisplayID = CGMainDisplayID()
    /// The display whose pill the pointer is on right now but has not opened yet.
    @Published var hoverDisplay: CGDirectDisplayID?
    /// Displays showing a full-screen video: their collapsed pill steps aside.
    @Published var hiddenPillDisplays: Set<CGDirectDisplayID> = []

    /// The glass of an island is alive while it is open and for a moment after it closes (so it can dissolve with the shrinking
    /// container). A glass effect samples what is behind it all the time, even when invisible: it must not outlive that.
    @Published private(set) var glassDisplays: Set<CGDirectDisplayID> = []
    private var glassTimers: [CGDirectDisplayID: Timer] = [:]

    func openStateChanged(_ open: Bool, on display: CGDirectDisplayID) {
        glassTimers[display]?.invalidate()
        if open {
            glassDisplays.insert(display)
        } else {
            glassTimers[display] = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.glassDisplays.remove(display) }
            }
        }
    }

    func isOpen(on display: CGDirectDisplayID) -> Bool { display == focusDisplay && isOpen }

    /// The camera mirror is showing in place of the usual island.
    @Published var mirrorOn = false
    /// A meeting to join from the mirror: set when the mirror was opened from a calendar card.
    @Published var mirrorJoinURL: URL?
    /// The "new chat" panel (recent folders) is showing.
    @Published var newChatOn = false
    /// The pomodoro setup panel is showing.
    @Published var pomodoroSetupOn = false
    @Published var recentFolders: [String] = []

    /// A turn just finished (the session carries its duration). The app uses it for the optional sound.
    var onTurnFinished: ((AgentSession) -> Void)?
    /// A new question was queued by a real hook.
    var onQuestion: (() -> Void)?

    /// How long the green "finished" dot stays beside the notch. 0 never shows it.
    private let doneGlance: TimeInterval
    private var finishedTimer: Timer?

    init(doneGlance: TimeInterval = 8) {
        self.doneGlance = doneGlance
    }

    private var responders: [UUID: Responder] = [:]
    /// Session id -> when it ended. Async hooks can deliver a late event after SessionEnd;
    /// without this it would resurrect the session.
    private var ended: [String: Date] = [:]
    /// Sessions the user removed from the list. Late chatter from an idle chat (a Stop, an idle reminder) must not
    /// bring them back; starting something new does.
    private var dismissed: [String: Date] = [:]
    private static let revivingEvents: Set<String> = ["UserPromptSubmit", "PermissionRequest", "SessionStart"]

    /// The island shows its full content while hovered, and for as long as a question is waiting.
    var isOpen: Bool { expanded || menuOpen || mirrorOn || newChatOn || pomodoroSetupOn || !requests.isEmpty }

    var mode: IslandMode {
        if mirrorOn { return .mirror }
        if newChatOn { return .newChat(folders: recentFolders.count) }
        if pomodoroSetupOn { return .pomodoro }
        return .list
    }

    var ordered: [AgentSession] {
        sessions.values.sorted { ($0.state == .needsAttention ? 0 : 1, $1.updated) < ($1.state == .needsAttention ? 0 : 1, $0.updated) }
    }

    /// What the collapsed pill reports: work in progress and questions always, a finished job for a few seconds, and
    /// otherwise nothing, so an island with nothing to say is just the notch.
    var closedStatus: SessionState? {
        guard !sessions.isEmpty else { return nil }
        switch overall {
        case .needsAttention, .working: return overall
        case .idle: return justFinished ? .idle : nil
        }
    }

    /// Whose spinner the collapsed pill shows: the agent that worked most recently.
    var workingAgent: String {
        sessions.values.filter { $0.state == .working }.max { $0.updated < $1.updated }?.agent ?? "claude"
    }

    var overall: SessionState {
        if sessions.values.contains(where: { $0.state == .needsAttention }) { return .needsAttention }
        if sessions.values.contains(where: { $0.state == .working }) { return .working }
        return .idle
    }

    /// The folder name, or "~" for the home folder (whose name is only the user's account name).
    static func projectName(for cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "session" }
        if URL(fileURLWithPath: cwd).standardized.path == FileManager.default.homeDirectoryForCurrentUser.standardized.path { return "~" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    // MARK: - Events

    func apply(_ e: AgentEvent) {
        if e.event == "SessionEnd" {
            retireRequests(forSession: e.sessionId)
            sessions[e.sessionId] = nil
            ended[e.sessionId] = e.timestamp
            return
        }
        if let endedAt = ended[e.sessionId] {
            if e.timestamp <= endedAt { return }
            ended[e.sessionId] = nil // a resumed session reuses its id
        }
        if let removedAt = dismissed[e.sessionId] {
            guard Self.revivingEvents.contains(e.event), e.timestamp > removedAt else { return }
            dismissed[e.sessionId] = nil
        }
        // Async hooks can arrive out of order: an older event must never overwrite a newer state.
        if let current = sessions[e.sessionId], e.timestamp < current.updated { return }

        // Events that prove the agent moved past a question we were still showing.
        switch e.event {
        case "PostToolUse", "PostToolUseFailure", "PermissionDenied":
            if let id = e.toolUseId { retireRequests(forToolUse: id) }
            // Real PermissionRequest payloads carry no tool_use_id, so also match on session + tool.
            retireRequestsWithoutId(forSession: e.sessionId, tool: e.tool, finishedAt: e.timestamp)
        case "Stop", "UserPromptSubmit":
            retireRequests(forSession: e.sessionId)
        default:
            break
        }

        var s = sessions[e.sessionId] ?? AgentSession(
            id: e.sessionId,
            project: Self.projectName(for: e.cwd),
            state: .idle, detail: "", updated: e.timestamp)
        s.agent = e.agent
        if let pid = e.pid {
            if let known = s.pid, known != pid { s.pidIsStable = false }
            s.pid = pid
        }
        if let mode = e.permissionMode { s.permissionMode = mode }
        if let path = e.transcriptPath { s.transcriptPath = path }
        var finishedTurn = false
        switch e.event {
        case "SessionStart":
            s.state = .idle; s.detail = "Started"; s.turnStartedAt = nil
        case "Stop":
            s.state = .idle; s.detail = "Done"
            if let start = s.turnStartedAt {
                s.lastTurnSeconds = max(0, Int(e.timestamp.timeIntervalSince(start)))
                finishedTurn = true
            }
            s.turnStartedAt = nil
        case "UserPromptSubmit":
            s.state = .working; s.detail = "Thinking…"; s.turnStartedAt = e.timestamp; s.lastTurnSeconds = nil
        case "PreToolUse":
            s.state = .working; s.detail = e.tool.map(ToolName.display) ?? "Working"
            if s.turnStartedAt == nil { s.turnStartedAt = e.timestamp }
        case "PostToolUse":
            s.state = .working; s.detail = e.tool.map { "\(ToolName.display($0)) done" } ?? "Working"
            if s.turnStartedAt == nil { s.turnStartedAt = e.timestamp }
        case "PermissionRequest":
            s.state = .needsAttention
            // Questions and plans are conversations, not yes/no cards: say what the chat is waiting for, and a click goes there.
            switch e.tool {
            case "AskUserQuestion": s.detail = "Asking you a question"
            case "ExitPlanMode": s.detail = "Plan ready to approve"
            default: s.detail = ToolName.clipped(e.permission?.title ?? e.message ?? "Needs approval", to: 48)
            }
        case "Notification":
            switch e.kind {
            case "idle_prompt": s.state = .idle; s.detail = "Waiting for your input" // finished, not an alarm
            case "agent_completed": s.state = .idle; s.detail = "Done"
            case "auth_success": break
            default: s.state = .needsAttention; s.detail = ToolName.clipped(e.message ?? "Needs you", to: 48) // permission_prompt, elicitation_dialog...
            }
        default: break
        }
        s.updated = e.timestamp
        sessions[e.sessionId] = s
        if finishedTurn { onTurnFinished?(s) }
        // A status much longer than a row can show: it is cut, and noted here so a layout glitch can be traced to it.
        if e.tool.map({ ToolName.display($0).hasSuffix("…") }) == true || e.message.map({ $0.count > 48 }) == true {
            IslandLog.write("anomaly", "long status text cut: tool=\(e.tool?.count ?? 0) chars, message=\(e.message?.count ?? 0) chars, event=\(e.event)")
        }
        noteFinish(after: e)
    }

    /// Takes a session off the list (to tidy up when many chats are open). It comes back by itself the moment that
    /// chat starts something new.
    func dismiss(_ sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        retireRequests(forSession: sessionId)
        sessions[sessionId] = nil
        dismissed[sessionId] = session.updated // event time, like everything else here: later events may revive it
        if overall != .idle || sessions.isEmpty { cancelFinished() }
    }

    // MARK: - The "finished" glance

    /// A real finish (`Stop`, or the agent saying it completed) that leaves nothing else running is worth a glance.
    /// Settling a silent session, ending one or dropping a dead one is not: nothing was completed.
    private func noteFinish(after e: AgentEvent) {
        if overall != .idle { cancelFinished(); return }
        if e.event == "Stop" || (e.event == "Notification" && e.kind == "agent_completed") { markFinished() }
    }

    private func markFinished() {
        guard doneGlance > 0 else { return }
        justFinished = true
        finishedTimer?.invalidate()
        finishedTimer = Timer.scheduledTimer(withTimeInterval: doneGlance, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireFinished() }
        }
    }

    private func cancelFinished() {
        finishedTimer?.invalidate()
        finishedTimer = nil
        if justFinished { justFinished = false }
    }

    /// The glance is over. Called by the timer.
    func expireFinished() {
        finishedTimer?.invalidate()
        finishedTimer = nil
        if justFinished { justFinished = false }
    }

    // MARK: - Questions

    /// A hook is waiting for an answer on `responder`.
    func enqueue(_ e: AgentEvent, id: UUID, responder: Responder) {
        guard let prompt = e.permission else { responder.reply(DecisionReply(.terminal)); return }
        apply(e)
        onQuestion?()
        responders[id] = responder
        requests.append(PendingRequest(
            id: id, sessionId: e.sessionId,
            project: sessions[e.sessionId]?.project ?? Self.projectName(for: e.cwd),
            toolUseId: e.toolUseId, prompt: prompt, receivedAt: e.timestamp,
            deadline: Date().addingTimeInterval(TimeInterval(prompt.waitSeconds))))
    }

    /// The user chose. Tells the waiting hook, drops the card, and shows the outcome until the agent says more.
    func answer(_ id: UUID, _ decision: Decision) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return }
        // The one choke point for every way of answering (buttons and shortcuts): a question the card could not show in
        // full cannot be allowed from here.
        if requests[index].prompt.needsReview, decision == .allow || decision == .allowAlways { return }
        let request = requests.remove(at: index)
        responders.removeValue(forKey: id)?.reply(DecisionReply(decision))
        guard var session = sessions[request.sessionId] else { return }
        switch decision {
        case .allow, .allowAlways: session.state = .working; session.detail = "Approved"
        case .deny: session.state = .working; session.detail = "Denied"
        case .terminal: session.state = .needsAttention; session.detail = session.chatId == nil ? "Asking in terminal" : "Asking in chat"
        }
        sessions[request.sessionId] = session
    }

    /// The hook went away without an answer: it timed out, was killed, or the user answered in the terminal.
    func withdraw(_ id: UUID) {
        responders.removeValue(forKey: id)
        requests.removeAll { $0.id == id }
    }

    /// Snapshots and demos: a card with nobody waiting behind it.
    func showPreview(_ e: AgentEvent) {
        guard let prompt = e.permission else { return }
        apply(e)
        requests.append(PendingRequest(
            id: UUID(), sessionId: e.sessionId, project: sessions[e.sessionId]?.project ?? "session",
            toolUseId: e.toolUseId, prompt: prompt, receivedAt: e.timestamp,
            deadline: Date().addingTimeInterval(TimeInterval(prompt.waitSeconds))))
    }

    /// The agent moved on without our answer: release the waiting hook and drop the card.
    private func retire(_ request: PendingRequest) {
        responders.removeValue(forKey: request.id)?.reply(DecisionReply(.terminal))
        requests.removeAll { $0.id == request.id }
    }

    private func retireRequests(forSession sessionId: String) {
        for request in requests where request.sessionId == sessionId { retire(request) }
    }

    /// A request that carries no tool_use_id is matched to the call that just finished by session and tool name.
    /// If two calls of the same tool overlap, a card may leave early; its hook then hands the question back to the
    /// terminal, which is the safe outcome.
    private func retireRequestsWithoutId(forSession sessionId: String, tool: String?, finishedAt: Date) {
        guard let tool else { return }
        for request in requests
        where request.toolUseId == nil && request.sessionId == sessionId && request.prompt.tool == tool
            && request.receivedAt <= finishedAt { retire(request) }
    }

    private func retireRequests(forToolUse toolUseId: String) {
        for request in requests where request.toolUseId == toolUseId { retire(request) }
    }

    // MARK: - Names and focus

    /// The sessions whose chat names are worth looking up, with the file that may hold the name.
    func identityTargets() -> [(id: String, transcriptPath: String?)] {
        sessions.values.filter { $0.agent == AgentKind.claude.rawValue }.map { ($0.id, $0.transcriptPath) } // the Claude app's chats
    }

    /// Remembers what was found about each session. Sessions that went away in the meantime are ignored, and a
    /// session is only republished when something actually changed.
    @discardableResult
    func applyIdentities(_ identities: [String: SessionIdentity]) -> Int {
        var changed = 0
        for (id, identity) in identities {
            guard var session = sessions[id], session.title != identity.title || session.chatId != identity.chatId else { continue }
            session.title = identity.title
            session.chatId = identity.chatId
            sessions[id] = session
            changed += 1
        }
        return changed
    }

    /// The chat's name, or the folder it works in when the name is not known.
    func displayName(forSession id: String) -> String? {
        sessions[id].map { $0.title ?? $0.project }
    }

    func focusTarget(for sessionId: String) -> FocusTarget {
        guard let session = sessions[sessionId] else { return .nowhere }
        if let chatId = session.chatId, let link = ClaudeDesktop.deepLink(toChat: chatId) { return .chat(link) }
        if let pid = session.pid { return .hostApp(pid: pid) }
        return .nowhere
    }

    /// Takes you to the session: the exact chat when it lives in the Claude app, otherwise the app that hosts it.
    func focus(_ sessionId: String) {
        switch focusTarget(for: sessionId) {
        case .chat(let link):
            ProcessTree.open(chat: link)
        case .hostApp(let pid):
            if let app = ProcessTree.hostApplication(of: pid) { ProcessTree.bringForward(app) }
        case .nowhere:
            break
        }
    }

    // MARK: - Housekeeping

    /// Claude Code does not emit `Stop` when you interrupt a response, and a long tool call is silent for minutes, so
    /// a session that has been "working" with no event at all for `interval` is shown as inactive instead of
    /// spinning forever. Any new event brings it back.
    func settleStaleSessions(after interval: TimeInterval = 300, now: Date = Date()) {
        for (id, session) in sessions where session.state == .working && now.timeIntervalSince(session.updated) > interval {
            var settled = session
            settled.state = .idle
            settled.detail = "No activity"
            settled.turnStartedAt = nil
            sessions[id] = settled
        }
    }

    /// Removes sessions whose agent process is gone (closed tab, crash, kill) without waiting for the long timeout.
    func dropDeadSessions(isAlive: (Int) -> Bool = ProcessLiveness.isAlive) {
        for (id, session) in sessions {
            guard session.pidIsStable, let pid = session.pid, !isAlive(pid) else { continue }
            retireRequests(forSession: id)
            sessions[id] = nil
            ended[id] = Date()
        }
    }

    /// Drops sessions that have been silent for `interval`. A live session that comes back simply reappears.
    /// Also a safety net for cards whose hook vanished without telling us.
    func prune(olderThan interval: TimeInterval, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-interval)
        for (id, session) in sessions where session.updated < cutoff { sessions[id] = nil }
        ended = ended.filter { $0.value > now.addingTimeInterval(-3600) }
        dismissed = dismissed.filter { $0.value > now.addingTimeInterval(-24 * 3600) }
        for request in requests where request.deadline < now.addingTimeInterval(-5) { withdraw(request.id) }
    }
}

enum ProcessLiveness {
    /// Signal 0 only checks that the process exists. EPERM means it exists but belongs to someone else.
    static func isAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return true }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }
}
