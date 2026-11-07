import Foundation

/// A project (a chat, or a folder an agent worked in) that was active recently. The island keeps these on disk, so after a
/// restart of the Mac, of the Claude app or of iSland itself you can see what you were working on and go back to it.
public struct RecentProject: Codable, Equatable, Identifiable, Sendable {
    /// The Claude app's chat id when there is one, otherwise the folder (per agent).
    public var key: String
    public var agent: String
    /// The folder's name: the headline when the chat has no name.
    public var project: String
    public var cwd: String?
    public var title: String?
    public var chatId: String?
    public var lastActive: Date

    public var id: String { key }

    public init(agent: String, project: String, cwd: String?, title: String?, chatId: String?, lastActive: Date) {
        self.agent = agent
        self.project = project
        self.cwd = cwd
        self.title = title
        self.chatId = chatId
        self.lastActive = lastActive
        self.key = Self.key(agent: agent, cwd: cwd, chatId: chatId, project: project)
    }

    public static func key(agent: String, cwd: String?, chatId: String?, project: String) -> String {
        if let chatId, !chatId.isEmpty { return chatId }
        return "dir:\(agent):\(cwd ?? project)"
    }
}

public struct RecentHistory: Codable, Equatable, Sendable {
    public var items: [RecentProject] = []

    /// How long a project stays on the list without activity, and how many are kept.
    public static let keepFor: TimeInterval = 48 * 3600
    public static let maxItems = 30

    public init(items: [RecentProject] = []) { self.items = items }

    /// Adds the project, or refreshes it: newest first. A chat that was first seen without its id (recorded under its folder)
    /// replaces that folder entry once the id is known.
    public mutating func record(_ project: RecentProject) {
        if project.chatId != nil {
            items.removeAll { $0.chatId == nil && $0.agent == project.agent && $0.cwd == project.cwd && $0.cwd != nil }
        }
        if let index = items.firstIndex(where: { $0.key == project.key }) {
            var kept = items[index]
            kept.lastActive = max(kept.lastActive, project.lastActive)
            kept.title = project.title ?? kept.title
            kept.cwd = project.cwd ?? kept.cwd
            kept.project = project.project
            items[index] = kept
        } else {
            items.append(project)
        }
        items.sort { $0.lastActive > $1.lastActive }
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
    }

    public mutating func remove(key: String) { items.removeAll { $0.key == key } }

    public mutating func prune(now: Date = Date()) {
        items.removeAll { now.timeIntervalSince($0.lastActive) > Self.keepFor }
    }

    /// What to offer: the recent ones that are not live right now, newest first. `liveKeys` are the keys of the live sessions
    /// and `liveFolders` the "agent|folder" of those that have no chat id yet.
    public func resumable(liveKeys: Set<String>, liveFolders: Set<String>, limit: Int, now: Date = Date()) -> [RecentProject] {
        guard limit > 0 else { return [] }
        return items.filter { item in
            guard now.timeIntervalSince(item.lastActive) <= Self.keepFor, !liveKeys.contains(item.key) else { return false }
            if item.chatId == nil, let cwd = item.cwd, liveFolders.contains("\(item.agent)|\(cwd)") { return false }
            return true
        }.prefix(limit).map { $0 }
    }

    // MARK: On disk (owner-only)

    public static func load(from url: URL) -> RecentHistory {
        guard let data = try? Data(contentsOf: url) else { return RecentHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RecentHistory.self, from: data)) ?? RecentHistory()
    }

    public func save(to url: URL) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        let temporary = folder.appendingPathComponent(".recent.json.tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}

public extension IslandPaths {
    static var recentURL: URL { home.appendingPathComponent("recent.json") }
}
