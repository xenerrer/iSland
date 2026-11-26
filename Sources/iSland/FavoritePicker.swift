import AppKit
import IslandCore

/// The menu behind the "+" of the favorites tile: what could be pinned (the chats of the Claude app you touched lately, the
/// sessions running now, the projects of the last two days), minus what is already pinned.
@MainActor
enum FavoritePicker {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    static func candidates(store: SessionStore, chats: DesktopChatIndex = DesktopChatIndex()) -> (chats: [RecentProject], others: [RecentProject]) {
        var seen = Set(store.favorites.items.map(\.key))
        func fresh(_ project: RecentProject) -> Bool { seen.insert(project.key).inserted }
        var fromChats: [RecentProject] = []
        for entry in chats.recentChats(limit: 12) {
            let folder = entry.folder
            let project = RecentProject(agent: "claude", project: folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "chat",
                                        cwd: folder, title: entry.chat.title, chatId: entry.chat.localId, lastActive: entry.modified)
            if fresh(project) { fromChats.append(project) }
        }
        var others: [RecentProject] = []
        for session in store.sessions.values.sorted(by: { $0.updated > $1.updated }) {
            let project = store.project(for: session)
            if fresh(project) { others.append(project) }
        }
        for project in store.history.items where fresh(project) { others.append(project) }
        return (fromChats, others)
    }

    /// Shows the menu under the pointer; the chosen project is pinned. Returns when the menu closes.
    static func show(store: SessionStore) {
        let (chats, others) = candidates(store: store)
        let menu = NSMenu()
        var keep: [Action] = []
        func add(_ title: String) {
            let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        func addProjects(_ projects: [RecentProject]) {
            for project in projects {
                let label = project.title ?? project.project
                let item = NSMenuItem(title: String(label.prefix(60)), action: #selector(Action.fire), keyEquivalent: "")
                let action = Action { store.addFavorite(project) }
                item.target = action
                item.image = NSImage(systemSymbolName: project.chatId == nil ? "folder" : "bubble.left", accessibilityDescription: nil)
                keep.append(action)
                menu.addItem(item)
            }
        }
        if !chats.isEmpty { add(L10n.t("Recent chats")); addProjects(chats) }
        if !others.isEmpty {
            if !chats.isEmpty { menu.addItem(.separator()) }
            add(L10n.t("Were active"))
            addProjects(others)
        }
        if chats.isEmpty && others.isEmpty { add(L10n.t("Nothing new to pin")) }
        store.menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        store.menuOpen = false
        withExtendedLifetime(keep) {}
    }
}
