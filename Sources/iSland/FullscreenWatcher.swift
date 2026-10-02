import AppKit
import Combine
import IslandCore

/// Notices when another app is in full screen, so the notch can step aside while you watch a video. It looks at the
/// window list (positions only, which needs no permission) when the Space or the front app changes, and every couple of
/// seconds while it matters.
@MainActor
final class FullscreenWatcher: ObservableObject {
    /// Displays where another app is in full screen.
    @Published private(set) var fullscreenDisplays: Set<CGDirectDisplayID> = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// The screens that carry an island.
    var screensProvider: () -> [NSScreen] = { NSScreen.screens }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
    }

    func check() {
        guard let primary = NSScreen.screens.first else { return }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.compactMap { entry -> WindowRect? in
            guard let bounds = entry[kCGWindowBounds as String] as? [String: Double],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return WindowRect(x: x, y: y, width: width, height: height, layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                              ownerPID: Int32(entry[kCGWindowOwnerPID as String] as? Int ?? 0))
        }
        var now: Set<CGDirectDisplayID> = []
        for screen in screensProvider() {
            // Window coordinates start at the top left of the main screen; AppKit's start at the bottom left.
            let frame = WindowRect(x: screen.frame.minX, y: primary.frame.height - screen.frame.maxY,
                                   width: screen.frame.width, height: screen.frame.height)
            if Fullscreen.isActive(windows: windows, screen: frame, ignoring: ProcessInfo.processInfo.processIdentifier),
               let id = screen.displayID { now.insert(id) }
        }
        if now != fullscreenDisplays {
            fullscreenDisplays = now
            NSLog("iSland: full screen on %d display(s)", now.count)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}
