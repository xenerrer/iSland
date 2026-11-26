import Foundation

/// Projects (chats or folders) the user pinned: they stay until removed, so after a restart of the Mac they are one click
/// away. Same shape as a recent project, kept in `~/.island/favorites.json` (owner-only).
public struct FavoriteList: Codable, Equatable, Sendable {
    public var items: [RecentProject] = []

    public init(items: [RecentProject] = []) { self.items = items }

    public static let maxItems = 24

    public func contains(key: String) -> Bool { items.contains { $0.key == key } }

    /// Adds at the end; a pinned chat keeps its place when pinned again, and a chat pinned by folder before its id was
    /// known is replaced by the same chat with the id.
    public mutating func add(_ project: RecentProject) {
        if project.chatId != nil {
            if let index = items.firstIndex(where: { $0.chatId == nil && $0.agent == project.agent && $0.cwd == project.cwd && $0.cwd != nil }) {
                items[index] = project
                return
            }
        }
        if let index = items.firstIndex(where: { $0.key == project.key }) {
            items[index].title = project.title ?? items[index].title
            return
        }
        guard items.count < Self.maxItems else { return }
        items.append(project)
    }

    public mutating func remove(key: String) { items.removeAll { $0.key == key } }

    /// Moves one place left (-1) or right (+1); stays put at the ends.
    public mutating func move(key: String, by step: Int) {
        guard let from = items.firstIndex(where: { $0.key == key }) else { return }
        let to = from + step
        guard items.indices.contains(to) else { return }
        items.swapAt(from, to)
    }

    /// A pinned chat takes the name the chat has now.
    public mutating func refreshTitle(key: String, title: String?) {
        guard let title, let index = items.firstIndex(where: { $0.key == key }), items[index].title != title else { return }
        items[index].title = title
    }

    public static func load(from url: URL) -> FavoriteList {
        guard let data = try? Data(contentsOf: url) else { return FavoriteList() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(FavoriteList.self, from: data)) ?? FavoriteList()
    }

    public func save(to url: URL) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        let temporary = folder.appendingPathComponent(".favorites.json.tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}

public extension IslandPaths {
    static var favoritesURL: URL { home.appendingPathComponent("favorites.json") }
}
