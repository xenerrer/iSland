import Foundation
import Testing
@testable import IslandCore

/// Fixtures mimic the real store: one compact JSON file per chat, in `<account>/<organization>/`, where the title sits
/// before the big tool list in most files and after it in some.
@Suite("Claude desktop chats") struct DesktopChatTests {
    let root: URL
    let folder: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("island-chats-\(UUID().uuidString)", isDirectory: true)
        folder = root.appendingPathComponent("account/organization", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func tools(_ count: Int) -> String {
        (0..<count).map { "\"server:tool_\($0)-hash\":true" }.joined(separator: ",")
    }

    @discardableResult
    func write(local: String, cli: String?, title: String, archived: Bool = false, titleAfterTools: Bool = false,
               in directory: URL? = nil, modified: Date? = nil) throws -> URL {
        let cliPart = cli.map { "\"cliSessionId\":\"\($0)\"," } ?? ""
        let head = "{\"sessionId\":\"\(local)\",\(cliPart)\"cwd\":\"/Users/me/proj\",\"lastActivityAt\":1789500006805,\"model\":\"opus\","
        let meta = "\"isArchived\":\(archived),\"title\":\"\(title)\",\"titleSource\":\"auto\",\"permissionMode\":\"default\""
        let blob = "\"enabledMcpTools\":{\(tools(2_000))}"
        let json = titleAfterTools ? head + blob + "," + meta + "}" : head + meta + "," + blob + "}"
        let url = (directory ?? folder).appendingPathComponent("\(local).json")
        try Data(json.utf8).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    @Test func findsAChatByItsClaudeCodeSessionId() throws {
        try write(local: "local_aaaa", cli: "cli-1", title: "Notch app para MacBook")
        try write(local: "local_bbbb", cli: "cli-2", title: "Outro chat")
        let found = DesktopChatIndex(root: root).chats(forSessions: ["cli-1", "cli-unknown"])
        #expect(found.count == 1)
        #expect(found["cli-1"]?.localId == "local_aaaa")
        #expect(found["cli-1"]?.title == "Notch app para MacBook")
        #expect(found["cli-1"]?.cliSessionId == "cli-1")
    }

    @Test func readsTheTitleEvenWhenItSitsAfterTheToolList() throws {
        try write(local: "local_late", cli: "cli-late", title: "Título depois do bloco", titleAfterTools: true)
        #expect(DesktopChatIndex(root: root).chats(forSessions: ["cli-late"])["cli-late"]?.title == "Título depois do bloco")
    }

    @Test func skipsRecordsThatCannotBeMatched() throws {
        try write(local: "local_none", cli: nil, title: "Never started") // no cliSessionId
        let deleted = folder.appendingPathComponent("deleted_xyz", isDirectory: true)
        try FileManager.default.createDirectory(at: deleted, withIntermediateDirectories: true)
        try write(local: "local_gone", cli: "cli-gone", title: "Deleted", in: deleted)
        let index = DesktopChatIndex(root: root)
        #expect(index.chats(forSessions: ["cli-gone"]).isEmpty)
        #expect(index.chats(forSessions: []).isEmpty)
    }

    @Test func noticesATitleThatChanged() throws {
        let past = Date(timeIntervalSinceNow: -100)
        try write(local: "local_t", cli: "cli-t", title: "Novo chat", modified: past)
        let index = DesktopChatIndex(root: root)
        #expect(index.chats(forSessions: ["cli-t"])["cli-t"]?.title == "Novo chat")
        try write(local: "local_t", cli: "cli-t", title: "Revisar contrato de aluguel", modified: Date())
        #expect(index.chats(forSessions: ["cli-t"])["cli-t"]?.title == "Revisar contrato de aluguel")
    }

    @Test func prefersTheLiveCopyOverAnArchivedOne() throws {
        try write(local: "local_old", cli: "cli-dup", title: "Arquivado", archived: true)
        try write(local: "local_new", cli: "cli-dup", title: "Ativo")
        let chat = try #require(DesktopChatIndex(root: root).chats(forSessions: ["cli-dup"])["cli-dup"])
        #expect(chat.localId == "local_new")
        #expect(!chat.isArchived)
    }

    @Test func aRecordCaughtMidWriteKeepsTheLastGoodTitle() throws {
        let url = try write(local: "local_w", cli: "cli-w", title: "Bom", modified: Date(timeIntervalSinceNow: -100))
        let index = DesktopChatIndex(root: root)
        #expect(index.chats(forSessions: ["cli-w"])["cli-w"]?.title == "Bom")
        // The head still names the chat, but the rest is cut off.
        try Data(#"{"sessionId":"local_w","cliSessionId":"cli-w","cwd":"/x","title":"Ruim"#.utf8).write(to: url)
        #expect(index.chats(forSessions: ["cli-w"])["cli-w"]?.title == "Bom")
    }

    @Test func aMissingFolderIsJustEmpty() {
        let nowhere = root.appendingPathComponent("does-not-exist")
        #expect(DesktopChatIndex(root: nowhere).chats(forSessions: ["x"]).isEmpty)
    }

    @Test func titlesAreTidied() throws {
        #expect(SessionTitle.clean("  Hello\nworld \n") == "Hello world")
        #expect(SessionTitle.clean("   \n ") == nil)
        #expect(SessionTitle.clean(String(repeating: "x", count: 500))?.count == 200)
        try write(local: "local_n", cli: "cli-n", title: "Linha um\\nlinha dois")
        #expect(DesktopChatIndex(root: root).chats(forSessions: ["cli-n"])["cli-n"]?.title == "Linha um linha dois")
    }
}

@Suite("claude:// links") struct DesktopLinkTests {
    @Test func buildsTheAppsOwnOpenChatLink() {
        #expect(ClaudeDesktop.deepLink(toChat: "local_990a8afe-0286-4040-924d-25f96101ee06")?.absoluteString
                == "claude://code/continue?session=local_990a8afe-0286-4040-924d-25f96101ee06")
    }

    @Test func refusesAnythingThatIsNotAChatId() {
        for bad in ["", "local_", "session_abc", "cse_abc", "local_a b", "local_a&x=1", "local_a/../b", "local_é",
                    "local_" + String(repeating: "a", count: 65), "LOCAL_abc", "last"] {
            #expect(ClaudeDesktop.deepLink(toChat: bad) == nil, "\(bad)")
        }
        #expect(ClaudeDesktop.deepLink(toChat: "local_" + String(repeating: "a", count: 64)) != nil)
    }
}

@Suite("Transcript titles") struct TranscriptTitleTests {
    func tail(_ lines: [String]) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }
    func custom(_ title: String) -> String { "{\"type\":\"custom-title\",\"customTitle\":\"\(title)\",\"sessionId\":\"s\"}" }
    func agent(_ name: String) -> String { "{\"type\":\"agent-name\",\"agentName\":\"\(name)\",\"sessionId\":\"s\"}" }
    let chatter = "{\"type\":\"assistant\",\"message\":{\"content\":\"hello\"}}"

    @Test func theLastTitleWins() {
        let data = tail([chatter, custom("Primeiro"), chatter, custom("Segundo"), chatter])
        #expect(TranscriptTitle.title(inTail: data) == "Segundo")
    }

    @Test func aLaterAgentNameBeatsAnEarlierCustomTitleAndViceVersa() {
        #expect(TranscriptTitle.title(inTail: tail([custom("A"), agent("B")])) == "B")
        #expect(TranscriptTitle.title(inTail: tail([agent("B"), custom("A")])) == "A")
    }

    @Test func aMarkerQuotedInsideAMessageIsNotATitle() {
        let quoted = "{\"type\":\"assistant\",\"message\":{\"content\":\"the entry {\\\"type\\\":\\\"custom-title\\\",\\\"customTitle\\\":\\\"Fake\\\"}\"}}"
        #expect(TranscriptTitle.title(inTail: tail([custom("Real"), quoted])) == "Real")
        #expect(TranscriptTitle.title(inTail: tail([quoted])) == nil)
    }

    @Test func aLineCutInHalfAtTheStartOfTheTailIsHandled() {
        let cut = "ttle\",\"customTitle\":\"Cortado\",\"sessionId\":\"s\"}" // the beginning of this line is gone
        #expect(TranscriptTitle.title(inTail: tail([cut, chatter])) == nil)
        #expect(TranscriptTitle.title(inTail: tail([cut, custom("Inteiro")])) == "Inteiro")
    }

    @Test func nothingToFindIsNil() {
        #expect(TranscriptTitle.title(inTail: Data()) == nil)
        #expect(TranscriptTitle.title(inTail: tail([chatter, chatter])) == nil)
        #expect(TranscriptTitle.title(inTail: tail([custom("   ")])) == nil)
    }

    @Test func readsTheEndOfARealFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        // 1.5 MB of conversation after an early title, then a later one near the end
        let filler = String(repeating: "x", count: 100_000)
        var lines = [custom("Muito antigo")]
        for _ in 0..<15 { lines.append("{\"type\":\"user\",\"text\":\"\(filler)\"}") }
        lines.append(custom("Atual"))
        lines.append(chatter)
        try tail(lines).write(to: url)
        #expect(TranscriptTitle.read(atPath: url.path) == "Atual")

        // with no later title, the early one is out of reach: the island falls back to the folder name
        lines.removeLast(2)
        try tail(lines).write(to: url)
        #expect(TranscriptTitle.read(atPath: url.path) == nil)
    }

