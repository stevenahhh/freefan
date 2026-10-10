import AppKit

/// Layout, size and opacity constants for the graph. Colors come from NSColor semantic system colors only, so the
/// graph follows light/dark appearance and the user's accent color.
enum CurveStyle {
    static let leftMargin: CGFloat = 26
    static let rightMargin: CGFloat = 4
    static let topMargin: CGFloat = 4
    static let bottomMargin: CGFloat = 26
    static let arrowGap: CGFloat = 8
    static let arrowHead: CGFloat = 5
    static let cornerRadius: CGFloat = 6
    static let curveWidth: CGFloat = 2.5
    static let liveLineWidth: CGFloat = 1.5
    static let dotRadius: CGFloat = 5.5
    static let dotRadiusActive: CGFloat = 7.5
    static let dotRingWidth: CGFloat = 2
    static let liveDotRadius: CGFloat = 5
    static let hitRadius: CGFloat = 11
    static let pillPaddingX: CGFloat = 7
    static let pillPaddingY: CGFloat = 3
    static let pillOffset: CGFloat = 10
    static let fillAlpha: CGFloat = 0.12
    static let extensionAlpha: CGFloat = 0.55
    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let pillFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
}

enum CurvePill {
    static var attributes: [NSAttributedString.Key: Any] {
        [.font: CurveStyle.pillFont, .foregroundColor: NSColor.labelColor]
    }

    static func size(for text: String) -> NSSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSSize(
            width: ceil(size.width) + CurveStyle.pillPaddingX * 2,
            height: ceil(size.height) + CurveStyle.pillPaddingY * 2
        )
    }

    static func draw(_ text: String, at origin: NSPoint, size: NSSize, tint: NSColor) {
        let rect = NSRect(origin: origin, size: size)
        let pill = NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2)
        NSColor.controlBackgroundColor.setFill()
        pill.fill()
        tint.setStroke()
        pill.lineWidth = 1
        pill.stroke()
        (text as NSString).draw(
            at: NSPoint(x: origin.x + CurveStyle.pillPaddingX, y: origin.y + CurveStyle.pillPaddingY),
            withAttributes: attributes
        )
    }
}
