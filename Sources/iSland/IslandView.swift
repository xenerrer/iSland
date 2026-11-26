import CoreGraphics
import IslandCore
import SwiftUI

struct IslandView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var appearance: Appearance
    @ObservedObject var widgets: Widgets
    @ObservedObject var mirror: MirrorManager
    let layout: IslandLayout
    /// The display this island is drawn on.
    var display: CGDirectDisplayID = CGMainDisplayID()
    /// The gear in the header: opens the settings menu.
    var onSettings: () -> Void = {}
    /// The "+" in the favorites tile: a menu of projects to pin.
    var onAddFavorite: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The island is dark whatever the system theme, so semantic colors and glass must resolve for dark.
        .environment(\.colorScheme, .dark)
    }

    // MARK: State

    private var open: Bool { store.isOpen(on: display) }
    private var presence: WidgetPresence { widgets.presence }
    private var size: CGSize { layout.size(for: store, widgets: presence, display: display) }
    /// The width the open content is laid out at, whatever the container is doing: it stays put while the container grows or
    /// shrinks around it (the shape clips it), so nothing in it reflows or travels sideways during the animation.
    private var contentWidth: CGFloat {
        layout.size(open: true, sessions: store.sessions.count, request: store.requests.first?.prompt, widgets: presence,
                    closedStatus: false, mode: store.mode, recents: store.visibleRecents.count,
                    favoriteCells: max(1, store.favorites.items.count)).width
    }
    /// Glass only when open: the closed pill stays black so it fuses with the hardware notch.
    private var usesGlass: Bool { open && appearance.style != .solid && !appearance.reduceTransparency }
    private var showsToast: Bool { !open && store.toast != nil && !store.hiddenPillDisplays.contains(display) }
    private var shape: NotchShape {
        NotchShape(topRadius: open ? 14 : IslandLayout.closedEar,
                   bottomRadius: open ? IslandLayout.islandBottomRadius : (showsToast ? 20 : 12))
    }
    private var motion: Animation { appearance.reduceMotion ? .easeOut(duration: 0.12) : (open ? Motion.open(appearance.motionStyle) : Motion.close(appearance.motionStyle)) }

    /// Without a hardware notch, the collapsed pill disappears while it has nothing to report.
    private var hidesClosedPill: Bool {
        !open && !IslandLayout.drawsClosedPill(hasHardwareNotch: layout.hasHardwareNotch, alwaysDraws: layout.alwaysDrawsPill, items: pillItems)
    }

    /// What the collapsed pill shows; nothing while a full-screen video is playing.
    private var pillItems: [PillItem] {
        if store.hiddenPillDisplays.contains(display) { return [] }
        return IslandLayout.pillItems(sessions: store.sessions.count, status: store.closedStatus != nil, widgets: presence)
    }

    /// The collapsed pill swells slightly while the pointer rests on it, before the island opens (Apple's way of saying "I felt that").
    private var swells: Bool { store.hoverDisplay == display && !open && !appearance.reduceMotion && !hidesClosedPill }

    /// The fade between the black pill and the glass. It only ever animates opacity: each layer's size follows the container
    /// spring through its own `.animation(motion, value: size)` placed under it (an animation modifier covers everything
    /// beneath it, so sharing one with the fade would make the shape's size ease with the fade and slide off-centre).
    private var fade: Animation { .easeOut(duration: open ? 0.25 : 0.08).delay(open ? Motion.glassArrives : Motion.glassLeaves) }

    private var showsGlass: Bool {
        appearance.style != .solid && !appearance.reduceTransparency && (open || store.glassDisplays.contains(display))
    }

    /// Everything is drawn on a stage as wide as the panel that never moves, centred on the notch. Each layer has its own
    /// animated frame, and the content is only ever revealed through the growing shape: the island opens from the notch
    /// downwards and closes back up into it, and nothing is drawn outside the shape.
    private var island: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black)
                .frame(width: size.width, height: size.height)
                .animation(motion, value: size)
                .opacity(usesGlass || hidesClosedPill ? 0 : 1)
                .animation(fade, value: usesGlass)
            if showsGlass {
                GlassBackdrop(shape: shape, style: appearance.style)
                    .frame(width: size.width, height: size.height)
                    .animation(motion, value: size)
                    .opacity(open ? 1 : 0)
                    .animation(fade, value: open)
                    // A glass that is added with the toggle starts at its final size, so it waits for the container to get there.
                    .transition(.opacity.animation(.easeOut(duration: 0.25).delay(Motion.glassInserted)))
            }
            ZStack(alignment: .top) {
                Group {
                    if open && store.mirrorOn && store.requests.isEmpty {
                        mirrorContent
                    } else if open && store.newChatOn && store.requests.isEmpty {
                        newChatContent
                    } else if open && store.pomodoroSetupOn && store.requests.isEmpty {
                        pomodoroContent
                    } else if open {
                        openContent
                    } else if showsToast, let toast = store.toast {
                        toastContent(toast)
                            .transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.12)))
                    } else if !pillItems.isEmpty {
                        closedIndicators
                            .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.15).delay(0.25)), // once the pill is pill-sized
                                                    removal: .opacity.animation(.easeOut(duration: 0.06)))) // gone before the island grows around it
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .mask(alignment: .top) {
                shape.frame(width: size.width, height: size.height).animation(motion, value: size)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { store.openStateChanged(open, on: display) }
        .onChange(of: open) { _, now in
            store.openStateChanged(now, on: display)
            if !now { store.rowHover.sessionId = nil }
        }
        // The glass is ready before the pointer opens the island, so it never has to be inserted mid-animation.
        .onChange(of: swells) { _, now in
            if now { store.openStateChanged(true, on: display) } else if !open { store.openStateChanged(false, on: display) }
        }
        // The hover cue is a small dip of the pill: vertical only, and scoped to the scale so it can never drive the frames.
        .animation(.spring(duration: 0.3, bounce: 0.35)) { $0.scaleEffect(x: 1, y: swells ? 1.15 : 1, anchor: .top) }
    }

    // MARK: Closed

    /// Collapsed: the black pill with whatever has something to say, split evenly over the two sides of the notch
    /// (see `IslandLayout.pillSides`). Present only while there is something to report.
    private var closedIndicators: some View {
        let items = pillItems
        let sides = IslandLayout.pillSides(items)
        // The flared ears take `closedEar` off each outer edge of the frame, so centre inside what is visible.
        let wing = IslandLayout.pillWing(items) - IslandLayout.closedEar
        return HStack(spacing: 0) {
            pillSide(sides.left).frame(width: wing).padding(.leading, IslandLayout.closedEar)
            Color.clear.frame(width: layout.notch.width)
            pillSide(sides.right).frame(width: wing).padding(.trailing, IslandLayout.closedEar)
        }
        .frame(height: layout.notch.height)
    }

    private func pillSide(_ items: [PillItem]) -> some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in pillView(item).frame(width: item.width) }
        }
    }

    @ViewBuilder
    private func pillView(_ item: PillItem) -> some View {
        switch item {
        case .count:
            Text("\(store.sessions.count)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
        case .equalizer:
            Equalizer(color: Color.white.opacity(0.8)).scaleEffect(0.75)
        case .pomodoro:
            // the ring of dots for the phase; the exact time is on the card in the open island
            TimelineView(.periodic(from: Clock.epoch, by: 5)) { context in
                DotRing(elapsed: widgets.focus.fraction(at: context.date),
                        isBreak: widgets.focus.phase?.isBreak ?? false, paused: widgets.focus.isPaused, diameter: 16)
            }
        case .status:
            if let status = store.closedStatus { StatusGlyph(state: status, agent: store.workingAgent) }
        }
    }

    // MARK: Finished toast

    /// Under the notch for a few seconds when a job finishes while you are elsewhere: a click goes to that chat.
    private func toastContent(_ toast: SessionStore.FinishToast) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.notch.height)
            Button {
                store.focus(toast.sessionId)
                store.dismissToast()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.30, green: 0.85, blue: 0.45))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(toast.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white).lineLimit(1)
                        Text(L10n.detail("Done") + " · " + DurationFormat.short(toast.seconds))
                            .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.8))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .frame(height: IslandLayout.toastHeight, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(toast.title + ", " + L10n.detail("Done"))
        }
        .frame(width: max(IslandLayout.toastWidth, layout.notch.width), alignment: .top)
    }

    // MARK: Mirror

    /// The camera in a circle hanging from the notch; the header (and its gear) gives way until you go back.
    private var mirrorContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.notch.height)
            MirrorCard(mirror: mirror, joinURL: store.mirrorJoinURL) {
                store.mirrorOn = false
                store.mirrorJoinURL = nil
            }
            .padding(.top, IslandLayout.topGap)
            .padding(.bottom, IslandLayout.bottomPadding)
        }
        .frame(width: contentWidth, alignment: .top)
        .transition(Motion.content(appearance.motionStyle))
    }

    // MARK: Pomodoro setup

    private var pomodoroContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.notch.height)
            PomodoroSetupCard(focus: widgets.focus, onStart: {
                widgets.focus.start()
                store.pomodoroSetupOn = false
            }, onBack: { store.pomodoroSetupOn = false })
            .padding(.top, IslandLayout.topGap)
            .padding(.bottom, IslandLayout.bottomPadding)
        }
        .frame(width: contentWidth, alignment: .top)
        .transition(Motion.content(appearance.motionStyle))
    }

    // MARK: New chat

    /// Recent folders under the notch: one click starts a chat in that folder, in the Claude app.
    private var newChatContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: layout.notch.height)
            NewChatCard(folders: store.recentFolders, onPick: { folder in
                if let link = ClaudeDesktop.newChatLink(inFolder: folder) { ProcessTree.open(chat: link) }
                store.newChatOn = false
            }, onBack: { store.newChatOn = false })
            .padding(.top, IslandLayout.topGap)
            .padding(.bottom, IslandLayout.bottomPadding)
        }
        .frame(width: contentWidth, alignment: .top)
        .transition(Motion.content(appearance.motionStyle))
    }

    // MARK: Open

    private var openContent: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: IslandLayout.tileGap) {
                if let request = store.requests.first {
                    // A question takes the grid: its tile, and under it only the rings of the agents.
                    ApprovalCard(request: request, chat: store.displayName(forSession: request.sessionId) ?? request.project,
                                 inChat: store.sessions[request.sessionId]?.chatId != nil,
                                 queued: store.requests.count - 1, showsShortcuts: store.hotkeysActive) {
                        store.answer(request.id, $0)
                    }
                    if !store.sessions.isEmpty { AgentsRailTile(store: store) }
                } else {
                    let recents = store.visibleRecents
                    if IslandLayout.showsPlaceholder(sessions: store.sessions.count, request: false, widgets: presence, recents: recents.count,
                                                     favoriteCells: max(1, store.favorites.items.count)) {
                        PlaceholderTile()
                    }
                    if !store.sessions.isEmpty { AgentsTile(store: store) }
                    FavoritesTile(favorites: store.favorites.items, maxRows: IslandLayout.favoriteRows(sessions: store.sessions.count),
                                  live: Set(store.sessions.values.map(SessionStore.historyKey(for:))),
                                  hover: store.rowHover,
                                  onOpen: { store.resume($0) }, onAdd: onAddFavorite,
                                  onRemove: { store.removeFavorite($0) }, onMove: { store.moveFavorite($0, by: $1) })
                    if !recents.isEmpty {
                        RecentsTile(recents: recents, hover: store.rowHover, onResume: { store.resume($0) }, onForget: { store.forget($0) })
                    }
                    if presence.music || presence.focus {
                        MediaRow(music: presence.music ? widgets.music : nil, focus: presence.focus ? widgets.focus : nil)
                    }
                    if presence.calendar {
                        CalendarCard(calendar: widgets.calendar, onMirror: { url in
                            store.mirrorJoinURL = url
                            store.mirrorOn = true
                        })
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, IslandLayout.sidePadding)
            .padding(.top, IslandLayout.bentoTop)
            .padding(.bottom, IslandLayout.bentoBottom)
        }
        .frame(width: contentWidth, alignment: .top)
        .transition(Motion.content(appearance.motionStyle))
    }

    /// The strip beside the physical notch: overall status on the left, session count and the settings gear on the right.
    private var header: some View {
        let wing = (contentWidth - layout.notch.width) / 2
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if store.overall != .idle { StatusGlyph(state: store.overall, agent: store.workingAgent) } // at rest, the words are enough
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            // The island's body starts 14 pt in (the flared corner); the chip keeps a little air from that edge.
            .padding(.leading, IslandLayout.sidePadding - 6)
            .frame(width: wing, alignment: .leading)
            Color.clear.frame(width: layout.notch.width)
            HStack(spacing: 2) {
                Button {
                    if widgets.focus.isActive { widgets.focus.togglePause() } else { store.pomodoroSetupOn = true }
                } label: {
                    Image(systemName: "timer").font(.system(size: 13)).frame(width: 24, height: 24)
                }
                .buttonStyle(GearButtonStyle())
                .help(L10n.t("Pomodoro"))
                .accessibilityLabel(L10n.t("Pomodoro"))
                Button { store.newChatOn = true } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12.5))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(GearButtonStyle())
                .help(L10n.t("New chat"))
                .accessibilityLabel(L10n.t("New chat"))
                Button { store.mirrorJoinURL = nil; store.mirrorOn = true } label: {
                    MirrorGlyph(size: 14).frame(width: 24, height: 24)
                }
                .buttonStyle(GearButtonStyle())
                .help(L10n.t("Mirror"))
                .accessibilityLabel(L10n.t("Mirror"))
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12.5))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(GearButtonStyle())
                .help(L10n.t("Settings"))
                .accessibilityLabel(L10n.t("Settings"))
            }
            .padding(.trailing, IslandLayout.sidePadding - 8)
            .frame(width: wing, alignment: .trailing)
        }
        .frame(height: layout.notch.height)
    }

    private var summary: String {
        let waiting = store.sessions.values.filter { $0.state == .needsAttention }.count
        let working = store.sessions.values.filter { $0.state == .working }.count
        if waiting > 0 {
            return L10n.isPortuguese ? L10n.n("%d waiting", waiting) : (waiting == 1 ? "1 needs you" : "\(waiting) need you")
        }
        if working > 0 { return L10n.n("%d working", working) }
        return store.sessions.isEmpty ? "iSland" : L10n.t("All idle")
    }
}

