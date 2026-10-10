import AppKit
import FreeFanCore

extension MemoryPressure {
    /// Fixed sRGB: dynamic system colors resolve to monochrome in the menu bar's vibrant appearance.
    public var dotColor: NSColor {
        switch self {
        case .normal: return NSColor(srgbRed: 0.204, green: 0.78, blue: 0.349, alpha: 1)
        case .warning: return NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        case .critical: return NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1)
        }
    }

    public func dotImage(size: CGFloat = 9) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            self.dotColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }
}
