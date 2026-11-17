import AppKit
import IslandCore
import SwiftUI

// The open island is a grid of rounded tiles: agents, music, pomodoro, calendar. Each function has its own hue, laid over the
// glass as a translucent wash; a waiting question takes the whole grid as one tile.

/// The colour of a tile. The fill is a wash of it over the glass; `neutral` is the quiet one.
enum BentoTint {
    case agents, music, focus, calendar, approval, neutral
    case custom(Color)

    var color: Color {
        switch self {
        case .agents: Color(red: 0.40, green: 0.42, blue: 0.95)
        case .music: Color(red: 0.66, green: 0.36, blue: 0.95)
        case .focus: Color(red: 1.00, green: 0.42, blue: 0.36)
        case .calendar: Color(red: 0.28, green: 0.56, blue: 1.00)
        case .approval: Color(red: 1.00, green: 0.45, blue: 0.28)
        case .neutral: Color.white
        case .custom(let color): color
        }
    }

    var opacity: Double {
        if case .neutral = self { return 0.07 }
        return 0.26
    }
}

private struct BentoTileStyle: ViewModifier {
    let tint: BentoTint
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                ZStack {
                    // A dark base under the wash: on a bright wallpaper the glass is light, and light grey under light
                    // text fails contrast. The wash then tints a darker surface and stays saturated.
                    shape.fill(Color.black.opacity(0.26))
                    shape.fill(tint.color.opacity(tint.opacity))
                    // A little light from above, so a tile reads as a surface and not a flat patch.
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.clear], startPoint: .top, endPoint: .center))
                }
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
            .clipShape(shape)
    }
}

extension View {
    func bentoTile(_ tint: BentoTint, radius: CGFloat = IslandLayout.tileRadius) -> some View {
        modifier(BentoTileStyle(tint: tint, radius: radius))
    }
}

// MARK: - Agents

/// A session as a ring: the colour is its state, the glyph inside says who is working. Static on purpose (the rows below
/// carry the animated glyphs; this rail is for reading state at a glance). The chat you are in gets a second ring.
struct AvatarRing: View {
    let session: AgentSession
    var isCurrent = false

    private var ringColor: Color {
        switch session.state {
        case .needsAttention: return Color(red: 1, green: 0.34, blue: 0.30)
        case .idle: return Color(red: 0.30, green: 0.85, blue: 0.45)
        case .working:
            switch session.agent {
            case AgentKind.gemini.rawValue: return GeminiSpinner.color
            case AgentKind.codex.rawValue: return Color.white.opacity(0.9)
            default: return ClaudeSpinner.orange
            }
        }
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(ringColor, lineWidth: 2)
            glyph
            if isCurrent { Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1).padding(-4) }
        }
        .frame(width: 22, height: 22)
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }

    @ViewBuilder private var glyph: some View {
        switch session.state {
        // A different mark per state, not only a different colour: red and green alone are no use to everyone.
        case .needsAttention: Text("!").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.38))
        case .idle: Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(red: 0.40, green: 0.90, blue: 0.52))
        case .working:
            switch session.agent {
            case AgentKind.gemini.rawValue: Text("⠿").font(.system(size: 11, weight: .bold)).foregroundStyle(GeminiSpinner.color)
            case AgentKind.codex.rawValue: Circle().fill(Color.white).frame(width: 7, height: 7)
            default: Text("✻").font(.system(size: 10, weight: .bold)).foregroundStyle(ClaudeSpinner.orange)
            }
        }
    }
}

/// "Agentes 3" and a ring per session.
struct AgentsHeader: View {
    let sessions: [AgentSession]
    let currentId: String?
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.t("Agents"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
            Text("\(sessions.count)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.white.opacity(0.16)))
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(sessions.prefix(IslandLayout.maxRows)) { session in
                    Button { onPick(session.id) } label: { AvatarRing(session: session, isCurrent: session.id == currentId) }
                        .buttonStyle(.plain)
                        .help(session.title ?? session.project)
                        // What VoiceOver says is the name and the state, and whether this is the chat in front.
                        .accessibilityLabel((session.title ?? session.project) + ", " + L10n.detail(session.detail))
                        .accessibilityAddTraits(session.id == currentId ? .isSelected : [])
                }
                if sessions.count > IslandLayout.maxRows {
                    Text("+\(sessions.count - IslandLayout.maxRows)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 2)
                }
            }
        }
        .frame(height: IslandLayout.agentsHeaderHeight)
    }
}

