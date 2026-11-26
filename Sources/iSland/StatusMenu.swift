import AppKit
import Combine
import IslandCore
import ServiceManagement

/// The settings menu: pick the style, choose what to show, connect or disconnect the agents (Claude Code, Codex, Gemini), quit.
/// An accessory app has no Dock icon, so this is also the only way to quit it without a terminal. It opens from the
/// gear in the open island, and optionally from a ✻ in the menu bar (off by default).
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let menu = NSMenu()
    private let appearance: Appearance
    private let widgets: Widgets
    private var subscriptions = Set<AnyCancellable>()
    /// Shows the pomodoro setup panel in the island; set by the app.
    var openPomodoroSetup: () -> Void = {}
    /// Shows the first-run guide; set by the app.
    var openGuide: () -> Void = {}

    init(appearance: Appearance, widgets: Widgets) {
        self.appearance = appearance
        self.widgets = widgets
        super.init()
        menu.delegate = self
        appearance.$showMenuBarIcon
            .sink { [weak self] show in self?.setMenuBarIcon(show) }
            .store(in: &subscriptions)
    }

    private func setMenuBarIcon(_ show: Bool) {
        if show, item == nil {
            let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            created.button?.title = "✻" // the glyph Claude Code shows while it works
            created.button?.font = .systemFont(ofSize: 14, weight: .semibold)
            created.menu = menu
            item = created
        } else if !show, let existing = item {
            NSStatusBar.system.removeStatusItem(existing)
            item = nil
        }
    }

    /// Shows the menu under the pointer. Returns when it closes, after any item has run.
    func popUpAtPointer() {
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "iSland \(Self.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let styleItem = NSMenuItem(title: L10n.t("Style"), action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in IslandStyle.allCases {
            let entry = NSMenuItem(title: L10n.t(style.title), action: #selector(selectStyle(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = style.rawValue
            entry.state = style == appearance.style ? .on : .off
            styleMenu.addItem(entry)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let motionItem = NSMenuItem(title: L10n.t("Animation"), action: nil, keyEquivalent: "")
        let motionMenu = NSMenu()
        for style in MotionStyle.allCases {
            let entry = NSMenuItem(title: L10n.t(style == .smooth ? "Smooth (Apple)" : "Bouncy (boring.notch)"), action: #selector(selectMotion(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = style.rawValue
            entry.state = style == appearance.motionStyle ? .on : .off
            motionMenu.addItem(entry)
        }
        motionItem.submenu = motionMenu
        menu.addItem(motionItem)

        // Which displays carry the island: only worth showing when there is more than one.
        if NSScreen.screens.count > 1 {
            let displaysItem = NSMenuItem(title: L10n.t("Displays"), action: nil, keyEquivalent: "")
            let displaysMenu = NSMenu()
            func add(_ title: String, _ choice: DisplayChoice) {
                let entry = NSMenuItem(title: title, action: #selector(selectDisplays(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = choice.raw
                entry.state = appearance.displayChoice == choice ? .on : .off
                displaysMenu.addItem(entry)
            }
            add(L10n.t("Main display"), .main)
            add(L10n.t("All displays"), .all)
            displaysMenu.addItem(.separator())
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                add(screen.localizedName, .specific(id))
            }
            displaysItem.submenu = displaysMenu
            menu.addItem(displaysItem)
        }

        let delayItem = NSMenuItem(title: L10n.t("Time to open"), action: nil, keyEquivalent: "")
        let delayMenu = NSMenu()
        for seconds in [0.0, 0.12, 0.3, 0.5, 0.8, 1.2] {
            let title = seconds == 0 ? L10n.t("Instant") : (seconds == 0.12 ? "120 ms · " + L10n.t("default") : "\(Int(seconds * 1000)) ms")
            let entry = NSMenuItem(title: title, action: #selector(selectOpenDelay(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = seconds
            entry.state = abs(appearance.hoverDelay - seconds) < 0.001 ? .on : .off
            delayMenu.addItem(entry)
        }
        delayItem.submenu = delayMenu
        menu.addItem(delayItem)

        let notifications = NSMenuItem(title: L10n.t("Notifications"), action: #selector(toggleNotifications), keyEquivalent: "")
        notifications.target = self
        notifications.state = appearance.notify ? .on : .off
        menu.addItem(notifications)

        let forget = NSMenuItem(title: L10n.t("Forget recent projects"), action: #selector(forgetRecent), keyEquivalent: "")
        forget.target = self
        menu.addItem(forget)

        let preview = NSMenuItem(title: L10n.t("Video preview"), action: #selector(toggleVideoPreview), keyEquivalent: "")
        preview.target = self
        preview.state = appearance.videoPreview ? .on : .off
        menu.addItem(preview)

        let sounds = NSMenuItem(title: L10n.t("Sounds"), action: #selector(toggleSounds), keyEquivalent: "")
        sounds.target = self
        sounds.state = appearance.sounds ? .on : .off
        menu.addItem(sounds)

        let video = NSMenuItem(title: L10n.t("Hide in full-screen video"), action: #selector(toggleHideInFullscreen), keyEquivalent: "")
        video.target = self
        video.state = appearance.hideInFullscreenVideo ? .on : .off
        menu.addItem(video)

        let hide = NSMenuItem(title: L10n.t("Hide from screen sharing"), action: #selector(toggleHideFromCapture), keyEquivalent: "")
        hide.target = self
        hide.state = appearance.hideFromCapture ? .on : .off
        menu.addItem(hide)

        let music = NSMenuItem(title: L10n.t("Show music"), action: #selector(toggleMusic), keyEquivalent: "")
        music.target = self
        music.state = appearance.showMusic ? .on : .off
        menu.addItem(music)

        let agenda = NSMenuItem(title: L10n.t("Show calendar"), action: #selector(toggleCalendar), keyEquivalent: "")
        agenda.target = self
        agenda.state = appearance.showCalendar ? .on : .off
        menu.addItem(agenda)

        // The pomodoro: set it up and start it, or end the round.
        if widgets.focus.isActive {
            let stop = NSMenuItem(title: L10n.t("Stop pomodoro"), action: #selector(stopFocus), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        } else {
            let setup = NSMenuItem(title: L10n.t("Pomodoro…"), action: #selector(openPomodoroSetupAction), keyEquivalent: "")
            setup.target = self
            menu.addItem(setup)
        }

        // Which accounts feed the calendar, and how to add Google's if it is missing.
        let calendar = widgets.calendar
        if appearance.showCalendar, CalendarManager.canAskForAccess {
            let status = calendar.access == .authorized && !calendar.sourceNames.isEmpty
                ? String(format: L10n.t("Calendar: %@"), calendar.sourceNames.joined(separator: ", "))
                : L10n.t("Calendar: no access yet")
            let info = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            if calendar.access == .authorized, !calendar.hasGoogleAccount {
                let add = NSMenuItem(title: L10n.t("Add a Google account…"), action: #selector(addGoogleAccount), keyEquivalent: "")
                add.target = self
                menu.addItem(add)
            }
        }

        let icon = NSMenuItem(title: L10n.t("Show icon in menu bar"), action: #selector(toggleMenuBarIcon), keyEquivalent: "")
        icon.target = self
        icon.state = appearance.showMenuBarIcon ? .on : .off
        menu.addItem(icon)

        // Only a real .app can register itself as a login item.
        if Bundle.main.bundleURL.pathExtension == "app" {
            let login = NSMenuItem(title: L10n.t("Launch at login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }
        menu.addItem(.separator())

        for kind in AgentKind.allCases { addAgentItems(kind, to: menu) }
        menu.addItem(.separator())

        let guide = NSMenuItem(title: L10n.t("First steps…"), action: #selector(openGuideAction), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)

        let quit = NSMenuItem(title: L10n.t("Quit iSland"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Claude Code always; Codex and Gemini only when they seem to be installed, otherwise a quiet "not found".
    private func addAgentItems(_ kind: AgentKind, to menu: NSMenu) {
        guard kind == .claude || kind.isInstalled() else {
            let missing = NSMenuItem(title: String(format: L10n.t("%@: not found"), kind.displayName), action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
            return
        }
        let installer = HookInstaller(kind: kind)
        let registered = (try? installer.registeredEvents()) ?? []
        let total = installer.events.count
        let status: String
        switch registered.count {
        case total: status = String(format: L10n.t("%@ hooks: installed"), kind.displayName)
        case 0: status = String(format: L10n.t("%@ hooks: not installed"), kind.displayName)
        default: status = String(format: L10n.t("%@ hooks: %d of %d installed"), kind.displayName, registered.count, total)
        }
        let info = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        if registered.count < total {
            let install = NSMenuItem(title: String(format: L10n.t("Install %@ hooks…"), kind.displayName), action: #selector(installHooksAction(_:)), keyEquivalent: "")
            install.target = self
            install.representedObject = kind.rawValue
            menu.addItem(install)
        }
        if !registered.isEmpty {
            let remove = NSMenuItem(title: String(format: L10n.t("Remove %@ hooks…"), kind.displayName), action: #selector(removeHooksAction(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = kind.rawValue
            menu.addItem(remove)
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: Actions

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = IslandStyle(rawValue: raw) else { return }
        appearance.style = style
    }

    @objc private func selectDisplays(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String { appearance.displayChoice = DisplayChoice(raw: raw) }
    }

    @objc private func selectMotion(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = MotionStyle(rawValue: raw) { appearance.motionStyle = style }
    }

    @objc private func selectOpenDelay(_ sender: NSMenuItem) {
        if let seconds = sender.representedObject as? Double { appearance.hoverDelay = seconds }
    }

    @objc private func toggleSounds() { appearance.sounds.toggle() }

    @objc private func toggleVideoPreview() {
        if !appearance.videoPreview && !VideoPreview.requestPermission() { VideoPreview.openPrivacySettings() }
        appearance.videoPreview.toggle()
    }

    @objc private func toggleNotifications() { appearance.notify.toggle() }

    @objc private func forgetRecent() { clearHistory() }

    /// Wired by the app: wipes the remembered projects.
    var clearHistory: () -> Void = {}

    @objc private func toggleHideInFullscreen() { appearance.hideInFullscreenVideo.toggle() }

    @objc private func toggleHideFromCapture() { appearance.hideFromCapture.toggle() }

    @objc private func toggleMenuBarIcon() { appearance.showMenuBarIcon.toggle() }

    @objc private func openPomodoroSetupAction() { openPomodoroSetup() }

    @objc private func stopFocus() { widgets.focus.stop() }

    @objc private func toggleMusic() { appearance.showMusic.toggle() }

    @objc private func toggleCalendar() { appearance.showCalendar.toggle() }

    @objc private func addGoogleAccount() { widgets.calendar.openInternetAccounts() }

    @objc private func openGuideAction() { openGuide() }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
            // Remember a deliberate "off": the app turns itself on at every launch otherwise (see AppDelegate.ensureLaunchAtLogin).
            UserDefaults.standard.set(service.status != .enabled && service.status != .requiresApproval, forKey: LoginItem.optOutKey)
            if service.status == .requiresApproval {
                inform(title: L10n.t("Launch at login"), message: L10n.t("Allow it in System Settings > General > Login Items."))
            }
        } catch {
            inform(title: L10n.t("Could not change the login item"), message: "\(error)")
        }
    }

    @objc private func installHooksAction(_ sender: NSMenuItem) {
        installHooks(kind: (sender.representedObject as? String).flatMap(AgentKind.init(rawValue:)) ?? .claude)
    }

    @objc private func removeHooksAction(_ sender: NSMenuItem) {
        removeHooks(kind: (sender.representedObject as? String).flatMap(AgentKind.init(rawValue:)) ?? .claude)
    }

    func installHooks(kind: AgentKind = .claude) {
        let installer = HookInstaller(kind: kind)
        let proceed = confirm(
            title: String(format: L10n.t("Install the %@ hooks?"), kind.displayName),
            message: L10n.installMessage(agent: kind.displayName, count: installer.events.count, path: Self.displayPath(installer.settingsURL)),
            button: L10n.t("Install"))
        guard proceed else { return }
        do {
            let backup = try AgentSetup.connect(kind)
            var message = String(format: L10n.t("Start a new %@ session to see it in the notch."), kind.displayName)
            if kind == .codex { message += "\n\n" + L10n.t("Codex asks you to trust new hooks: run /hooks in Codex once and approve iSland's.") }
            inform(title: L10n.t("Hooks installed"),
                   message: message + (backup.map { "\n\n" + L10n.t("Backup: ") + Self.displayPath($0) } ?? ""))
        } catch {
            inform(title: L10n.t("Could not install the hooks"), message: "\(error)")
        }
    }

    func removeHooks(kind: AgentKind = .claude) {
        let installer = HookInstaller(kind: kind)
        guard confirm(title: String(format: L10n.t("Remove the %@ hooks?"), kind.displayName),
                      message: L10n.removeMessage(path: Self.displayPath(installer.settingsURL)),
                      button: L10n.t("Remove")) else { return }
        do {
            let (_, backup) = try installer.apply(install: false)
            if !HookInstaller.anyInstalled() { HookBinary.remove() } // another agent may still use the helper
            inform(title: L10n.t("Hooks removed"), message: backup.map { L10n.t("Backup: ") + Self.displayPath($0) } ?? "")
        } catch {
            inform(title: L10n.t("Could not remove the hooks"), message: "\(error)")
        }
    }

    // MARK: Alerts

    private func confirm(title: String, message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: L10n.t("Cancel"))
        return alert.runAboveIsland() == .alertFirstButtonReturn
    }

    private func inform(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = alert.runAboveIsland()
    }

    private static func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
