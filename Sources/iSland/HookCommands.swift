import Foundation
import IslandCore

/// Maintenance commands, run instead of the UI:
///
///     iSland --install-hooks   [--agent claude|codex|gemini] [--dry-run] [--settings <path>]
///     iSland --uninstall-hooks [--agent claude|codex|gemini] [--dry-run] [--settings <path>]
///     iSland --hooks-status    [--agent claude|codex|gemini] [--settings <path>]
///
/// `--dry-run` prints the resulting settings file on stdout and changes nothing.
enum HookCommands {
    static func handles(_ args: [String]) -> Bool {
        ["--install-hooks", "--uninstall-hooks", "--hooks-status"].contains { args.contains($0) }
    }

    static func run(_ args: [String]) -> Int32 {
        let kind = AgentKind(arguments: args) ?? .claude
        var settingsURL = kind.settingsURL()
        if let i = args.firstIndex(of: "--settings"), i + 1 < args.count {
            settingsURL = URL(fileURLWithPath: args[i + 1])
        }
        let installer = HookInstaller(kind: kind, settingsURL: settingsURL)
        do {
            if args.contains("--hooks-status") { return try status(installer) }

            let install = args.contains("--install-hooks")
            if args.contains("--dry-run") {
                let change = try installer.preview(install: install)
                print(change.text, terminator: "")
                log(summary(change, install: install) + " (dry run, nothing written)")
                return 0
            }

            // The helper goes first, so settings.json never points at a missing file.
            if install { try installHelper() }
            let (change, backup) = try installer.apply(install: install)
            if !install, !HookInstaller.anyInstalled() { HookBinary.remove() } // another agent may still use it
            log(summary(change, install: install))
            if let backup { log("Backup: \(backup.path)") }
            if install && change.didChange {
                log("\(kind.displayName) sessions already running may keep their old hook list: start a new session to be sure.")
                if kind == .codex { log("Codex asks you to trust new hooks: run /hooks in Codex once and approve iSland's.") }
            }
            return 0
        } catch {
            log("error: \(error)")
            return 1
        }
    }

    private static func status(_ installer: HookInstaller) throws -> Int32 {
        let registered = Set(try installer.registeredEvents())
        for event in installer.events { print("\(registered.contains(event) ? "✓" : "·") \(event)") }
        let helper = FileManager.default.isExecutableFile(atPath: IslandPaths.hookBinaryURL.path)
        print("helper: \(helper ? IslandPaths.hookBinaryURL.path : "not installed")")
        return 0
    }

    private static func summary(_ change: HookInstaller.Change, install: Bool) -> String {
        if !change.didChange { return install ? "Already installed: nothing to change." : "Not installed: nothing to remove." }
        return "\(install ? "Installed" : "Removed") hooks for: " + change.changed.joined(separator: ", ")
    }

    private static func installHelper() throws {
        guard let source = HookBinary.bundledHelperURL() else {
            throw HookInstallerError.unreadable("island-hook helper not found next to the app")
        }
        try HookBinary.install(from: source)
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
