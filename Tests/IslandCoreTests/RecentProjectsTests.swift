import Foundation
import Testing
@testable import IslandCore

@Suite("Recent projects") struct RecentProjectsTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func project(_ name: String, chat: String? = nil, agent: String = "claude", ago: TimeInterval = 60, title: String? = nil) -> RecentProject {
        RecentProject(agent: agent, project: name, cwd: "/work/\(name)", title: title, chatId: chat, lastActive: now.addingTimeInterval(-ago))
    }

    @Test func newestFirstAndRefreshedInPlace() {
        var history = RecentHistory()
        history.record(project("a", ago: 300))
        history.record(project("b", ago: 100))
        history.record(project("a", ago: 10, title: "Named")) // same folder, no chat id: the same entry
        #expect(history.items.map(\.project) == ["a", "b"])
        #expect(history.items[0].title == "Named")
    }

    @Test func aChatIdReplacesItsFolderEntry() {
        var history = RecentHistory()
        history.record(project("a", ago: 200))
        history.record(project("a", chat: "local_1", ago: 10))
        #expect(history.items.count == 1)
        #expect(history.items[0].chatId == "local_1")
    }

    @Test func liveOnesAreNotOffered() {
        var history = RecentHistory()
        history.record(project("a", chat: "local_1"))
        history.record(project("b"))
        history.record(project("c"))
        let live = history.resumable(liveKeys: ["local_1"], liveFolders: ["claude|/work/b"], limit: 5, now: now)
        #expect(live.map(\.project) == ["c"])
        #expect(history.resumable(liveKeys: [], liveFolders: [], limit: 2, now: now).count == 2)
        #expect(history.resumable(liveKeys: [], liveFolders: [], limit: 0, now: now).isEmpty)
    }

    @Test func oldOnesExpireAndTheListIsBounded() {
        var history = RecentHistory()
        history.record(project("old", ago: RecentHistory.keepFor + 60))
        history.prune(now: now)
        #expect(history.items.isEmpty)
        for i in 0..<(RecentHistory.maxItems + 5) { history.record(project("p\(i)", ago: Double(i))) }
        #expect(history.items.count == RecentHistory.maxItems)
    }

    @Test func survivesARestartAndIsOwnerOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("island-recent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("recent.json")
        var history = RecentHistory()
        history.record(project("a", chat: "local_1", title: "Notch app"))
        history.save(to: url)
        #expect(RecentHistory.load(from: url).items.map(\.chatId) == ["local_1"])
        let mode = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
        #expect(mode == 0o600)
        #expect(RecentHistory.load(from: folder.appendingPathComponent("missing.json")).items.isEmpty)
    }
}
