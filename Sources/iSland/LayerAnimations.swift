import AppKit
import SwiftUI

/// Small endless animations played by Core Animation instead of SwiftUI. A SwiftUI `TimelineView` or repeating animation
/// makes the app re-evaluate and re-layout a view tree on every tick, on the main thread; here the frames are prepared
/// once and the render server plays them, so a spinner that runs for hours costs the app almost no CPU.

/// A looping strip of glyph frames ("✻", braille dots...), flipped without the app doing anything.
struct GlyphSpinner: NSViewRepresentable {
    let glyphs: [String]
    let interval: Double
    let font: NSFont
    let color: NSColor

    func makeNSView(context: Context) -> LayerSpinnerView {
        LayerSpinnerView(frames: GlyphImages.frames(glyphs, font: font, color: color), interval: interval)
    }

    func updateNSView(_ view: LayerSpinnerView, context: Context) {}
}

/// A dot that swells and fades forever (Codex's working bullet, the attention dot).
struct PulsingDot: NSViewRepresentable {
    let glyph: String
    let font: NSFont
    let color: NSColor
    let low: Float
    let period: Double
    var shadow: Bool = false

    func makeNSView(context: Context) -> LayerSpinnerView {
        LayerSpinnerView(pulse: GlyphImages.frames([glyph], font: font, color: color)[0], low: low, period: period, glow: shadow)
    }

    func updateNSView(_ view: LayerSpinnerView, context: Context) {}
}

/// The music bars: four capsules that rise and fall at their own pace.
struct BarsEqualizer: NSViewRepresentable {
    let color: NSColor
    let animated: Bool

    func makeNSView(context: Context) -> EqualizerLayerView { EqualizerLayerView(color: color, animated: animated) }
    func updateNSView(_ view: EqualizerLayerView, context: Context) {}
}

enum GlyphImages {
    /// Canvas, in points, that every glyph is centred in (bigger than the 16 pt slot, so large glyphs are not cut).
    static let canvas: CGFloat = 28
    static let scale: CGFloat = 3
    private nonisolated(unsafe) static var cache: [String: [CGImage]] = [:]

    static func frames(_ glyphs: [String], font: NSFont, color: NSColor) -> [CGImage] {
        let key = glyphs.joined() + font.fontName + String(describing: font.pointSize) + color.description
        if let cached = cache[key] { return cached }
        let images = glyphs.map { render($0, font: font, color: color) }
        cache[key] = images
        return images
    }

    private static func render(_ glyph: String, font: NSFont, color: NSColor) -> CGImage {
        let pixels = Int(canvas * scale)
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let text = NSAttributedString(string: glyph, attributes: attributes)
        let size = text.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(at: NSPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
}

/// Hosts one animated layer, centred in the 16 pt slot SwiftUI gives it. Animations are re-attached when the view comes
/// back into a window, because Core Animation drops them when a layer leaves the screen.
final class LayerSpinnerView: NSView {
    private let content = CALayer()
    private let install: (CALayer) -> Void

    init(frames: [CGImage], interval: Double) {
        install = { layer in
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames
            animation.calculationMode = .discrete
            animation.duration = interval * Double(frames.count)
            animation.repeatCount = .infinity
            layer.add(animation, forKey: "spin")
        }
        super.init(frame: .zero)
        setUp(first: frames.first)
    }

    init(pulse image: CGImage, low: Float, period: Double, glow: Bool) {
        install = { layer in
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = low
            animation.toValue = 1.0
            animation.duration = period / 2
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "pulse")
        }
        super.init(frame: .zero)
        setUp(first: image)
        if glow {
            content.shadowColor = NSColor.red.cgColor
            content.shadowOpacity = 0.7
            content.shadowRadius = 4
            content.shadowOffset = .zero
        }
    }

    required init?(coder: NSCoder) { nil }

    private func setUp(first image: CGImage?) {
        wantsLayer = true
        layer = CALayer()
        content.contents = image
        content.bounds = CGRect(x: 0, y: 0, width: GlyphImages.canvas, height: GlyphImages.canvas)
        // The images are drawn at 3x: tell the layer so (and fit them to the bounds), or on a 1x display they show 3x as big.
        content.contentsScale = GlyphImages.scale
        content.contentsGravity = .resizeAspect
        layer?.addSublayer(content)
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    override func layout() {
        super.layout()
        content.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        content.removeAllAnimations()
        install(content)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class EqualizerLayerView: NSView {
    private let bars: [CALayer]
    private let animated: Bool

    init(color: NSColor, animated: Bool) {
        self.animated = animated
        bars = (0..<4).map { _ in
            let bar = CALayer()
            bar.backgroundColor = color.cgColor
            bar.cornerRadius = 1.25
            bar.bounds = CGRect(x: 0, y: 0, width: 2.5, height: 12)
            return bar
        }
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        bars.forEach { layer?.addSublayer($0) }
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 12) }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 2, width: CGFloat = 2.5
        let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * spacing
        var x = bounds.midX - total / 2 + width / 2
        for bar in bars {
            bar.position = CGPoint(x: x, y: bounds.midY)
            x += width + spacing
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            if !animated { bar.transform = CATransform3DMakeScale(1, [0.42, 0.83, 0.58, 0.75][index], 1); continue }
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = 0.25
            animation.toValue = 1.0
            animation.duration = Double.pi / (2 * (2.3 + Double(index) * 0.9)) // |sin| of the old formula: one rise per half period
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(animation, forKey: "bar")
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A fixed origin for every `TimelineView`: `.now` is evaluated again each time the parent redraws, which re-anchors the
/// schedule on every agent event.
enum Clock {
    static let epoch = Date(timeIntervalSinceReferenceDate: 0)
}