// MARK: - Background

/// Liquid Glass body for the open island (macOS 26+; black below that).
struct GlassBackdrop: View {
    let shape: NotchShape
    let style: IslandStyle

    var body: some View {
        // `compiler(>=6.2)` is the toolchain that ships the macOS 26 SDK: an older one (a CI runner with Xcode 16) cannot
        // even parse `glassEffect`, so it builds the black fallback.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(glass, in: shape)
                // A light scrim keeps white text readable over bright wallpapers; the glass still shows through.
                .overlay { shape.fill(Color.black.opacity(Self.knob("scrim", default: style == .clear ? 0.12 : 0.20))) }
        } else {
            shape.fill(Color.black.opacity(0.92))
        }
        #else
        shape.fill(Color.black.opacity(0.92))
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var glass: Glass {
        style == .clear
            ? Glass.clear.tint(Color.black.opacity(Self.knob("clearTint", default: 0.35)))
            : Glass.regular.tint(Color.black.opacity(Self.knob("glassTint", default: 0.50)))
    }
    #endif

    /// Hidden tuning knob: `iSland -glassTint 0.6` (any number from 0 to 1) overrides the tint opacity.
    private static func knob(_ key: String, default value: Double) -> Double {
        UserDefaults.standard.object(forKey: key) == nil ? value : UserDefaults.standard.double(forKey: key)
    }
}

