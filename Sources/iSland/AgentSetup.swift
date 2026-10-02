import Foundation
import IslandCore

/// Connecting an agent: put the helper in its stable place, then register iSland's hooks in the agent's file (with a backup).
/// Used by the settings menu and by the first-run guide.
enum AgentSetup {
    static func isConnected(_ kind: AgentKind) -> Bool {
        let installer = HookInstaller(kind: kind)
        return ((try? installer.registeredEvents().count) ?? 0) == installer.events.count
    }

    /// Returns the backup of the agent's file, when there was one to back up.
    @discardableResult
    static func connect(_ kind: AgentKind) throws -> URL? {
        guard let helper = HookBinary.bundledHelperURL() else {
            throw HookInstallerError.unreadable("The island-hook helper was not found inside the app.")
        }
        try HookBinary.install(from: helper)
        return try HookInstaller(kind: kind).apply(install: true).backup
    }
}
