import AppKit

/// A large number whose changed characters roll the way the system's numeric text transition does: the glyph that is
/// replaced slides out while the new one slides in, both clipped to the row and blurred as they travel, so nothing
/// overlaps. Columns are laid out from the right of a monospaced font, so a changing digit count never shifts the
/// digits that stayed.
final class RollingNumberView: NSView {
    private static let duration: CFTimeInterval = 0.3
    private static let blurRadius: CGFloat = 5

    private final class Column {
        let incoming = GlyphLayer()
        let outgoing = GlyphLayer()
    }

    private let font: NSFont
    private var text = ""
    private var columns: [Column] = []
    private var widths: [CGFloat] = []

    init(font: NSFont) {
        self.font = font
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(widths.reduce(0, +), 1), height: ceil(font.ascender - font.descender))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let color = Self.labelColor(for: effectiveAppearance)
        columns.forEach { column in
            column.incoming.textColor = color
            column.outgoing.textColor = color
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        columns.forEach { column in
            column.incoming.contentsScale = scale
            column.outgoing.contentsScale = scale
        }
        layoutColumns()
    }

    override func layout() {
        super.layout()
        layoutColumns()
    }

    func setText(_ newText: String, animated: Bool) {
        guard newText != text else { return }
        let old = Array(text)
        let new = Array(newText)
        let rising = Self.number(in: newText) > Self.number(in: text)
        text = newText
        setAccessibilityLabel(newText)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.finishRoll() }
        resize(count: new.count)
        // Both strings share their right edge, so the digits that did not change stay in place.
        for index in 0..<new.count {
            let column = columns[index]
            let oldCharacter = index >= new.count - old.count ? String(old[index - (new.count - old.count)]) : nil
            let newCharacter = String(new[index])
            widths[index] = Self.width(of: newCharacter, font: font)
            column.incoming.text = newCharacter
            guard animated, let oldCharacter, oldCharacter != newCharacter else {
                column.outgoing.isHidden = true
                continue
            }
            roll(column, from: oldCharacter, rising: rising)
        }
        layoutColumns()
        CATransaction.commit()
        invalidateIntrinsicContentSize()
    }

    private func roll(_ column: Column, from oldCharacter: String, rising: Bool) {
        let height = max(bounds.height, 1)
        column.outgoing.text = oldCharacter
        column.outgoing.isHidden = false
        let travel = rising ? height : -height
        column.incoming.add(Self.roll(from: -travel, blurFrom: Self.blurRadius, blurTo: 0), forKey: "roll")
        column.outgoing.add(Self.roll(from: 0, to: travel, blurFrom: 0, blurTo: Self.blurRadius), forKey: "roll")
    }

    private func finishRoll() {
        columns.forEach { $0.outgoing.isHidden = true }
    }

    private func layoutColumns() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var x = bounds.width
        for (column, width) in zip(columns, widths).reversed() {
            x -= width
            let frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            column.incoming.frame = frame
            column.outgoing.frame = frame
        }
        CATransaction.commit()
    }

    private func resize(count: Int) {
        while columns.count > count {
            let column = columns.removeLast()
            column.incoming.removeFromSuperlayer()
            column.outgoing.removeFromSuperlayer()
            widths.removeLast()
        }
        while columns.count < count {
            let column = Column()
            for layer in [column.incoming, column.outgoing] {
                layer.font = font
                layer.contentsScale = window?.backingScaleFactor ?? 2
                layer.isHidden = layer === column.outgoing
                layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
            }
            layer?.addSublayer(column.incoming)
            layer?.addSublayer(column.outgoing)
            columns.append(column)
            widths.append(0)
        }
    }

    private static func roll(from: CGFloat, to: CGFloat = 0, blurFrom: CGFloat, blurTo: CGFloat) -> CAAnimationGroup {
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = from
        move.toValue = to
        let blur = CABasicAnimation(keyPath: "blurRadius")
        blur.fromValue = blurFrom
        blur.toValue = blurTo
        let group = CAAnimationGroup()
        group.animations = [move, blur]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0, 0.25, 1)
        return group
    }

    private static func labelColor(for appearance: NSAppearance) -> NSColor {
        var color = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance { color = NSColor.labelColor }
        return color
    }

    private static func width(of string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func number(in text: String) -> Double {
        Double(text.filter { $0.isNumber || $0 == "." }) ?? 0
    }
}