// MARK: - Status

/// One glyph per state, all in the same 16 pt box so rows line up.
struct StatusGlyph: View {
    let state: SessionState
    /// Whose spinner to show while it works.
    var agent = "claude"

    var body: some View {
        Group {
            switch state {
            case .working: AgentSpinner(agent: agent)
            case .needsAttention: AttentionDot()
            case .idle: Circle().fill(Color.green).frame(width: 8, height: 8)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// Each agent's own sign that it is working: Claude Code's blooming star, Gemini CLI's braille dots, Codex CLI's pulsing bullet.
struct AgentSpinner: View {
    let agent: String

    var body: some View {
        Group {
            switch agent {
            case AgentKind.gemini.rawValue: GeminiSpinner()
            case AgentKind.codex.rawValue: CodexSpinner()
            default: ClaudeSpinner()
            }
        }
    }
}

/// Gemini CLI's spinner: ten braille dots turning, in its blue-violet.
struct GeminiSpinner: View {
    static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    static let color = Color(red: 0.55, green: 0.66, blue: 0.98)

    var body: some View {
        GlyphSpinner(glyphs: Self.frames, interval: 0.08, font: .monospacedSystemFont(ofSize: 19, weight: .bold),
                     color: NSColor(red: 0.55, green: 0.66, blue: 0.98, alpha: 1))
    }
}

/// Codex CLI's "Working": a bullet whose brightness swells and fades, the way the shimmer sweeps its label.
struct CodexSpinner: View {
    var body: some View {
        PulsingDot(glyph: "•", font: .systemFont(ofSize: 24, weight: .heavy), color: .white, low: 0.3, period: 1.4)
    }
}

/// The spinner Claude Code shows while it works: a glyph that blooms from a dot to a star and back.
struct ClaudeSpinner: View {
    static let orange = Color(red: 0.95, green: 0.54, blue: 0.38)
    static let orangeNS = NSColor(red: 0.95, green: 0.54, blue: 0.38, alpha: 1)
    private static let bloom = ["·", "✢", "✳", "∗", "✻", "✽"]
    private static let frames: [String] = bloom + bloom.dropFirst().dropLast().reversed()

    var body: some View {
        GlyphSpinner(glyphs: Self.frames, interval: 0.12, font: .systemFont(ofSize: 15, weight: .bold), color: Self.orangeNS)
    }
}

/// A red dot that breathes: something is waiting for you.
struct AttentionDot: View {
    var body: some View {
        // A solid dot drawn once; the breathing is Core Animation's (a SwiftUI repeating animation would redraw the island forever).
        PulsingDot(glyph: "●", font: .systemFont(ofSize: 7.5), color: NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1),
                   low: 0.4, period: 1.4, shadow: true)
    }
}

/// One session: the chat's name, with the folder it works in underneath, small. Click to go to that chat.
struct SessionRow: View {
    let session: AgentSession
    /// The chat you are in right now: marked, so you do not click it by mistake.
    var isCurrent = false
    @ObservedObject var hover: RowHover
    let onFocus: () -> Void
    /// The x at the right edge: take this session off the list.
    let onDismiss: () -> Void

    private var badge: ModeBadge? { L10n.modeBadge(session.permissionMode) }
    private var hovered: Bool { hover.sessionId == session.id }
    private var plate: Double { (isCurrent ? 0.10 : 0) + (hovered ? 0.07 : 0) }

    var body: some View {
        HStack(spacing: 8) {
            StatusGlyph(state: session.state, agent: session.agent)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? session.project)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                if session.title != nil || badge != nil {
                    HStack(spacing: 6) {
                        // Without a chat name the folder is already the headline.
                        if session.title != nil { FolderLabel(name: session.project) }
                        if let badge { ModeBadgeView(badge: badge) }
                    }
                }
            }
            Spacer(minLength: 8)
            SessionDetail(session: session)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.middle)
                // The name gives way, never the status; but the status itself has a ceiling, or one long text would make the
                // row wider than the island and push every row out of it on both sides.
                .frame(maxWidth: IslandLayout.detailMaxWidth, alignment: .trailing)
                // Its own width up to the cap: without this the frame would take the whole 170 pt whatever the text needs, and
                // the chat's name would be cut with room to spare.
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(DismissButtonStyle())
            .help(L10n.t("Remove from the list"))
            .accessibilityLabel(L10n.t("Remove from the list") + ": " + (session.title ?? session.project))
        }
        .frame(height: IslandLayout.sessionRowHeight)
        // The chat you are in gets a soft plate that reaches a little past the row's content.
        // A soft plate under the row: stronger for the chat you are in, lighter while the pointer is on it.
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(plate))
            .padding(.horizontal, -8).padding(.vertical, -1)
            .animation(.easeOut(duration: 0.12), value: plate))
        .background(HoverTracker { [hover, id = session.id] inside in hover.set(id, inside) })
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus) // jump to this chat (or to the app that hosts the session)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onFocus)
    }
}

