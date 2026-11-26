import Foundation
import Testing
@testable import IslandCore

@Suite("Favorites") struct FavoritesTests {
    func fav(_ name: String, chat: String? = nil, title: String? = nil) -> RecentProject {
        RecentProject(agent: "claude", project: name, cwd: "/work/\(name)", title: title, chatId: chat, lastActive: Date())
    }

    @Test func addKeepsOrderAndNeverDuplicates() {
        var list = FavoriteList()
        list.add(fav("a", chat: "local_1", title: "Dra Patricia"))
        list.add(fav("b", chat: "local_2"))
        list.add(fav("a", chat: "local_1", title: "Dra Patricia 2"))
        #expect(list.items.map(\.key) == ["local_1", "local_2"])
        #expect(list.items[0].title == "Dra Patricia 2")
    }

    @Test func aFolderPinBecomesTheChatOnceItsIdIsKnown() {
        var list = FavoriteList()
        list.add(fav("a"))
        list.add(fav("a", chat: "local_1"))
        #expect(list.items.count == 1 && list.items[0].chatId == "local_1")
    }

    @Test func moveRemoveAndTheLimit() {
        var list = FavoriteList()
        for n in ["a", "b", "c"] { list.add(fav(n)) }
        list.move(key: list.items[2].key, by: -1)
        #expect(list.items.map(\.project) == ["a", "c", "b"])
        list.move(key: list.items[0].key, by: -1) // already first
        #expect(list.items.map(\.project) == ["a", "c", "b"])
        list.remove(key: list.items[1].key)
        #expect(list.items.map(\.project) == ["a", "b"])
        for n in 0..<(FavoriteList.maxItems + 5) { list.add(fav("p\(n)")) }
        #expect(list.items.count == FavoriteList.maxItems)
    }

    @Test func survivesARestartAndIsOwnerOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("island-fav-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("favorites.json")
        var list = FavoriteList()
        list.add(fav("a", chat: "local_1", title: "ConexãoBIM"))
        list.save(to: url)
        #expect(FavoriteList.load(from: url).items.first?.title == "ConexãoBIM")
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(FavoriteList.load(from: folder.appendingPathComponent("none.json")).items.isEmpty)
    }
}
