import AppKit
import IslandCore
import SwiftUI

// MARK: - Music

/// Four bars that dance while something plays. With Reduce Motion on they stand still.
struct Equalizer: View {
    var color: Color = Color.white.opacity(0.85)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BarsEqualizer(color: NSColor(color), animated: !reduceMotion).frame(width: 16, height: 12)
    }
}

/// What is playing, and whether it is: a tile tinted by the cover, with previous / play-pause / next. Next to the pomodoro it
/// is squarer (`compact`); alone it is one wide strip.
struct MusicTile: View {
    @ObservedObject var music: NowPlayingManager
    let compact: Bool

    private var tint: BentoTint {
        music.artworkTint.map { .custom(Color(nsColor: $0)) } ?? .music
    }

    var body: some View {
        let state = music.state
        Group {
            if compact { square(state) } else { wide(state) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bentoTile(tint)
    }

    private func square(_ state: NowPlayingState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Cover(image: music.artwork, size: 52, radius: 11)
                VStack(alignment: .leading, spacing: 3) {
                    title(state, size: 13)
                    Text(subtitle(for: state))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                    playbackMark(state)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 4)
            ProgressLine(state: state)
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                control("backward.fill", label: "Previous", .previous)
                playButton(state, size: 32)
                control("forward.fill", label: "Next", .next)
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(10)
    }

    private func wide(_ state: NowPlayingState) -> some View {
        HStack(spacing: 12) {
            Cover(image: music.artwork, size: 60, radius: 12)
            VStack(alignment: .leading, spacing: 4) {
                title(state, size: 14)
                HStack(spacing: 6) {
                    playbackMark(state)
                    Text(subtitle(for: state))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                }
                ProgressLine(state: state).padding(.top, 2)
            }
            HStack(spacing: 2) {
                control("backward.fill", label: "Previous", .previous)
                playButton(state, size: 34)
                control("forward.fill", label: "Next", .next)
            }
        }
        .padding(12)
    }

    private func title(_ state: NowPlayingState, size: CGFloat) -> some View {
        Text(state.title.isEmpty ? L10n.t("Unknown track") : state.title)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
    }

    @ViewBuilder private func playbackMark(_ state: NowPlayingState) -> some View {
        if state.isPlaying {
            Equalizer(color: Color.white.opacity(0.9)).frame(width: 14, height: 10).scaleEffect(0.8)
        } else {
            Image(systemName: "pause.fill").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.6))
        }
    }

    /// "Channel · Google Chrome": on YouTube the artist is the channel, and the app says where it plays.
    private func subtitle(for state: NowPlayingState) -> String {
        [state.artist, music.appName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func playButton(_ state: NowPlayingState, size: CGFloat) -> some View {
        Button { music.send(.togglePlayPause) } label: {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.95)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t(state.isPlaying ? "Pause" : "Play"))
    }

    private func control(_ symbol: String, label: String, _ command: MediaCommand) -> some View {
        Button { music.send(command) } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(L10n.t(label))
    }
}

struct Cover: View {
    let image: NSImage?
    var size: CGFloat = 38
    var radius: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.42)).foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A line that advances with the track.
struct ProgressLine: View {
    let state: NowPlayingState