/// A project that was active before a restart: click to go back to it, × to forget it.
struct RecentRow: View {
    let project: RecentProject
    @ObservedObject var hover: RowHover
    let onResume: () -> Void
    let onForget: () -> Void

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var hovered: Bool { hover.sessionId == project.key }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title ?? project.project)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if project.title != nil { FolderLabel(name: project.project) }
                    Text(Self.formatter.localizedString(for: project.lastActive, relativeTo: Date()))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onForget) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(DismissButtonStyle())
            .help(L10n.t("Forget this project"))
            .accessibilityLabel(L10n.t("Forget this project") + ": " + (project.title ?? project.project))
        }
        .frame(height: IslandLayout.recentRowHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hovered ? 0.07 : 0))
            .padding(.horizontal, -8).padding(.vertical, -1)
            .animation(.easeOut(duration: 0.12), value: hovered))
        .background(HoverTracker { [hover, key = project.key] inside in hover.set(key, inside) })
        .contentShape(Rectangle())
        .onTapGesture(perform: onResume)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onResume)
        .help(L10n.t("Go back to this project"))
    }
}

struct FolderLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "folder.fill").font(.system(size: 8.5))
            Text(name).lineLimit(1)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Color.white.opacity(0.72))
    }
}

/// Marks how a session treats permissions with a quiet grey icon; the explanation is its tooltip.
struct ModeBadgeView: View {
    let badge: ModeBadge

