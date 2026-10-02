import AppKit

extension NSAlert {
    /// The island floats above everything, and an alert opens near the top of the screen, right where the island is: left
    /// alone, the island would sit on the alert and swallow its clicks. This runs the alert one level above the island.
    @MainActor
    func runAboveIsland() -> NSApplication.ModalResponse {
        NSApp.activate()
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 10)
        return runModal()
    }
}