    var body: some View {
        if let duration = state.duration, duration > 0 {
            TimelineView(.periodic(from: Clock.epoch, by: 1)) { context in
                let fraction = min(1, max(0, (state.elapsedNow(at: context.date) ?? 0) / duration))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule().fill(Color.white.opacity(0.8)).frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 3)
            }
        } else {
            Color.clear.frame(height: 3)
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
    /// Each dot's diameter; by default a little under a tenth of the ring's.
    var dotSize: CGFloat?

    var body: some View {
        Canvas { context, size in
            let dots = 30
            let remaining: Double = 1 - min(1, max(0, elapsed))
            let left = Int(ceil(remaining * Double(dots) - 0.0001))
            let radius: CGFloat = min(size.width, size.height) / 2 - 1
            let dot: CGFloat = dotSize ?? max(1.2, diameter * 0.085)
            let tint: Color = isBreak ? Color(red: 0.4, green: 0.88, blue: 0.55) : Color.white
            let onColor: Color = tint.opacity(paused ? 0.45 : 0.95)
            let offColor: Color = Color.white.opacity(0.17)
            for index in 0..<dots {
                let angle: Double = Double(index) / Double(dots) * 2 * Double.pi - Double.pi / 2
                let x: CGFloat = size.width / 2 + CGFloat(cos(angle)) * radius
                let y: CGFloat = size.height / 2 + CGFloat(sin(angle)) * radius
                let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                let on = index >= dots - left
                context.fill(Path(ellipseIn: rect), with: .color(on ? onColor : offColor))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The pomodoro tile: the ring of dots with the time inside, and pause / skip / stop; after a break, a way to start again.
/// Next to the music it is squarer (`compact`); alone it is one wide strip.
struct FocusTile: View {
    @ObservedObject var focus: FocusTimer
    let compact: Bool

    var body: some View {
        TimelineView(.periodic(from: Clock.epoch, by: 1)) { context in
            let time = DurationFormat.clock(Int(focus.remaining(at: context.date).rounded(.up)))
            Group {
                if focus.state == .waiting { waiting } else if compact { square(time, context.date) } else { wide(time, context.date) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .bentoTile(.focus)
        }
    }

    /// Side by side with the music the tile is squarer, so the three parts stack; alone it is a strip, so they sit in a row.
    @ViewBuilder private var waiting: some View {
        let start = Button(L10n.t("Start focus")) { focus.startNextFocus() }
            .buttonStyle(CapsuleButtonStyle(fill: Color(red: 0.86, green: 0.25, blue: 0.20), foreground: Color.white))
        if compact {
            VStack(spacing: 8) {
                Text(L10n.t("Break is over")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                start
                control("xmark", "Stop pomodoro") { focus.stop() }
            }
            .padding(10)
        } else {
            HStack(spacing: 10) {
                Text(L10n.t("Break is over")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white).lineLimit(1)
                Spacer(minLength: 4)
                start
                control("xmark", "Stop pomodoro") { focus.stop() }
            }
            .padding(12)
        }
    }

    private func ring(_ date: Date, diameter: CGFloat, dot: CGFloat) -> some View {
        DotRing(elapsed: focus.fraction(at: date), isBreak: focus.phase?.isBreak ?? false, paused: focus.isPaused,
                diameter: diameter, dotSize: dot)
    }

    private func square(_ time: String, _ date: Date) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(phaseName).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white)
                Spacer(minLength: 4)
                Text(cycle).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.82))
            }
            .frame(height: 14)
            ZStack {
                ring(date, diameter: 62, dot: 3.4)
                Text(time)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(focus.isPaused ? 0.55 : 1))
            }
            .frame(width: 62, height: 62)
            HStack(spacing: 10) { controls }.frame(height: 24)
        }
        .padding(10)
    }

    private func wide(_ time: String, _ date: Date) -> some View {
        HStack(spacing: 12) {
            ring(date, diameter: 56, dot: 3.2).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(time)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(focus.isPaused ? 0.55 : 1))
                Text([phaseName, cycle].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.82)).lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 8) { controls }
        }
        .padding(12)
    }

    @ViewBuilder private var controls: some View {
        control(focus.isPaused ? "play.fill" : "pause.fill", focus.isPaused ? "Resume" : "Pause") { focus.togglePause() }
        control("forward.end.fill", "Skip") { focus.skip() }
        control("xmark", "Stop pomodoro") { focus.stop() }
    }

    private var phaseName: String {
        switch focus.phase {
        case .focus: L10n.t("Focus")
        case .shortBreak: L10n.t("Short break")
        case .longBreak: L10n.t("Long break")
        case nil: ""
        }
    }

    private var cycle: String {
        guard focus.phase == .focus else { return "" }
        var text = L10n.t("cycle %d of %d")
        for value in [focus.completedFocus % focus.plan.rounds + 1, focus.plan.rounds] {
            if let range = text.range(of: "%d") { text.replaceSubrange(range, with: String(value)) }
        }
        return text
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help(L10n.t(help))
        .accessibilityLabel(L10n.t(help))
    }
}
