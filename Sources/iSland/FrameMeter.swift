import AppKit
import QuartzCore

/// Records when each frame of a window is due, to see whether an animation keeps up with the screen (development tool).
@MainActor
final class FrameMeter: NSObject {
    private var link: CADisplayLink?
    private(set) var stamps: [CFTimeInterval] = []

    func start(on view: NSView) {
        link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) { stamps.append(link.timestamp) }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Frame-to-frame times (ms) of the frames inside a window of time.
    func intervals(from start: CFTimeInterval, to end: CFTimeInterval) -> [Double] {
        let inside = stamps.filter { $0 >= start && $0 <= end }
        return zip(inside.dropFirst(), inside).map { ($0 - $1) * 1000 }
    }

    static func summary(_ intervals: [Double], refresh: Double) -> String {
        guard !intervals.isEmpty else { return "no frames" }
        let sorted = intervals.sorted()
        let budget = 1000 / refresh
        let late = intervals.filter { $0 > budget * 1.5 }.count
        return String(format: "%d frames, median %.1f ms, p95 %.1f ms, worst %.1f ms, %d late (budget %.1f ms)",
                      intervals.count, sorted[sorted.count / 2], sorted[Int(Double(sorted.count - 1) * 0.95)], sorted.last ?? 0, late, budget)
    }
}
