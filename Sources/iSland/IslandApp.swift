import AppKit
import Combine
import ImageIO
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import IslandCore

/// Never becomes key: clicking the island must not take the keyboard away from the app you are typing in.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The first click on a panel that is not key still has to reach the buttons.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// One island: the panel on one display, with its own layout (a notch, or none) and pointer tracking.
@MainActor
final class Island {
    let display: CGDirectDisplayID
    let panel: IslandPanel
    var hover: HoverController?
    var layout: IslandLayout?
    init(display: CGDirectDisplayID, panel: IslandPanel) {
        self.display = display
        self.panel = panel
    }

    func close() {
        hover?.stop()
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore(doneGlance: Appearance.doneGlance)
    let appearance = Appearance()
    lazy var widgets = Widgets(appearance: appearance)
    lazy var identities = SessionIdentityResolver(store: store)
    lazy var currentChat = CurrentChatTracker(store: store)
    lazy var notifier = Notifier(store: store, appearance: appearance, tracker: currentChat)
    let mirror = MirrorManager()
    private let fullscreen = FullscreenWatcher()
    private let guideWindow = OnboardingWindow()
    private lazy var guideModel = OnboardingModel(calendar: widgets.calendar)
    var panel: NSPanel! // the single panel of the development modes (demo, snapshots, measurements)
    var islands: [Island] = []
    var server: SocketServer?
    var statusMenu: StatusMenu?
    var hotkeys: ApprovalHotkeys?
    var pruneTimer: Timer?
    var layout = IslandLayout(notch: CGSize(width: 200, height: 32), hasHardwareNotch: false)
    var subscriptions = Set<AnyCancellable>()
    private var signalSources: [DispatchSourceSignal] = []

    /// `kill` and `pkill` send SIGTERM, which would skip applicationWillTerminate: the media adapter would be left running
    /// and the socket file behind. Turn those signals into an ordinary quit.
    private func quitOnSignals() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let args = CommandLine.arguments
        quitOnSignals()

        // `--headless`: the socket server and session store only, no window. For end-to-end tests.
        if args.contains("--headless") {
            startServer(args: args)
            return
        }

        // `--whois <pid>`: which app hosts that process? Used to check the "click a session to focus it" lookup.
        if let i = args.firstIndex(of: "--whois"), i + 1 < args.count, let pid = Int(args[i + 1]) {
            let app = ProcessTree.hostApplication(of: pid)
            print(app.map { "\($0.localizedName ?? "?") (\($0.bundleIdentifier ?? "?"), pid \($0.processIdentifier))" } ?? "no host application found")
            NSApp.terminate(nil)
            return
        }

        // `--guide-shot <png> [--step N]`: render a step of the first-run guide to an image and quit.
        if let i = args.firstIndex(of: "--guide-shot"), i + 1 < args.count {
            let model = OnboardingModel(calendar: CalendarManager())
            model.step = args.firstIndex(of: "--step").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 0
            let renderer = ImageRenderer(content: OnboardingView(model: model).environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let image = renderer.cgImage, let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[i + 1]) as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
            NSApp.terminate(nil)
            return
        }

        // `--chat-of <session id>`: the Claude app chat behind a Claude Code session id, and the link that opens it.
        if let i = args.firstIndex(of: "--chat-of"), i + 1 < args.count {
            let id = args[i + 1]
            let started = Date()
            let chat = DesktopChatIndex().chats(forSessions: [id])[id]
            let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
            if let chat {
                print("title: \(chat.title ?? "-")\nchat id: \(chat.localId)\narchived: \(chat.isArchived)")
                print("link: \(ClaudeDesktop.deepLink(toChat: chat.localId)?.absoluteString ?? "-")")
            } else {
                print("no chat in the Claude app has that session id")
            }
            print("looked in \(milliseconds) ms")
            NSApp.terminate(nil)
            return
        }

        // `--icon <png>`: write the 1024 px app icon master and quit.
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
            NSLog(AppIconArt.write(to: args[i + 1]) ? "iSland: icon written" : "iSland: icon failed")
            NSApp.terminate(nil)
            return
        }

        guard let screen = notchScreen() else { return }
        layout = Self.layout(for: screen)
        if args.contains("--no-notch") { layout = IslandLayout(notch: CGSize(width: 150, height: 24), hasHardwareNotch: false) } // dev flag: pretend there is no notch

