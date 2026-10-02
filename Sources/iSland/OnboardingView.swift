import AppKit
import IslandCore
import SwiftUI

/// The first-run guide: what iSland is, which agents to connect, and the one permission it asks for up front. One step at a
/// time; everything can be done later from the settings menu.
@MainActor
final class OnboardingModel: ObservableObject {
    static let stepCount = 5
    static let doneKey = "onboardingDone"

    @Published var step = 0
    @Published private(set) var connected: Set<AgentKind> = []
    @Published private(set) var failure: String?
    let calendar: CalendarManager
    var onFinish: () -> Void = {}

    init(calendar: CalendarManager) {
        self.calendar = calendar
        refresh()
    }

    func refresh() {
        connected = Set(AgentKind.allCases.filter(AgentSetup.isConnected))
    }

    func connect(_ kind: AgentKind) {
        do {
            try AgentSetup.connect(kind)
            failure = nil
        } catch {
            failure = "\(error)"
        }
        refresh()
    }

    func next() {
        if step + 1 < Self.stepCount { step += 1 } else { finish() }
    }

    func back() { step = max(0, step - 1) }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        onFinish()
    }

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var calendar: CalendarManager

    init(model: OnboardingModel) {
        self.model = model
        self.calendar = model.calendar
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                switch model.step {
                case 0: welcome
                case 1: agents
                case 2: agenda
                case 3: camera
                default: ready
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32)
            .padding(.top, 34)
            footer
        }
        .frame(width: 540, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("✻").font(.system(size: 40, weight: .bold)).foregroundStyle(ClaudeSpinner.orange)
            title(L10n.t("Welcome to iSland"))
            text(L10n.t("Your notch becomes a control surface for AI agents. You see what each chat is doing, approve permissions without leaving what you are doing, and jump to the right chat with a click."))
            text(L10n.t("Rest the pointer on the notch to open it. The gear inside is where all the settings live."))
        }
    }

    private var agents: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(L10n.t("Connect your agents"))
            text(L10n.t("iSland learns what an agent is doing through its hooks. Connecting adds them to the agent's own settings file, after saving a backup, and touches nothing else. You can undo it from the settings menu."))
            ForEach(AgentKind.allCases, id: \.self) { kind in agentRow(kind) }
            if let failure = model.failure { Text(failure).font(.system(size: 11)).foregroundStyle(.red) }
        }
    }

    private func agentRow(_ kind: AgentKind) -> some View {
        let installed = kind == .claude || kind.isInstalled()
        return HStack(spacing: 10) {
            AgentSpinnerPreview(agent: kind.rawValue)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.displayName).font(.system(size: 13, weight: .semibold))
                if kind == .codex && model.connected.contains(kind) {
                    Text(L10n.t("In Codex, run /hooks once and approve iSland's hooks.")).font(.system(size: 11)).foregroundStyle(.secondary)
                } else if !installed {
                    Text(L10n.t("Not found on this Mac")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.connected.contains(kind) {
                Label(L10n.t("Connected"), systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green)
            } else {
                Button(L10n.t("Connect")) { model.connect(kind) }.disabled(!installed)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(L10n.t("Your calendar"))
            text(L10n.t("iSland can show the next event with a Join button, from the calendars your Mac already syncs. For Google Calendar, add your Google account in System Settings → Internet Accounts with Calendars turned on."))
            switch calendar.access {
            case .authorized:
                Label(L10n.t("Connected"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .notDetermined:
                Button(L10n.t("Show my calendar")) { calendar.requestAccess() }
                    .disabled(!CalendarManager.canAskForAccess)
            case .denied:
                Button(L10n.t("Open Settings")) { calendar.openPrivacySettings() }
            case .unavailable:
                Text(L10n.t("Available in the installed app.")).foregroundStyle(.secondary)
            }
            text(L10n.t("Nothing is read until you press the button, and nothing leaves your Mac."))
        }
    }

    private var camera: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(L10n.t("Mirror and photos"))
            text(L10n.t("The mirror icon in the notch turns your camera on while you look at yourself, and its round button takes a photo for when you need a picture in a hurry. macOS asks for the camera the first time you use it; photos go to Pictures/iSland only after you allow that."))
            text(L10n.t("The camera is on only while the mirror is showing, and nothing is recorded or sent anywhere."))
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 12) {
            title(L10n.t("All set"))
            tip("timer", L10n.t("Pomodoro with focus and breaks"))
            tip("square.and.pencil", L10n.t("Start a new chat in a recent folder"))
            tip("xmark", L10n.t("Take a chat off the list with the ×"))
            tip("gearshape.fill", L10n.t("Everything else is in the gear, including this guide"))
        }
    }

    // MARK: Pieces

    private func title(_ string: String) -> some View { Text(string).font(.system(size: 22, weight: .semibold)) }
    private func text(_ string: String) -> some View {
        Text(string).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func tip(_ symbol: String, _ string: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(ClaudeSpinner.orange)
            Text(string).font(.system(size: 13))
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<OnboardingModel.stepCount, id: \.self) { index in
                    Circle().fill(index == model.step ? Color.primary : Color.primary.opacity(0.2)).frame(width: 6, height: 6)
                }
            }
            Spacer()
            if model.step > 0 { Button(L10n.t("Back")) { model.back() } }
            Button(model.step == OnboardingModel.stepCount - 1 ? L10n.t("Finish") : L10n.t("Next step")) { model.next() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
    }
}

/// An agent's own working spinner, as a small label in the guide.
struct AgentSpinnerPreview: View {
    let agent: String

    var body: some View {
        AgentSpinner(agent: agent).frame(width: 24, height: 24)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
    }
}

/// The window that holds the guide.
@MainActor
final class OnboardingWindow {
    private var window: NSWindow?

    func show(model: OnboardingModel) {
        if let window { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        model.step = 0
        model.refresh()
        let hosting = NSHostingView(rootView: OnboardingView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        window.level = .floating
        model.onFinish = { [weak self] in self?.close() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(true, forKey: OnboardingModel.doneKey) // closing it counts: it will not come back by itself
                self?.window = nil
            }
        }
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
