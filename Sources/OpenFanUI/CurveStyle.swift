import AppKit

/// Layout, size and opacity constants for the graph. Colors are system colors plus the plot's own dynamic fill, so the
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
    /// The plot's own fill: a translucent black, so it reads as a darker well in the glass in both appearances. A fill
    /// as light as the glass, such as the system fills (about 12 % gray), is indistinguishable from it in light mode.
    static let plotBackground = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.black.withAlphaComponent(dark ? 0.28 : 0.18)
    }
    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let pillFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
}

enum CurvePill {
    private static let lineSpacing: CGFloat = 1

    static var attributes: [NSAttributedString.Key: Any] {
        [.font: CurveStyle.pillFont, .foregroundColor: NSColor.labelColor]
    }

    static func size(for lines: [String]) -> NSSize {
        let sizes = lines.map { ($0 as NSString).size(withAttributes: attributes) }
        let textWidth = sizes.map(\.width).max() ?? 0
        let textHeight = sizes.map(\.height).reduce(0, +) + CGFloat(max(lines.count - 1, 0)) * lineSpacing
        return NSSize(
            width: ceil(textWidth) + CurveStyle.pillPaddingX * 2,
            height: ceil(textHeight) + CurveStyle.pillPaddingY * 2
        )
    }

    static func draw(_ lines: [String], at origin: NSPoint, size: NSSize, tint: NSColor) {
        let rect = NSRect(origin: origin, size: size)
        let pill = NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2)
        NSColor.controlBackgroundColor.setFill()
        pill.fill()
        tint.setStroke()
        pill.lineWidth = 1
        pill.stroke()

        var y = origin.y + size.height - CurveStyle.pillPaddingY
        for line in lines {
            let lineHeight = (line as NSString).size(withAttributes: attributes).height
            y -= lineHeight
            (line as NSString).draw(
                at: NSPoint(x: origin.x + CurveStyle.pillPaddingX, y: y),
                withAttributes: attributes
            )
            y -= lineSpacing
        }
    }
}
