import AppKit
import QuartzCore

/// One static glyph. Moving, fading and blurring it is Core Animation's job and runs on the render server, so a roll
/// costs the main thread nothing per frame and the glyph is never redrawn while it travels.
final class GlyphLayer: CALayer {
    static let blurKeyPath = "filters.blur.inputRadius"

    var text = "" {
        didSet { if text != oldValue { setNeedsDisplay() } }
    }

    var font = NSFont.systemFont(ofSize: 26, weight: .semibold) {
        didSet { setNeedsDisplay() }
    }

    var textColor = NSColor.labelColor {
        didSet { setNeedsDisplay() }
    }

    /// Puts a zero-radius Gaussian blur on the layer so `blurKeyPath` can be animated. Call `endBlur()` afterwards:
    /// a layer without filters is composited without an offscreen pass.
    func beginBlur() {
        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.name = "blur"
        blur?.setValue(0, forKey: kCIInputRadiusKey)
        filters = blur.map { [$0] }
    }

    func endBlur() {
        filters = nil
    }

    override func draw(in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}