    var body: some View {
        // Just the icon: the words are in the tooltip, and a row should not shout about its mode.
        Image(systemName: badge.symbol)
            .font(.system(size: 9))
            .foregroundStyle(Color.white.opacity(0.65))
            .help(badge.help)
            .accessibilityLabel(badge.text)
    }
}

struct DismissButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.95 : 0.6))
            .contentShape(Rectangle())
    }
}

struct GearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.95 : 0.55))
            .contentShape(Rectangle())
    }
}

/// "Edit · 1m 20s" while working (ticking), "Done · 3m 12s" afterwards.
struct SessionDetail: View {
    let session: AgentSession

    var body: some View {
        if session.state == .working, let start = session.turnStartedAt {
            TimelineView(.periodic(from: Clock.epoch, by: 1)) { context in
                Text(L10n.detail(session.detail) + " · " + DurationFormat.short(Int(context.date.timeIntervalSince(start))))
            }
        } else if session.state == .idle, let seconds = session.lastTurnSeconds, seconds >= 1, session.detail == "Done" {
            Text(L10n.detail(session.detail) + " · " + DurationFormat.short(seconds))
        } else {
            Text(L10n.detail(session.detail))
        }
    }
}

// MARK: - Approval

/// A question an agent is waiting on. Allow, deny, or hand it back to the terminal.
struct ApprovalCard: View {
    let request: PendingRequest
    /// Which chat is asking: its name, or the folder when the name is not known.
    let chat: String
    /// The session lives in the Claude app, so handing the question back means answering it in the chat, not a terminal.
    let inChat: Bool
    let queued: Int
    let showsShortcuts: Bool
    let answer: (Decision) -> Void

