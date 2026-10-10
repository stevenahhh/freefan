import AppKit

/// A large number whose changed characters slide in vertically, like the system's numeric text transition. It is
/// built from layers so an update redraws nothing, and stays in AppKit so the app links no UI framework for it.
final class RollingNumberView: NSView {
    private static let duration: CFTimeInterval = 0.22

    private let font: NSFont
    private var text = ""
    private var cells: [CATextLayer] = []
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
        cells.forEach { $0.foregroundColor = color }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        cells.forEach { $0.contentsScale = scale }
        layoutCells()
    }

    override func layout() {
        super.layout()
        layoutCells()
    }

    func setText(_ newText: String, animated: Bool) {
        guard newText != text else { return }
        let old = Array(text)
        let new = Array(newText)
        let rising = Self.number(in: newText) >= Self.number(in: text)
        text = newText
        setAccessibilityLabel(newText)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        resize(count: new.count)
        for (index, character) in new.enumerated() {
            let cell = cells[index]
            cell.string = String(character)
            widths[index] = Self.width(of: String(character), font: font)
            let changed = index >= old.count || old[index] != character
            if animated, changed, !old.isEmpty {
                cell.add(Self.slide(rising: rising, height: bounds.height), forKey: "roll")
            }
        }
        layoutCells()
        CATransaction.commit()
        invalidateIntrinsicContentSize()
    }

    private func layoutCells() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var x: CGFloat = 0
        for (cell, width) in zip(cells, widths) {
            cell.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            x += width
        }
        CATransaction.commit()
    }

    private func resize(count: Int) {
        while cells.count > count {
            cells.removeLast().removeFromSuperlayer()
            widths.removeLast()
        }
        while cells.count < count {
            let cell = CATextLayer()
            cell.font = font
            cell.fontSize = font.pointSize
            cell.alignmentMode = .center
            cell.foregroundColor = Self.labelColor(for: effectiveAppearance)
            cell.contentsScale = window?.backingScaleFactor ?? 2
            layer?.addSublayer(cell)
            cells.append(cell)
            widths.append(0)
        }
    }

    private static func slide(rising: Bool, height: CGFloat) -> CAAnimation {
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = (rising ? -1 : 1) * height * 0.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = Self.duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return group
    }

    private static func labelColor(for appearance: NSAppearance) -> CGColor {
        var color = NSColor.labelColor.cgColor
        appearance.performAsCurrentDrawingAppearance { color = NSColor.labelColor.cgColor }
        return color
    }

    private static func width(of string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func number(in text: String) -> Double {
        Double(text.filter { $0.isNumber || $0 == "." }) ?? 0
    }
}
