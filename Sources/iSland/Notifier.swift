import AppKit
import IslandCore
import UserNotifications

/// System notifications for the two moments you would otherwise only notice by opening the notch: a job that finished (after
/// a while, in a chat you are not looking at) and an agent that needs you. Clicking one takes you there. Only the chat's name,
/// the time taken and the kind of question go in the text: never what was asked or run.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let store: SessionStore
    private let appearance: Appearance
    private let tracker: CurrentChatTracker
    /// A click on a "needs you" notification: show the island (the question is on its card).
    var onShowIsland: () -> Void = {}

    /// Notifications need a real app bundle: the bare binary of the test scripts has none.
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    init(store: SessionStore, appearance: Appearance, tracker: CurrentChatTracker) {
        self.store = store
        self.appearance = appearance
        self.tracker = tracker
    }

    func start() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        if appearance.notify { requestAuthorization() }
    }

    /// Asked when the feature is on, the first time it can matter; macOS remembers the answer.
    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            IslandLog.write("notify", "authorization \(granted ? "granted" : "not granted")\(error.map { ": \($0.localizedDescription)" } ?? "")")
        }
    }

    func finished(_ session: AgentSession) {
        guard available, appearance.notify,
              AlertPolicy.shouldAnnounceFinish(turnSeconds: session.lastTurnSeconds, userIsLooking: tracker.isLooking(at: session.id))
        else { return }
        let seconds = session.lastTurnSeconds ?? 0
        post(id: session.id, kind: "finished", title: session.title ?? session.project,
             body: L10n.detail("Done") + " · " + DurationFormat.short(seconds))
    }

    func needsYou(sessionId: String, prompt: String) {
        guard available, appearance.notify, !tracker.isLooking(at: sessionId) else { return }
        let session = store.sessions[sessionId]
        post(id: sessionId, kind: "question", title: L10n.t("Needs your approval"),
             body: (session?.title ?? session?.project ?? "") + " · " + L10n.t(prompt))
    }

    private func post(id: String, kind: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = id
        content.userInfo = ["session": id, "kind": kind]
        let request = UNNotificationRequest(identifier: "island-\(id)-\(kind)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { IslandLog.write("notify", "could not post: \(error.localizedDescription)") }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let session = info["session"] as? String
        let kind = info["kind"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if kind == "question" { self.onShowIsland() } else if let session { self.store.focus(session) }
            }
        }
        completionHandler()
    }
}
