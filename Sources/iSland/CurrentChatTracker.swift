import AppKit
import Combine
import IslandCore

/// Works out which session you are looking at right now, so the open island can mark it (clicking the chat you are already
/// in only takes you where you are). In the Claude app the answer is the Code chat the app has on screen; in a terminal or an
/// editor it is the session that app hosts, when it hosts exactly one. It looks when the island opens and every couple of
/// seconds while it stays open, and whenever another app comes to the front: never in the background.
@MainActor
final class CurrentChatTracker {
    private let store: SessionStore
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private let queue = DispatchQueue(label: "island.current-chat", qos: .utility)

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        store.$expanded
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] open in open ? self?.opened() : self?.closed() }
            .store(in: &subscriptions)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.store.isOpen == true { self?.refresh() } }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private func opened() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.5
    }

    private func closed() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        if front.bundleIdentifier == ClaudeDesktop.bundleIdentifier {
            queue.async { [weak self] in
                let chatId = ClaudeDesktop.currentChatId()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.set(chatId.flatMap { id in self.store.sessions.values.first { $0.chatId == id }?.id })
                    }
                }
            }
        } else {
            let hosted = store.sessions.values.filter { session in
                session.pid.flatMap { ProcessTree.hostApplication(of: $0)?.processIdentifier } == front.processIdentifier
            }
            set(hosted.count == 1 ? hosted[0].id : nil)
        }
    }

    private func set(_ id: String?) {
        if store.currentSessionId != id { store.currentSessionId = id }
    }
}
