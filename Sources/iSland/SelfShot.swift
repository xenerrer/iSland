import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Looks at the island the way the user will, without the Screen Recording permission.
///
/// Liquid Glass samples whatever is behind the window, so a plain SwiftUI render shows nothing useful. Instead the
/// app draws a synthetic wallpaper in a window of its own, puts the real island panel on top, and captures that
/// region of the screen. macOS only withholds the windows of *other* apps, so our own two windows come through.
/// `CGWindowListCreateImage` is marked unavailable in the macOS 15+ SDK but still exists at runtime, hence dlsym.
enum SelfShot {
    private typealias CaptureFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Captures a rectangle of the screen (global coordinates, origin top-left). nil when the system refuses.
    static func capture(_ rect: CGRect) -> CGImage? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let function = unsafeBitCast(symbol, to: CaptureFunction.self)
        let onScreenOnly: UInt32 = 1 << 0
        let bestResolution: UInt32 = 1 << 3
        return function(rect, onScreenOnly, 0, bestResolution)?.takeRetainedValue()
    }

    static func write(_ image: CGImage, to path: String) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// A window just below the island, drawing `kind` ("light", "dark" or "busy") where the wallpaper would be.
    @MainActor
    static func backdropWindow(frame: NSRect, kind: String, notchHeight: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .mainMenu + 2
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: SyntheticWallpaper(kind: kind, menuBarHeight: notchHeight))
        window.orderFrontRegardless()
        return window
    }

    /// AppKit rectangle (origin bottom-left) to the global top-left coordinates CGWindowList uses.
    static func globalRect(_ rect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Stand-in for a desktop: a gradient, a fake menu bar and a busy "window" for the glass to refract.
struct SyntheticWallpaper: View {
    let kind: String
    let menuBarHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            wallpaper
            if kind == "busy" { fakeWindow }
            fakeMenuBar
        }
    }

    @ViewBuilder private var wallpaper: some View {
        switch kind {
        case "light":
            LinearGradient(colors: [Color(red: 0.98, green: 0.90, blue: 0.74), Color(red: 0.62, green: 0.82, blue: 0.96)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case "dark":
            LinearGradient(colors: [Color(red: 0.04, green: 0.05, blue: 0.11), Color(red: 0.27, green: 0.10, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.35, blue: 0.75), Color(red: 0.85, green: 0.30, blue: 0.55),
                                        Color(red: 0.98, green: 0.62, blue: 0.20)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.white.opacity(0.35)).frame(width: 260).offset(x: -170, y: 40)
                Circle().fill(Color.yellow.opacity(0.4)).frame(width: 200).offset(x: 190, y: 120)
            }
        }
    }

    private var fakeMenuBar: some View {
        HStack(spacing: 14) {
            Text("").frame(width: 4)
            ForEach(["Finder", "File", "Edit", "View", "Go", "Window"], id: \.self) { Text($0).font(.system(size: 13, weight: .medium)) }
            Spacer()
            ForEach(["􀙇", "􀐫", "􀙫"], id: \.self) { Text($0).font(.system(size: 13)) }
            Text("Tue 21:42").font(.system(size: 13))
            Text("").frame(width: 4)
        }
        .foregroundStyle(kind == "light" ? Color.black.opacity(0.85) : Color.white.opacity(0.9))
        .frame(height: menuBarHeight)
        .frame(maxWidth: .infinity)
        .background(kind == "light" ? Color.white.opacity(0.25) : Color.black.opacity(0.18))
    }

    private var fakeWindow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<9, id: \.self) { row in
                HStack(spacing: 8) {
                    Circle().fill(row % 3 == 0 ? Color.red : row % 3 == 1 ? Color.green : Color.blue).frame(width: 10, height: 10)
                    Text("Row \(row + 1)  The quick brown fox jumps over the lazy dog")
                        .font(.system(size: 12)).foregroundStyle(Color.black.opacity(0.8))
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.88)))
        .offset(y: menuBarHeight + 24)
    }
}
