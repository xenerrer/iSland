import Foundation

/// When a finished job is worth a notification of its own.
public enum AlertPolicy {
    /// Shorter turns are over before you could have looked away.
    public static let minimumTurnSeconds = 20

    /// A turn that took a while, in a chat you are not looking at.
    public static func shouldAnnounceFinish(turnSeconds: Int?, userIsLooking: Bool) -> Bool {
        (turnSeconds ?? 0) >= minimumTurnSeconds && !userIsLooking
    }
}
