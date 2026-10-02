import AppKit
import Darwin
import IslandCore

/// Finds the app a session runs in, by walking up from the agent's process: the shell, then Terminal, iTerm,
/// VS Code or the Claude app. Needs no permission; it only reads the process table.
enum ProcessTree {
    static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// The nearest ancestor (or the process itself) that is a regular Dock application.
    static func hostApplication(of pid: Int) -> NSRunningApplication? {
        var current = pid_t(pid)
        for _ in 0..<32 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
            guard let next = parent(of: current), next > 1, next != current else { return nil }
            current = next
        }
        return nil
    }

    /// Brings the app forward the way `open -a` does. NSRunningApplication.activate() from a background app is
    /// ignored on recent macOS, because activation has become cooperative.
    @MainActor
    static func bringForward(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Hands a `claude://` link to the Claude app, which opens that chat and comes to the front. Addressed to the app
    /// by its bundle id, so no other program that registered the same scheme can answer.
    @MainActor
    static func open(chat link: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeDesktop.bundleIdentifier) {
            NSWorkspace.shared.open([link], withApplicationAt: app, configuration: configuration)
        } else {
            NSWorkspace.shared.open(link)
        }
    }
}