        // `--snapshot <png> [--closed] [--request]`: render a demo state to an image and quit, without touching the screen.
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            seedDemo(expanded: !args.contains("--closed"), withRequest: args.contains("--request"))
            renderSnapshot(to: args[i + 1])
            NSApp.terminate(nil)
            return
        }

        // `--measure-animation`: open and close the real island a few times and report how smoothly it moves.
        if args.contains("--measure-animation") {
            runAnimationMeasurement(on: screen)
            return
        }

        // `--close-frames <dir>`: capture the real island at successive moments of closing, to see what is left behind.
        if let i = args.firstIndex(of: "--close-frames"), i + 1 < args.count {
            runCloseFrames(into: args[i + 1], screen: screen, opening: args.contains("--opening"))
            return
        }

        // `--selfshot <png> [--backdrop light|dark|busy] [--request] [--closed]`: draw the real island over a synthetic
        // wallpaper and capture it. Shows what Liquid Glass really looks like, without any permission.
        if let i = args.firstIndex(of: "--selfshot"), i + 1 < args.count {
            runSelfShot(to: args[i + 1], args: args, screen: screen)
            return
        }

        if args.contains("--demo") {
            createPanel(on: screen)
            seedDemo(expanded: !args.contains("--closed"), withRequest: args.contains("--request")) // pinned open (or closed with --closed): no pointer tracking
        } else {
            rebuildIslands()
            appearance.$hoverDelay.sink { [weak self] seconds in self?.islands.forEach { $0.hover?.openDelay = seconds } }.store(in: &subscriptions)
            appearance.$displayChoice.dropFirst().removeDuplicates()
                .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildIslands() } }
                .store(in: &subscriptions)
        }

        // Clicks land on the island only while the pointer is over it; everywhere else they reach the windows below.
        Publishers.CombineLatest(store.$expanded, store.$requests)
            .sink { [weak self] _, _ in
                // @Published fires before the value changes, so look again on the next turn of the run loop.
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.islands.isEmpty { self.panel?.ignoresMouseEvents = !self.store.isOpen }
                    self.islands.forEach { $0.hover?.refreshInteractivity() }
                }
            }
            .store(in: &subscriptions)

        // Step aside while another app shows a video in full screen: something is playing and a window covers the screen.
        // The watcher only runs while its answer can matter (music playing and the setting on): it is the app's biggest idle wake-up.
        Publishers.CombineLatest(widgets.music.$state.map(\.isPlaying), appearance.$hideInFullscreenVideo)
            .map { $0 && $1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [fullscreen] on in if on { fullscreen.start() } else { fullscreen.stop() } }
            .store(in: &subscriptions)
        Publishers.CombineLatest3(fullscreen.$fullscreenDisplays, widgets.music.$state.map(\.isPlaying), appearance.$hideInFullscreenVideo)
            .map { displays, playing, enabled in playing && enabled ? displays : [] }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [store] hidden in store.hiddenPillDisplays = hidden }
            .store(in: &subscriptions)

        // The camera runs only while the mirror shows.
        store.$mirrorOn
            .removeDuplicates()
            .sink { [mirror] on in if on { mirror.start() } else { mirror.stop() } }
            .store(in: &subscriptions)

        // Follow the screen when its resolution changes or a display is plugged in.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleScreenChanged() }
        }

        appearance.$hideFromCapture
            .sink { [weak self] hide in
                let type: NSWindow.SharingType = hide ? .none : .readOnly
                self?.panel?.sharingType = type
                self?.islands.forEach { $0.panel.sharingType = type }
            }
            .store(in: &subscriptions)

        store.onHandBack = { [store] sessionId in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { store.focus(sessionId) }
        }
        // A question opens on the display the pointer is on, not on one you may not be looking at.
        store.$requests.map { $0.first?.id }.removeDuplicates()
            .sink { [weak self] id in
                guard id != nil else { return }
                DispatchQueue.main.async { self?.focusDisplayUnderPointer() }
            }
            .store(in: &subscriptions)
        store.onTurnFinished = { [appearance, notifier, store, currentChat] session in
            if appearance.sounds, (session.lastTurnSeconds ?? 0) >= AlertPolicy.minimumTurnSeconds { NSSound(named: "Glass")?.play() }
            notifier.finished(session)
            // A reminder under the notch, for the one you would otherwise forget: a long job, in a chat you are not looking at.
            if appearance.notify, AlertPolicy.shouldAnnounceFinish(turnSeconds: session.lastTurnSeconds,
                                                                    userIsLooking: currentChat.isLooking(at: session.id)) {
                store.showToast(.init(sessionId: session.id, title: session.title ?? session.project, seconds: session.lastTurnSeconds ?? 0))
            }
        }
        store.onQuestion = { [appearance, store, notifier] sessionId in
            if appearance.sounds { NSSound(named: "Tink")?.play() }
            notifier.needsYou(sessionId: sessionId, prompt: store.requests.last?.prompt.title ?? "Needs approval")
            // VoiceOver users hear that a decision is waiting (it has about 20 seconds).
            let who = store.displayName(forSession: sessionId) ?? store.sessions[sessionId]?.project ?? ""
            AccessibilityNotification.Announcement(L10n.t("Needs your approval") + ", " + who).post()
        }
        notifier.onShowIsland = { [weak self] in
            self?.store.expanded = true
            self?.focusedHover?.hold(for: 8)
        }
        appearance.$notify.dropFirst().removeDuplicates().filter { $0 }
            .sink { [notifier] _ in notifier.requestAuthorization() }
            .store(in: &subscriptions)

        statusMenu = StatusMenu(appearance: appearance, widgets: widgets)
        statusMenu?.openPomodoroSetup = { [store] in store.pomodoroSetupOn = true }
        statusMenu?.openGuide = { [weak self] in self?.showGuide() }
        statusMenu?.clearHistory = { [store] in store.clearHistory() }
        if !OnboardingModel.isDone { DispatchQueue.main.async { [weak self] in self?.showGuide() } } // the first run

        // Shortcuts exist only while a question is waiting.
        let hotkeys = ApprovalHotkeys { [store] decision in
            if let id = store.requests.first?.id { store.answer(id, decision) }
        }
        self.hotkeys = hotkeys
        store.$requests
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [store] pending in
                if pending { hotkeys.activate() } else { hotkeys.deactivate() }
                store.hotkeysActive = pending && hotkeys.isActive
            }
            .store(in: &subscriptions)

        pruneTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.dropDeadSessions()
                self?.store.settleStaleSessions()
                self?.store.prune(olderThan: 6 * 3600)
            }
        }
        pruneTimer?.tolerance = 5 // housekeeping: let the system batch the wake-up with others

        if let helper = HookBinary.bundledHelperURL() { HookBinary.refreshIfInstalled(from: helper) }
        widgets.focus.onPhaseEnded = { phase in NSSound(named: phase.isBreak ? "Hero" : "Glass")?.play() }
        if !args.contains("--demo") { // demos show made-up music, events and chat names instead
            widgets.start()
            identities.start()
            currentChat.start()
            notifier.start()
            startHistory()
        }
        startServer(args: args)
        ensureLaunchAtLogin()
    }

    // MARK: What you were working on

    private var historySaver: AnyCancellable?

    /// Loads the remembered projects and keeps them on disk: every live session is noted a few seconds after things change,
    /// and again when the app quits.
    private func startHistory() {
        var loaded = RecentHistory.load(from: IslandPaths.recentURL)
        loaded.prune()
        store.loadHistory(loaded)
        store.$sessions
            .dropFirst()
            .debounce(for: .seconds(3), scheduler: DispatchQueue.main)
            .sink { [store] _ in store.recordHistory() }
            .store(in: &subscriptions)
        historySaver = store.$history
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { history in history.save(to: IslandPaths.recentURL) }
    }

    // MARK: Login item

    /// iSland starts with the Mac: it turns its own login item on at launch, unless you switched it off in the menu. (A
    /// development build, which lives under `.build`, never registers itself: it would take the place of the installed app.)
    private func ensureLaunchAtLogin() {
        guard !UserDefaults.standard.bool(forKey: LoginItem.optOutKey), !Bundle.main.bundlePath.contains("/.build/"),
              Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
            IslandLog.write("login", "registered the login item (status \(service.status.rawValue))")
        } catch {
            IslandLog.write("anomaly", "could not register the login item: \(error.localizedDescription)")
        }
    }

    // MARK: Window

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private static func layout(for screen: NSScreen) -> IslandLayout {
        let geometry = NotchGeometry.current(for: screen)
        return IslandLayout(notch: geometry.size, hasHardwareNotch: geometry.hasHardwareNotch)
    }

    /// A fixed, transparent panel bigger than any island state; the island is drawn inside it.
    private func panelFrame(on screen: NSScreen) -> NSRect {
        let size = CGSize(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight)
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func configure(_ panel: IslandPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true // click-through while collapsed; turned off while the island is open
        panel.sharingType = appearance.hideFromCapture ? .none : .readOnly
    }

    /// The single panel of the development modes.
    private func createPanel(on screen: NSScreen) {
        let made = IslandPanel(contentRect: panelFrame(on: screen), styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        configure(made)
        panel = made
        if let id = screen.displayID { store.focusDisplay = id }
        installContent(in: made, layout: layout, display: store.focusDisplay)
        made.orderFrontRegardless()
    }

    private func installContent(in panel: NSPanel, layout: IslandLayout, display: CGDirectDisplayID) {
        let host = IslandHostingView(rootView: IslandView(
            store: store, appearance: appearance, widgets: widgets, mirror: mirror, layout: layout, display: display,
            onSettings: { [weak self] in self?.showSettings() }))
        host.sizingOptions = [] // the panel has a fixed frame: no re-measuring of the root view on every update
        panel.contentView = host
    }

    private func layoutFor(_ screen: NSScreen) -> IslandLayout {
        var layout = CommandLine.arguments.contains("--no-notch") ? IslandLayout(notch: CGSize(width: 150, height: 24), hasHardwareNotch: false) : Self.layout(for: screen)
        // Beside a screen that has a notch, one without gets a virtual one, so there is something to point at.
        if !layout.hasHardwareNotch, NSScreen.screens.count > 1, NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 }) { layout.alwaysDrawsPill = true }
        return layout
    }

    /// Puts an island on every display the setting asks for, and takes them off the others. Runs at launch, when a display
    /// is plugged in or out or changes resolution, and when the setting changes.
    private func rebuildIslands() {
        let screens = NSScreen.screens
        let targets = appearance.displayChoice.targets(available: screens.compactMap(\.displayID))
        for gone in islands where !targets.contains(gone.display) { gone.close() }
        islands.removeAll { !targets.contains($0.display) }
        for id in targets {
            guard let screen = screens.first(where: { $0.displayID == id }) else { continue }
            let layout = layoutFor(screen)
            if let island = islands.first(where: { $0.display == id }) {
                // Only touch what really changed: re-creating the view mid-animation would throw its state away.
                let frame = panelFrame(on: screen)
                if island.panel.frame != frame { island.panel.setFrame(frame, display: true) }
                if island.layout != layout {
                    installContent(in: island.panel, layout: layout, display: id)
                    island.layout = layout
                }
                island.hover?.update(layout: layout, screenFrame: screen.frame)
                continue
            }
            let panel = IslandPanel(contentRect: panelFrame(on: screen), styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
            configure(panel)
            installContent(in: panel, layout: layout, display: id)
            let island = Island(display: id, panel: panel)
            island.layout = layout
            let hover = HoverController(store: store, widgets: widgets, layout: layout, screenFrame: screen.frame, display: id)
            hover.openDelay = appearance.hoverDelay
            hover.setInteractive = { [weak panel] interactive in panel?.ignoresMouseEvents = !interactive }
            hover.start()
            island.hover = hover
            islands.append(island)
            panel.orderFrontRegardless()
        }
        if !targets.contains(store.focusDisplay), let first = targets.first {
            store.expanded = false
            store.focusDisplay = first
        }
        NSLog("iSland: %d island(s) on %d display(s)", islands.count, screens.count)
        IslandLog.write("display", "islands=\(islands.count) displays=\(screens.count) choice=\(appearance.displayChoice.raw) focus=\(store.focusDisplay)")
    }

    private var screenWork: DispatchWorkItem?

    /// A display change arrives as a burst of notifications: act once, when it has settled.
    private func scheduleScreenChanged() {
        screenWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.screenChanged() } }
        screenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func focusDisplayUnderPointer() {
        let point = NSEvent.mouseLocation
        guard let id = NSScreen.screens.first(where: { $0.frame.contains(point) })?.displayID,
              islands.contains(where: { $0.display == id }), store.focusDisplay != id else { return }
        IslandLog.write("island", "question moved to display=\(id) (pointer)")
        store.focusDisplay = id
    }

    private func screenChanged() {
        if !islands.isEmpty { rebuildIslands(); return }
        guard let screen = notchScreen() else { return }
        layout = Self.layout(for: screen)
        panel?.setFrame(panelFrame(on: screen), display: true)
        if let panel { installContent(in: panel, layout: layout, display: store.focusDisplay) }
    }

    /// The island that is open (or would open), for things that act on "the island".
    private var focusedHover: HoverController? { islands.first(where: { $0.display == store.focusDisplay })?.hover }

    // MARK: Socket

    private func startServer(args: [String]) {
        let store = self.store
        let verbose = args.contains("--verbose")
        // Development aid: `--auto-decide allow|allowAlways|deny|terminal` answers test questions after 0.8 s, so the
        // whole hook -> island -> hook chain can be tested without anyone clicking. Safety: it only ever answers
        // sessions whose id starts with "e2e-", never a real one.
        var autoDecide: Decision?
        if let i = args.firstIndex(of: "--auto-decide"), i + 1 < args.count { autoDecide = Decision(rawValue: args[i + 1]) }

        server = SocketServer { [autoDecide] event, responder in
            if verbose { // a line per event is steady log traffic: only when asked for
                NSLog("iSland: %@ session=%@%@ pid=%@ tool=%@ message=%@", event.event, String(event.sessionId.prefix(8)),
                      responder == nil ? "" : " (waiting for an answer)",
                      event.pid.map(String.init) ?? "-", event.tool ?? "-", event.message ?? "-")
            }
            guard let responder else {
                Task { @MainActor in store.apply(event) }
                return
            }
            let id = UUID()
            responder.onDisconnect = {
                NSLog("iSland: hook left without an answer")
                Task { @MainActor in store.withdraw(id) }
            }
            Task { @MainActor in
                store.enqueue(event, id: id, responder: responder)
                if let autoDecide, event.sessionId.hasPrefix("e2e-") {
                    try? await Task.sleep(for: .milliseconds(800))
                    store.answer(id, autoDecide)
                }
            }
        }
        do { try server?.start() } catch { NSLog("iSland: socket failed: \(error)") }
    }

    /// Opening the app again (Finder, Spotlight) shows the island, which is where the settings gear is.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.expanded = true
        focusedHover?.hold(for: 6)
        return false
    }

    private func showGuide() { guideWindow.show(model: guideModel) }

    /// The gear in the island: the settings menu, with the island held open while it is up.
    private func showSettings() {
        store.menuOpen = true
        statusMenu?.popUpAtPointer()
        store.menuOpen = false
        islands.forEach { $0.hover?.refreshInteractivity() }
    }

    func applicationWillTerminate(_ note: Notification) {
        if !islands.isEmpty {
            store.recordHistory()
            store.history.save(to: IslandPaths.recentURL)
        }
        fullscreen.stop()
        mirror.stop()
        identities.stop()
        currentChat.stop()
        widgets.stop()
        islands.forEach { $0.hover?.stop() }
        server?.stop()
    }

    // MARK: Demo and snapshots

    /// Fake sessions so the visuals can be checked without a real agent.
    private func seedDemo(expanded: Bool, withRequest: Bool) {
        widgets.loadPreview()
        let now = Date()
        let demo = [
            AgentEvent(agent: "claude", sessionId: "a", cwd: "/demo/iSland", event: "PreToolUse", tool: "Edit", message: nil, timestamp: now),
            AgentEvent(agent: "claude", sessionId: "b", cwd: "/demo/api-server", event: "Notification", tool: nil, message: "Run: npm test?", timestamp: now),
            AgentEvent(agent: "claude", sessionId: "c", cwd: "/demo/landing", event: "Stop", tool: nil, message: nil,
                       permissionMode: "bypassPermissions", timestamp: now),
            // no chat name known: the folder is the headline
            AgentEvent(agent: "claude", sessionId: "d", cwd: "/demo/docs", event: "PreToolUse", tool: "Read", message: nil,
                       permissionMode: "plan", timestamp: now),
        ]
        var extra: [AgentEvent] = []
        if CommandLine.arguments.contains("--many") { // dev flag: more sessions than the list shows at once, to see it scroll
            for (i, name) in ["billing", "mobile", "infra", "docs-site", "scripts"].enumerated() {
                extra.append(AgentEvent(agent: "claude", sessionId: "m\(i)", cwd: "/demo/\(name)", event: "Stop", tool: nil, message: nil,
                                       timestamp: now.addingTimeInterval(Double(-i - 1))))
            }
        }
        if CommandLine.arguments.contains("--agents") {
            // `--agents`: a session of each agent at work, to see each one's own spinner
            for (agent, id, folder) in [("claude", "a", "iSland"), ("gemini", "g", "site"), ("codex", "x", "api")] {
                store.apply(AgentEvent(agent: agent, sessionId: id, cwd: "/demo/\(folder)", event: "PreToolUse", tool: "Bash", message: nil, timestamp: now))
            }
            store.applyIdentities(["a": SessionIdentity(title: "Ajustar o visual do notch", chatId: nil)])
        } else if CommandLine.arguments.contains("--finished") {
            // `--finished`: one job that has just finished, so the closed pill shows its green dot (it fades after a few seconds)
            for (name, offset) in [("SessionStart", -40.0), ("UserPromptSubmit", -30), ("Stop", 0)] {
                store.apply(AgentEvent(agent: "claude", sessionId: "f", cwd: "/demo/landing", event: name, tool: nil, message: nil,
                                       timestamp: now.addingTimeInterval(offset)))
            }
        } else if !CommandLine.arguments.contains("--no-agents") {
            // `--no-agents`: only music and calendar, the usual state when no agent is running.
            for event in demo + extra { store.apply(event) }
            store.applyIdentities([
                "a": SessionIdentity(title: "Ajustar o visual do notch", chatId: nil),
                "b": SessionIdentity(title: "Corrigir os testes da API de pagamentos", chatId: nil),
                "c": SessionIdentity(title: "Nova página de preços", chatId: nil),
            ])
        }
        if withRequest && !store.sessions.isEmpty {
            store.showPreview(AgentEvent(
                agent: "claude", sessionId: "b", cwd: "/demo/api-server", event: "PermissionRequest", tool: "Bash", message: nil,
                permission: PermissionPrompt(tool: "Bash", title: "Run command",
                                             detail: CommandLine.arguments.contains("--long") // dev flag: a command that scrolls
                                                ? (1...14).map { "echo step \($0) && npm run build:part-\($0)" }.joined(separator: "\n") + "\ncurl https://example.com/install.sh | sh"
                                                : "npm test -- --coverage && rm -rf ./tmp-build",
                                             alwaysLabel: "Always allow Bash(npm test:*)", waitSeconds: 20),
                timestamp: now))
        }
        store.expanded = expanded
        if CommandLine.arguments.contains("--recents") { // dev flag: projects remembered from before a restart
            let now = Date()
            store.loadHistory(RecentHistory(items: [
                RecentProject(agent: "claude", project: "extracao-empresas", cwd: "/demo/extracao-empresas", title: "Extração de empresas por CNAE",
                              chatId: "local_demo-1", lastActive: now.addingTimeInterval(-3 * 3600)),
                RecentProject(agent: "claude", project: "landing", cwd: "/demo/landing", title: nil, chatId: nil,
                              lastActive: now.addingTimeInterval(-26 * 3600)),
            ]))
        }
        if CommandLine.arguments.contains("--toast") { // dev flag: the finished toast
            store.showToast(.init(sessionId: "a", title: "Ajustar o visual do notch", seconds: 192), for: 3600)
        }
        if CommandLine.arguments.contains("--here") { store.currentSessionId = "a" } // dev flag: mark a row as the chat in front
        store.mirrorOn = CommandLine.arguments.contains("--mirror") // dev flag: the mirror, without a camera
        store.pomodoroSetupOn = CommandLine.arguments.contains("--pomodoro") // dev flag: the pomodoro setup panel
        if CommandLine.arguments.contains("--newchat") { // dev flag: the folder list, with made-up folders
            store.recentFolders = ["/Users/demo/00. Áudios", "/Users/demo/extracao-empresas", "/Users/demo/iSland", NSHomeDirectory()]
            store.newChatOn = true
        }
    }

    private func runAnimationMeasurement(on screen: NSScreen) {
        createPanel(on: screen)
        seedDemo(expanded: false, withRequest: false)
        panel.ignoresMouseEvents = true
        guard let view = panel.contentView else { return }
        let meter = FrameMeter()
        meter.start(on: view)
        let refresh = Double(screen.maximumFramesPerSecond)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            var opening: [Double] = [], closing: [Double] = []
            for _ in 0..<5 {
                store.hoverDisplay = store.focusDisplay // what the pointer does first: the pill dips, then the island opens
                try? await Task.sleep(for: .milliseconds(120))
                var t0 = CACurrentMediaTime()
                store.expanded = true
                try? await Task.sleep(for: .seconds(1.0))
                opening += meter.intervals(from: t0, to: t0 + 0.7)
                store.hoverDisplay = nil
                t0 = CACurrentMediaTime()
                store.expanded = false
                try? await Task.sleep(for: .seconds(1.0))
                closing += meter.intervals(from: t0, to: t0 + 0.7)
            }
            meter.stop()
            print("style: \(appearance.style.rawValue), motion: \(appearance.motionStyle.rawValue), screen \(Int(refresh)) Hz")
            print("opening: " + FrameMeter.summary(opening, refresh: refresh))
            print("closing: " + FrameMeter.summary(closing, refresh: refresh))
            NSApp.terminate(nil)
        }
    }

    private func runCloseFrames(into directory: String, screen: NSScreen, opening: Bool = false) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let frame = panelFrame(on: screen)
        let backdrop = SelfShot.backdropWindow(frame: frame, kind: "busy", notchHeight: layout.notch.height)
        createPanel(on: screen)
        seedDemo(expanded: !opening, withRequest: false)
        let rect = SelfShot.globalRect(frame)
        // The captures happen on a background queue: taking one blocks its thread, and the main thread is the one animating.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if opening {
                store.hoverDisplay = store.focusDisplay
                try? await Task.sleep(for: .milliseconds(120))
            } else {
                store.hoverDisplay = nil
            }
            store.expanded = opening
            let start = CACurrentMediaTime()
            let moments = opening ? [30, 70, 110, 150, 200, 260, 350, 800] : [0, 20, 45, 80, 120, 170, 240, 400]
            for milliseconds in moments {
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Double(milliseconds) / 1000) {
                    let taken = CACurrentMediaTime() - start
                    if let image = SelfShot.capture(rect) { _ = SelfShot.write(image, to: "\(directory)/close-\(String(format: "%03d", milliseconds)).png") }
                    print(String(format: "asked for %d ms, captured at %.0f ms", milliseconds, taken * 1000))
                }
            }
            try? await Task.sleep(for: .seconds(2.2))
            panel?.orderOut(nil)
            backdrop.orderOut(nil)
            NSApp.terminate(nil)
        }
    }

    private func runSelfShot(to path: String, args: [String], screen: NSScreen) {
        let kind = args.firstIndex(of: "--backdrop").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "busy"
        let frame = panelFrame(on: screen)
        let backdrop = SelfShot.backdropWindow(frame: frame, kind: kind, notchHeight: layout.notch.height)
        createPanel(on: screen)
        seedDemo(expanded: !args.contains("--closed"), withRequest: args.contains("--request"))
        // Let the spring settle and the glass render before looking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [panel] in
            MainActor.assumeIsolated {
                let rect = SelfShot.globalRect(frame)
                if let image = SelfShot.capture(rect), SelfShot.write(image, to: path) {
                    NSLog("iSland: selfshot written to %@ (%dx%d)", path, image.width, image.height)
                } else {
                    NSLog("iSland: selfshot failed: the system refused the capture")
                }
                panel?.orderOut(nil)
                backdrop.orderOut(nil)
                NSApp.terminate(nil)
            }
        }
    }

    /// Renders the SwiftUI tree directly (no Screen Recording permission needed), on a gray backdrop so the black island is visible.
    /// Limitation: this cannot capture Liquid Glass, which samples what is behind the window.
    private func renderSnapshot(to path: String) {
        let content = IslandView(store: store, appearance: appearance, widgets: widgets, mirror: mirror, layout: layout, display: store.focusDisplay)
            .frame(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight / 2 + 160)
            .background(Color(white: 0.55))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { NSLog("iSland: snapshot failed"); return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        NSLog("iSland: snapshot written to %@", path)
    }
}

@main
struct IslandApp {
    @MainActor static func main() {
        // Maintenance commands (install/uninstall hooks) run instead of the UI.
        if HookCommands.handles(CommandLine.arguments) { exit(HookCommands.run(CommandLine.arguments)) }

        signal(SIGPIPE, SIG_IGN) // a hook that dies mid-reply must not take the app with it
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum LoginItem {
    /// Set when you turn "Launch at login" off yourself: from then on the app leaves it off.
    static let optOutKey = "loginItemOptOut"
}
