import CoreGraphics

/// Where the menu bar panel goes: centered under its status item, a little below the menu bar, and inside the visible
/// area of its screen. Rectangles are in screen coordinates (origin at the bottom left).
public enum PanelPlacement {
    public static let gap: CGFloat = 6
    public static let margin: CGFloat = 8

    /// `anchor` is the status item's frame (its bottom edge is the menu bar's); `visible` is the screen's visible
    /// frame, which excludes the menu bar and the Dock.
    public static func frame(size: CGSize, anchor: CGRect, visible: CGRect) -> CGRect {
        let leftmost = visible.minX + margin
        let rightmost = max(leftmost, visible.maxX - margin - size.width)
        let x = min(max(anchor.midX - size.width / 2, leftmost), rightmost)
        let top = min(anchor.minY, visible.maxY) - gap
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}
