import AppKit
import IslandCore
import SwiftUI

enum IslandStyle: String, CaseIterable {
    /// Pure black: indistinguishable from the hardware notch.
    case solid
    /// Dark-tinted Liquid Glass (macOS 26+).
    case glass
    /// Lighter, more transparent Liquid Glass (macOS 26+).
    case clear

    var title: String {
        switch self {
        case .solid: "Solid black"
        case .glass: "Glass"
        case .clear: "Clear glass"
        }
    }
}

/// How the island looks: the user's style choice plus the system accessibility settings that override it.
@MainActor
final class Appearance: ObservableObject {
    static let styleKey = "style"

    /// Seconds the green "finished" dot stays beside the notch; 0 never shows it. A hidden knob:
    /// `defaults write com.lucasschoenherr.island doneGlance 0`.
    nonisolated static var doneGlance: TimeInterval {
        UserDefaults.standard.object(forKey: "doneGlance") as? Double ?? 8
    }

    @Published var style: IslandStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey) }
    }
    /// A soft sound when a question arrives and when a long turn finishes. Off by default.
    @Published var sounds: Bool {
        didSet { UserDefaults.standard.set(sounds, forKey: "sounds") }
    }
    /// Keeps the island out of screen shares and recordings: it shows chat names, project names and commands.
    /// Off by default because it also hides it from your own screenshots.
    @Published var hideFromCapture: Bool {
        didSet { UserDefaults.standard.set(hideFromCapture, forKey: "hideFromCapture") }
    }
    /// What is playing, in the open island and as an equalizer in the closed pill.
    @Published var showMusic: Bool {
        didSet { UserDefaults.standard.set(showMusic, forKey: "showMusic") }
    }
    /// How long the pointer must rest on the notch before the island opens, in seconds. Everyone has a taste for this.
    @Published var hoverDelay: Double {
        didSet { UserDefaults.standard.set(hoverDelay, forKey: "hoverDelay") }
    }
    /// How the island opens and closes.
    @Published var motionStyle: MotionStyle {
        didSet { UserDefaults.standard.set(motionStyle.rawValue, forKey: "motionStyleV2") }
    }
    /// Step aside while another app shows a video in full screen.
    /// Which displays carry an island (see DisplayChoice): the main display by default.
    @Published var displayChoice: DisplayChoice {
        didSet { UserDefaults.standard.set(displayChoice.raw, forKey: "displayChoice") }
    }
    @Published var hideInFullscreenVideo: Bool {
        didSet { UserDefaults.standard.set(hideInFullscreenVideo, forKey: "hideInFullscreenVideo") }
    }
    /// The next event of your calendars.
    @Published var showCalendar: Bool {
        didSet { UserDefaults.standard.set(showCalendar, forKey: "showCalendar") }
    }
    /// The ✻ in the menu bar. Off by default: the gear in the open island opens the same menu.
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    @Published private(set) var reduceTransparency: Bool
    @Published private(set) var reduceMotion: Bool
    private var observer: NSObjectProtocol?

    init() {
        // `iSland -style clear` works too: command-line arguments land in UserDefaults.
        style = UserDefaults.standard.string(forKey: Self.styleKey).flatMap(IslandStyle.init(rawValue:)) ?? .glass
        sounds = UserDefaults.standard.bool(forKey: "sounds")
        hideFromCapture = UserDefaults.standard.bool(forKey: "hideFromCapture")
        showMusic = UserDefaults.standard.object(forKey: "showMusic") as? Bool ?? true
        showCalendar = UserDefaults.standard.object(forKey: "showCalendar") as? Bool ?? true
        displayChoice = DisplayChoice(raw: UserDefaults.standard.string(forKey: "displayChoice"))
        hideInFullscreenVideo = UserDefaults.standard.object(forKey: "hideInFullscreenVideo") as? Bool ?? true
        motionStyle = UserDefaults.standard.string(forKey: "motionStyleV2").flatMap(MotionStyle.init(rawValue:)) ?? .bouncy
        hoverDelay = min(2, max(0, UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.12))
        showMenuBarIcon = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        let workspace = NSWorkspace.shared
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility() }
        }
    }

    private func refreshAccessibility() {
        let workspace = NSWorkspace.shared
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
    }
}
