import AppKit

/// A large number whose changed characters roll, like the system's numeric text transition: the old glyph slides out
/// while the new one slides in, both fully opaque and clipped to the row. It is built from layers so an update
/// redraws nothing, and stays in AppKit so the app links no UI framework for it.
final class RollingNumberView: NSView {
    private static let duration: CFTimeInterval = 0.32

    private final class DigitCell {
        let current = CATextLayer()
        let outgoing = CATextLayer()
    }

    private let font: NSFont
    private var text = ""
    private var cells: [DigitCell] = []
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
        cells.forEach { cell in
            cell.current.foregroundColor = color
            cell.outgoing.foregroundColor = color
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cells.forEach { cell in
            cell.current.contentsScale = window?.backingScaleFactor ?? 2
            cell.outgoing.contentsScale = window?.backingScaleFactor ?? 2
        }
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
        let rising = Self.number(in: newText) > Self.number(in: text)
        text = newText
        setAccessibilityLabel(newText)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.finishRoll() }
        resize(count: new.count)
        for (index, character) in new.enumerated() {
            let cell = cells[index]
            let string = String(character)
            widths[index] = Self.width(of: string, font: font)
            cell.current.string = string
            guard animated, index < old.count, old[index] != character, !old.isEmpty else {
                cell.outgoing.isHidden = true
                continue
            }
            roll(cell, from: String(old[index]), rising: rising)
        }
        layoutCells()
        CATransaction.commit()
        invalidateIntrinsicContentSize()
    }

    private func roll(_ cell: DigitCell, from oldCharacter: String, rising: Bool) {
        let height = max(bounds.height, 1)
        cell.outgoing.string = oldCharacter
        cell.outgoing.isHidden = false
        cell.current.add(Self.slide(from: rising ? -height : height), forKey: "roll")
        cell.outgoing.add(Self.slide(from: 0, to: rising ? height : -height), forKey: "roll")
    }

    private func finishRoll() {
        cells.forEach { $0.outgoing.isHidden = true }
    }

    private func layoutCells() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var x: CGFloat = 0
        for (cell, width) in zip(cells, widths) {
            let frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            cell.current.frame = frame
            cell.outgoing.frame = frame
            x += width
        }
        CATransaction.commit()
    }

    private func resize(count: Int) {
        while cells.count > count {
            let cell = cells.removeLast()
            cell.current.removeFromSuperlayer()
            cell.outgoing.removeFromSuperlayer()
            widths.removeLast()
        }
        while cells.count < count {
            let cell = DigitCell()
            for layer in [cell.current, cell.outgoing] {
                layer.font = font
                layer.fontSize = font.pointSize
                layer.alignmentMode = .center
                layer.foregroundColor = Self.labelColor(for: effectiveAppearance)
                layer.contentsScale = window?.backingScaleFactor ?? 2
                layer.isHidden = layer === cell.outgoing
                layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
            }
            layer?.addSublayer(cell.current)
            layer?.addSublayer(cell.outgoing)
            cells.append(cell)
            widths.append(0)
        }
    }

    private static func slide(from: CGFloat, to: CGFloat = 0) -> CAAnimation {
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = from
        move.toValue = to
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        return move
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
