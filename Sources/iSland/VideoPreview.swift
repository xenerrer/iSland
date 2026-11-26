import AppKit
import CoreMedia
import ScreenCaptureKit

/// A live preview of the window that is playing, for the music tile: the picture is captured (ScreenCaptureKit) at low
/// size and rate, only while the tile is on screen, kept in memory and never saved or sent anywhere. It needs the Screen
/// Recording permission; without it the tile keeps the cover. Protected video (Netflix...) arrives black: that is the system.
@MainActor
final class VideoPreview: ObservableObject {
    enum State: Equatable { case idle, starting, running, denied, noWindow }

    @Published private(set) var state: State = .idle
    let view = PreviewLayerView()
    private var stream: SCStream?
    private var output: FrameOutput?
    private var generation = 0

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks macOS for the permission (it shows its own dialog the first time); true when it is already granted.
    static func requestPermission() -> Bool { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    /// Starts capturing the window of one of `owners` (bundle ids) that best matches the track: the one whose title holds
    /// the track's name, otherwise the largest.
    func start(owners: [String], title: String) {
        guard Self.hasPermission else { stop(); state = .denied; return }
        generation += 1
        let mine = generation
        let old = stream
        stream = nil
        output = nil
        state = .starting
        Task { @MainActor in
            try? await old?.stopCapture()
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard mine == generation else { return }
                let candidates = content.windows.filter { window in
                    owners.contains(window.owningApplication?.bundleIdentifier ?? "") && window.isOnScreen
                        && window.frame.width >= 320 && window.frame.height >= 200
                }
                let byTitle = title.isEmpty ? nil : candidates.first { ($0.title ?? "").localizedCaseInsensitiveContains(title) }
                guard let window = byTitle ?? candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                    state = .noWindow
                    return
                }
                let config = SCStreamConfiguration()
                let aspect = max(0.5, window.frame.width / max(1, window.frame.height))
                config.width = 480
                config.height = Int(480 / aspect)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 12)
                config.queueDepth = 3
                config.showsCursor = false
                config.pixelFormat = kCVPixelFormatType_32BGRA
                let next = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
                let sink = FrameOutput(view: view)
                try next.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "island.preview", qos: .userInitiated))
                try await next.startCapture()
                guard mine == generation else { try? await next.stopCapture(); return }
                stream = next
                output = sink
                state = .running
            } catch {
                IslandLog.write("anomaly", "video preview could not start: \(error.localizedDescription)")
                if mine == generation { state = Self.hasPermission ? .noWindow : .denied }
            }
        }
    }

    func stop() {
        generation += 1
        let old = stream
        stream = nil
        output = nil
        if state != .denied { state = .idle }
        view.layer?.contents = nil
        Task { try? await old?.stopCapture() }
    }
}

/// Receives the frames off the main thread and hands each one to the layer.
private final class FrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private weak var view: PreviewLayerView?

    init(view: PreviewLayerView) { self.view = view }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async { [weak view] in view?.layer?.contents = surface }
    }
}

final class PreviewLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.contentsGravity = .resizeAspectFill
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

import SwiftUI

struct LiveVideoView: NSViewRepresentable {
    let preview: VideoPreview

    func makeNSView(context: Context) -> PreviewLayerView { preview.view }
    func updateNSView(_ view: PreviewLayerView, context: Context) {}
}