    private var prompt: PermissionPrompt { request.prompt }
    private static let alarm = Color(red: 1, green: 0.34, blue: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: IslandLayout.approvalSpacing) {
            header
            command
            hints
            Spacer(minLength: 0)
            buttons
        }
        .padding(IslandLayout.approvalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: IslandLayout.cardHeight(for: prompt), alignment: .top)
        .bentoTile(.approval)
    }

    /// The tool's icon in a ring that empties as the time runs out, the question's title, and the seconds left, big.
    private var header: some View {
        TimelineView(.periodic(from: Clock.epoch, by: 1)) { context in
            let remaining = max(0, request.deadline.timeIntervalSince(context.date))
            let total = max(1, request.deadline.timeIntervalSince(request.receivedAt))
            let seconds = Int(remaining.rounded(.up))
            let late = seconds <= 5
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: min(1, remaining / total))
                        .stroke(late ? Self.alarm : BentoTint.approval.color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(late ? Self.alarm : BentoTint.approval.color)
                        .accessibilityHidden(true)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(prompt.title))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(chat).lineLimit(1)
                        // Kept out of the string that gets cut: the name gives way, the count of waiting questions never does.
                        if queued > 0 { Text("· " + L10n.n("+%d waiting", queued)).lineLimit(1).fixedSize().layoutPriority(1) }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.82))
                }
                Spacer(minLength: 0)
                Text("\(seconds)s")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // White even when late: red digits on the orange tile are harder to read exactly when it matters. The ring
                    // and the icon turn red instead.
                    .foregroundStyle(Color.white)
                    .fixedSize()
            }
        }
        .frame(height: IslandLayout.approvalHeaderHeight)
    }

    /// What is about to run, in a well: the tool, then the text, with the dangerous words marked. A long text scrolls in
    /// the well, so all of it can be read before saying yes.
    private var command: some View {
        let text = Text(Self.highlighted(prompt.detail.isEmpty ? L10n.t("(no details)") : prompt.detail))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.92))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(ToolName.display(prompt.tool))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                Spacer(minLength: 4)
                if prompt.hasHiddenCharacters {
                    Label(L10n.t("Has hidden characters (⍰)"), systemImage: "eye.slash")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.45))
                        .lineLimit(1)
                } else if prompt.isLong {
                    Label(L10n.t("Scroll to read it all"), systemImage: "arrow.up.and.down")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            if prompt.isLong {
                ScrollView(.vertical, showsIndicators: false) {
                    text.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: CGFloat(PermissionPrompt.visibleLines) * 15)
                .mask(alignment: .top) {
                    // the last line fades, so it is clear there is more under it
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom).frame(height: 14)
                    }
                }
            } else {
                text
                    .lineLimit(PermissionPrompt.visibleLines)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.30)))
    }

    private var hints: some View {
        HStack(spacing: 8) {
            if prompt.needsReview {
                Label {
                    Text(L10n.t("Too big to approve here: check it in the terminal")).foregroundStyle(Color.white.opacity(0.92))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 1, green: 0.72, blue: 0.45))
                }
                .lineLimit(1)
            } else {
                Text(prompt.alwaysLabel.map { L10n.t("Always: ") + $0.replacingOccurrences(of: "Always allow ", with: "") } ?? "")
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if showsShortcuts && !prompt.needsReview {
                KeyHint(keys: "⌥⌘Y", label: L10n.t("Allow").lowercased())
                KeyHint(keys: "⌥⌘N", label: L10n.t("Deny").lowercased())
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(0.8))
        .frame(height: IslandLayout.approvalHintsHeight)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            IslandButton(title: L10n.t("Deny"), kind: .deny, large: true) { answer(.deny) }
            Spacer(minLength: 4)
            IslandButton(title: L10n.t(inChat ? "In chat" : "Terminal"), kind: .neutral, large: true) { answer(.terminal) }
            if prompt.alwaysLabel != nil && !prompt.needsReview {
                IslandButton(title: L10n.t("Always"), kind: .always, large: true) { answer(.allowAlways) }
            }
            if !prompt.needsReview { IslandButton(title: L10n.t("Allow"), kind: .allow, large: true) { answer(.allow) } }
        }
        .frame(height: IslandLayout.approvalButtonsHeight)
    }

    private var symbol: String {
        switch prompt.tool {
        case "Bash": "terminal"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": "square.and.pencil"
        case "Read", "Glob", "Grep": "doc.text.magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        default: prompt.tool.hasPrefix("mcp__") ? "puzzlepiece.extension" : "questionmark.circle"
        }
    }

    /// Words that deserve a second look are drawn in red. Only a visual aid: it never decides anything.
    static func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let risky = ["rm -rf", "rm -fr", "sudo", "chown -R", "chmod -R", "git push --force", "git push -f", "git reset --hard",
                     "DROP TABLE", "DROP DATABASE", "mkfs", "dd if="]
        for word in risky {
            var from = attributed.startIndex
            while from < attributed.endIndex, let range = attributed[from...].range(of: word, options: .caseInsensitive) {
                attributed[range].foregroundColor = Color(red: 1, green: 0.45, blue: 0.40)
                from = range.upperBound
            }
        }
        return attributed
    }
}

