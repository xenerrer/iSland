import Combine
import Foundation
import IslandCore

/// Gives every session in the island the name of its chat, and finds out which sessions live in the Claude app (so a
/// click can open that exact chat). The work is a few file reads, done off the main thread and only when something
/// could have changed: a new session, the island opening, and a slow tick while it stays open (the Claude app names a
/// chat after its first answer, and you can rename it at any time).
@MainActor
final class SessionIdentityResolver {
    private let store: SessionStore
    private let chats: DesktopChatIndex
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var running = false
    private var again = false

    init(store: SessionStore, chats: DesktopChatIndex = DesktopChatIndex()) {
        self.store = store
        self.chats = chats
    }

    func start() {
        // @Published fires before the change lands, so look on the next turn of the run loop.
        store.$sessions
            .map { Set($0.keys) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        store.$expanded
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        store.$newChatOn
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshFolders() }
            .store(in: &subscriptions)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.store.isOpen == true { self?.refresh() } }
        }
        timer?.tolerance = 1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        subscriptions.removeAll()
    }

    func refresh() {
        guard !running else { again = true; return }
        let targets = store.identityTargets()
        guard !targets.isEmpty else { return }
        running = true
        let index = chats
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.resolve(targets, using: index)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finish(found) }
            }
        }
    }

    /// The folders for "new chat", newest first.
    func refreshFolders() {
        let index = chats
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let folders = index.recentFolders()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { if self?.store.recentFolders != folders { self?.store.recentFolders = folders } }
            }
        }
    }

    private func finish(_ found: [String: SessionIdentity]) {
        let changed = store.applyIdentities(found)
        if changed > 0 {
            NSLog("iSland: chat names updated for %d of %d session(s), %d open in the Claude app", changed, store.sessions.count,
                  store.sessions.values.filter { $0.chatId != nil }.count)
        }
        running = false
        if again {
            again = false
            refresh()
        }
    }

    /// The Claude app's record wins (it has the name you see in its sidebar and the id that opens the chat); the
    /// transcript is the fallback for chats that started elsewhere, such as a terminal.
    nonisolated static func resolve(_ targets: [(id: String, transcriptPath: String?)],
                                    using index: DesktopChatIndex) -> [String: SessionIdentity] {
        let chats = index.chats(forSessions: Set(targets.map(\.id)))
        var found: [String: SessionIdentity] = [:]
        for target in targets {
            let chat = chats[target.id]
            let title = chat?.title ?? target.transcriptPath.flatMap(TranscriptTitle.read(atPath:))
            if chat != nil || title != nil { found[target.id] = SessionIdentity(title: title, chatId: chat?.localId) }
        }
        return found
    }
}
