import AppKit
import QuartzCore

/// One glyph, drawn with an animatable Gaussian blur so a rolling digit can blur exactly while it moves.
final class GlyphLayer: CALayer {
    @NSManaged var blurRadius: CGFloat

    var text = "" {
        didSet { if text != oldValue { invalidate() } }
    }

    var font = NSFont.systemFont(ofSize: 26, weight: .semibold) {
        didSet { invalidate() }
    }

    var textColor = NSColor.labelColor {
        didSet { invalidate() }
    }

    private static let ciContext = CIContext()
    private var glyph: CGImage?
    private var glyphKey = ""
    private var blurred: [Int: CGImage] = [:]

    override class func needsDisplay(forKey key: String) -> Bool {
        key == "blurRadius" ? true : super.needsDisplay(forKey: key)
    }

    override func draw(in context: CGContext) {
        guard let glyph = glyphImage() else { return }
        let radius = presentation()?.blurRadius ?? blurRadius
        context.draw(radius > 0.05 ? (blurredGlyph(glyph, radius: radius) ?? glyph) : glyph, in: bounds)
    }

    private func invalidate() {
        glyph = nil
        glyphKey = ""
        blurred.removeAll()
        setNeedsDisplay()
    }

    private func glyphImage() -> CGImage? {
        let key = "\(text)|\(font.fontName)|\(font.pointSize)|\(Int(bounds.width))x\(Int(bounds.height))|\(contentsScale)|\(textColor.description)"
        if key == glyphKey, let glyph { return glyph }
        let scale = max(contentsScale, 1)
        let width = max(Int((bounds.width * scale).rounded()), 1)
        let height = max(Int((bounds.height * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()

        glyph = context.makeImage()
        glyphKey = key
        blurred.removeAll()
        return glyph
    }

    private func blurredGlyph(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let bucket = Int((radius * 4).rounded())
        if let cached = blurred[bucket] { return cached }
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let output = CIImage(cgImage: image)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * max(contentsScale, 1)])
            .cropped(to: extent)
        guard let result = Self.ciContext.createCGImage(output, from: extent) else { return nil }
        blurred[bucket] = result
        return result
    }
}