/// The sessions: a header with the rings, then a row each; past five they scroll in a window that shows half of the next.
struct AgentsTile: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        let sessions = store.ordered
        VStack(spacing: 0) {
            AgentsHeader(sessions: sessions, currentId: store.currentSessionId, onPick: { store.focus($0) })
            if sessions.count > IslandLayout.maxRows {
                ScrollView(.vertical, showsIndicators: false) { rows(sessions) }
                    .frame(height: IslandLayout.scrollingRowsHeight)
            } else {
                rows(sessions)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, IslandLayout.agentsTileTop)
        .padding(.bottom, IslandLayout.agentsTileBottom)
        .frame(maxWidth: .infinity)
        .frame(height: IslandLayout.agentsTileHeight(sessions: sessions.count) ?? 0, alignment: .top)
        .bentoTile(.agents)
    }

    private func rows(_ sessions: [AgentSession]) -> some View {
        VStack(spacing: 0) {
            ForEach(sessions) { session in
                SessionRow(session: session, isCurrent: store.currentSessionId == session.id, hover: store.rowHover,
                           onFocus: { store.focus(session.id) }, onDismiss: { store.dismiss(session.id) })
            }
        }
    }
}

/// While a question waits: just the rings, so you still see who else is working.
struct AgentsRailTile: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        AgentsHeader(sessions: store.ordered, currentId: store.currentSessionId, onPick: { store.focus($0) })
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: IslandLayout.railTileHeight)
            .bentoTile(.agents)
    }
}

/// "No active agents", when there is nothing else to show.
struct PlaceholderTile: View {
    var body: some View {
        Text(L10n.t("No active agents"))
            .font(.system(size: 13))
            .foregroundStyle(Color.white.opacity(0.78))
            .frame(maxWidth: .infinity)
            .frame(height: IslandLayout.placeholderTileHeight)
            .bentoTile(.neutral)
    }
}

/// What you were working on before a restart.
struct RecentsTile: View {
    let recents: [RecentProject]
    @ObservedObject var hover: RowHover
    let onResume: (RecentProject) -> Void
    let onForget: (RecentProject) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("Were active"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: IslandLayout.recentHeaderHeight)
            ForEach(recents) { project in
                RecentRow(project: project, hover: hover, onResume: { onResume(project) }, onForget: { onForget(project) })
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, IslandLayout.agentsTileTop)
        .padding(.bottom, IslandLayout.agentsTileBottom)
        .frame(maxWidth: .infinity)
        .frame(height: IslandLayout.recentsTileHeight(count: recents.count) ?? 0, alignment: .top)
        .bentoTile(.neutral)
    }
}

// MARK: - Media row

/// Music and pomodoro side by side (squarer), or whichever is there as one wide strip.
struct MediaRow: View {
    let music: NowPlayingManager?
    let focus: FocusTimer?

    private var height: CGFloat {
        var presence = WidgetPresence()
        presence.music = music != nil
        presence.focus = focus != nil
        return IslandLayout.mediaRowHeight(widgets: presence) ?? 0
    }

    var body: some View {
        HStack(spacing: IslandLayout.tileGap) {
            if let music { MusicTile(music: music, compact: focus != nil) }
            if let focus { FocusTile(focus: focus, compact: music != nil) }
        }
        .frame(height: height)
    }
}

// MARK: - Cover colour

extension NSImage {
    /// The cover's average colour (a 1x1 render of it), kept bright enough to be a tint and dark enough for white text.
    func averageTint() -> NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let color = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(1, max(0.35, saturation * 1.15)), brightness: min(0.85, max(0.5, brightness)), alpha: 1)
    }

    /// A made-up cover for demos and snapshots: a sunset over a skyline.
    static func demoCover() -> NSImage {
        let size = NSSize(width: 120, height: 120)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.18, green: 0.08, blue: 0.40, alpha: 1), NSColor(srgbRed: 0.93, green: 0.35, blue: 0.55, alpha: 1),
                                NSColor(srgbRed: 1.0, green: 0.72, blue: 0.30, alpha: 1)])?.draw(in: rect, angle: 90)
            NSColor(srgbRed: 0.06, green: 0.04, blue: 0.16, alpha: 1).setFill()
            for (i, h) in [34, 52, 28, 62, 40, 48].enumerated() {
                NSBezierPath(rect: NSRect(x: CGFloat(i) * 20, y: 0, width: 17, height: CGFloat(h))).fill()
            }
            return true
        }
    }
}
