import AppKit
import IslandCore
import SwiftUI

private let cardBackground = RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06))

// MARK: - Music

/// Four bars that dance while something plays. With Reduce Motion on they stand still.
struct Equalizer: View {
    var color: Color = Color.white.opacity(0.85)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BarsEqualizer(color: NSColor(color), animated: !reduceMotion).frame(width: 16, height: 12)
    }
}

/// What is playing, and whether it is: cover, title, artist and app, with previous / play-pause / next.
struct MusicCard: View {
    @ObservedObject var music: NowPlayingManager

    var body: some View {
        let state = music.state
        HStack(spacing: 10) {
            Cover(image: music.artwork)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title.isEmpty ? L10n.t("Unknown track") : state.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if state.isPlaying {
                        Equalizer(color: ClaudeSpinner.orange).frame(width: 14, height: 10).scaleEffect(0.8)
                    } else {
                        Image(systemName: "pause.fill").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.55))
                    }
                    Text(subtitle(for: state))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                control("backward.fill", label: "Previous", .previous)
                control(state.isPlaying ? "pause.fill" : "play.fill", label: state.isPlaying ? "Pause" : "Play", .togglePlayPause, size: 16)
                control("forward.fill", label: "Next", .next)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: IslandLayout.widgetHeight)
        .background(cardBackground)
        .overlay(alignment: .bottom) { ProgressLine(state: state).padding(.horizontal, 12).padding(.bottom, 4) }
    }

    /// "Channel · Google Chrome": on YouTube the artist is the channel, and the app says where it plays.
    private func subtitle(for state: NowPlayingState) -> String {
        [state.artist, music.appName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func control(_ symbol: String, label: String, _ command: MediaCommand, size: CGFloat = 12) -> some View {
        Button { music.send(command) } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(width: 30, height: 30)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(L10n.t(label))
    }
}

struct Cover: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: 16)).foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A hairline that advances with the track.
struct ProgressLine: View {
    let state: NowPlayingState

    var body: some View {
        if let duration = state.duration, duration > 0 {
            TimelineView(.periodic(from: Clock.epoch, by: 1)) { context in
                let fraction = min(1, max(0, (state.elapsedNow(at: context.date) ?? 0) / duration))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.white.opacity(0.5)).frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 2)
            }
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.5 : 0.9))
            .contentShape(Rectangle())
    }
}

// MARK: - Usage and focus

struct ProgressBar: View {
    let fraction: Double
    var color: Color = ClaudeSpinner.orange

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color.opacity(0.85)).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 3)
    }
}

/// A small ring of thirty dots, whatever the length of the phase, that go out clockwise from the top as it runs down: the
/// bright ones are the time left. White for focus, green for a break.
struct DotRing: View {
    /// How much of the phase has gone, 0...1.
    let elapsed: Double
    var isBreak = false
    var paused = false
    var diameter: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            let dots = 30
            let left = Int(ceil((1 - min(1, max(0, elapsed))) * Double(dots) - 0.0001))
            let radius = min(size.width, size.height) / 2 - 1
            let dot = max(1.2, diameter * 0.085)
            let tint = isBreak ? Color(red: 0.4, green: 0.88, blue: 0.55) : Color.white
            for index in 0..<dots {
                let angle = Double(index) / Double(dots) * 2 * .pi - .pi / 2
                let center = CGPoint(x: size.width / 2 + cos(angle) * radius, y: size.height / 2 + sin(angle) * radius)
                let on = index >= dots - left
                context.fill(Path(ellipseIn: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)),
                             with: .color(on ? tint.opacity(paused ? 0.45 : 0.95) : Color.white.opacity(0.17)))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The pomodoro card: the ring of dots, time left, and pause / skip / stop; after a break, a way to start again.
struct FocusCard: View {
    @ObservedObject var focus: FocusTimer

    var body: some View {
        TimelineView(.periodic(from: Clock.epoch, by: 1)) { context in
            HStack(spacing: 10) {
                DotRing(elapsed: focus.fraction(at: context.date),
                        isBreak: focus.phase?.isBreak ?? false, paused: focus.isPaused, diameter: 26)
                    .frame(width: 30, height: 30)
                if focus.state == .waiting {
                    Text(L10n.t("Break is over")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                    Spacer(minLength: 4)
                    Button(L10n.t("Start focus")) { focus.startNextFocus() }
                        .buttonStyle(CapsuleButtonStyle(fill: Color(red: 1, green: 0.38, blue: 0.32).opacity(0.85), foreground: Color.white))
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(DurationFormat.clock(Int(focus.remaining(at: context.date).rounded(.up))))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(focus.isPaused ? 0.5 : 1))
                        Text(label).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer(minLength: 4)
                    control(focus.isPaused ? "play.fill" : "pause.fill", focus.isPaused ? "Resume" : "Pause") { focus.togglePause() }
                    control("forward.end.fill", "Skip") { focus.skip() }
                }
                control("xmark", "Stop pomodoro") { focus.stop() }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: IslandLayout.compactWidgetHeight)
            .background(cardBackground)
        }
    }

    private var label: String {
        switch focus.phase {
        case .focus: L10n.t("Focus") + " · \(focus.completedFocus % focus.plan.rounds + 1)/\(focus.plan.rounds)"
        case .shortBreak: L10n.t("Short break")
        case .longBreak: L10n.t("Long break")
        case nil: ""
        }
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 28)
        }
        .buttonStyle(IconButtonStyle())
        .help(L10n.t(help))
        .accessibilityLabel(L10n.t(help))
    }
}