    @Test func refusesPathsThatAreNotTranscripts() {
        #expect(TranscriptTitle.read(atPath: "relative/path.jsonl") == nil)
        #expect(TranscriptTitle.read(atPath: "/etc/hosts") == nil)
        #expect(TranscriptTitle.read(atPath: "/does/not/exist.jsonl") == nil)
    }

    @Test func theHookCarriesTheTranscriptPath() throws {
        let payload = try JSONValue.parse(Data(#"{"session_id":"s","transcript_path":"/Users/me/.claude/projects/p/s.jsonl","cwd":"/w","hook_event_name":"PreToolUse"}"#.utf8))
        #expect(ClaudeHook.event(from: payload).transcriptPath == "/Users/me/.claude/projects/p/s.jsonl")
        let bare = try JSONValue.parse(Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8))
        #expect(ClaudeHook.event(from: bare).transcriptPath == nil)
    }
}

@Suite("The chat on screen") struct CurrentChatTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("island-ls-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func entry(_ id: String) -> String { "{\"state\":{\"rowSplit\":0.5,\"lastPrimaryCodeSession\":{\"id\":\"\(id)\",\"type\":\"local\"}},\"version\":4}" }

    @Test func theNewestEntryWins() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = entry("local_aaaaaaaa-0000-4000-8000-000000000001") + "\u{1}junk\u{2}" + entry("local_bbbbbbbb-0000-4000-8000-000000000002")
        try Data(log.utf8).write(to: dir.appendingPathComponent("000001.log"))
        #expect(ClaudeDesktop.currentChatId(in: dir) == "local_bbbbbbbb-0000-4000-8000-000000000002")
    }

    @Test func anEntryThatIsNotAChatIdIsSkipped() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = entry("local_aaaaaaaa-0000-4000-8000-000000000001") + entry("not a chat id")
        try Data(log.utf8).write(to: dir.appendingPathComponent("000001.log"))
        #expect(ClaudeDesktop.currentChatId(in: dir) == "local_aaaaaaaa-0000-4000-8000-000000000001")
    }

    @Test func nothingToFindIsNil() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ClaudeDesktop.currentChatId(in: dir) == nil)
        try Data("nothing here".utf8).write(to: dir.appendingPathComponent("000001.log"))
        #expect(ClaudeDesktop.currentChatId(in: dir) == nil)
        #expect(ClaudeDesktop.currentChatId(in: dir.appendingPathComponent("missing")) == nil)
    }
}