/// A keyboard shortcut and what it does: "⌥⌘Y permitir".
struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.95))
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.12)))
            Text(label)
        }
    }
}

/// Buttons are opaque on purpose. The panel is never the active window (so it cannot steal the keyboard), and macOS
/// desaturates Liquid Glass controls in inactive windows: Deny and Allow would lose their colors.
struct IslandButton: View {
    enum Kind { case deny, neutral, always, allow }

    let title: String
    let kind: Kind
    /// The approval tile's big pills (about 40 pt tall).
    var large = false
    let action: () -> Void

    var body: some View {
        Button(title, action: action).buttonStyle(CapsuleButtonStyle(fill: fill, foreground: foreground, large: large))
    }

    private var fill: Color {
        switch kind {
        case .deny: Color(red: 0.86, green: 0.20, blue: 0.18).opacity(0.62)
        case .neutral: Color.white.opacity(0.18)
        case .always: Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.26)
        case .allow: Color(red: 0.3, green: 0.85, blue: 0.45)
        }
    }

    private var foreground: Color {
        switch kind {
        case .deny: Color.white
        case .neutral: Color.white
        case .always: Color(red: 0.76, green: 1.0, blue: 0.80)
        case .allow: Color.black.opacity(0.85)
        }
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13 : 12, weight: .semibold))
            .padding(.horizontal, large ? 16 : 12)
            .frame(height: large ? 38 : nil)
            .padding(.vertical, large ? 0 : 5)
            .background(Capsule().fill(fill))
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
