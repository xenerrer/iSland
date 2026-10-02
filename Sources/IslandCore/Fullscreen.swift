import Foundation

/// A window as the window server lists it: where it is (origin at the top left of the main screen), how high it sits, who owns it.
public struct WindowRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public var layer: Int
    public var ownerPID: Int32

    public init(x: Double, y: Double, width: Double, height: Double, layer: Int = 0, ownerPID: Int32 = 0) {
        self.x = x; self.y = y; self.width = width; self.height = height
        self.layer = layer
        self.ownerPID = ownerPID
    }
}

public enum Fullscreen {
    /// Whether some other app has an ordinary window over the whole screen: macOS full screen, as a video player or a
    /// browser showing a video in full screen does. A maximised window does not count, because it leaves the menu bar.
    public static func isActive(windows: [WindowRect], screen: WindowRect, ignoring pid: Int32, tolerance: Double = 1.5) -> Bool {
        windows.contains { window in
            window.layer == 0 && window.ownerPID != pid
                && abs(window.x - screen.x) <= tolerance && abs(window.y - screen.y) <= tolerance
                && window.width >= screen.width - tolerance && window.height >= screen.height - tolerance
        }
    }
}
