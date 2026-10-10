import AppKit

/// A large number whose changed characters roll the way the system's numeric text transition does: the replaced
/// glyph slides away while the new one slides in from the other side, each blurring and fading as it travels. Columns
/// are laid out from the right of a monospaced font, so a changing digit count never shifts the digits that stayed.
final class RollingNumberView: NSView {
    private static let travel: CGFloat = 0.35
    private static let blurRadius: CGFloat = 2
    private static let blurMargin: CGFloat = 6
    private static let stagger: CFTimeInterval = 0.11

    private final class Column {
        let incoming = GlyphLayer()
        let outgoing = GlyphLayer()
    }

    private let font: NSFont
    private var text = ""
    private var columns: [Column] = []
    private var widths: [CGFloat] = []
    private var generation = 0

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
        let animates = animated && !old.isEmpty
        let rising = Self.number(in: newText) > Self.number(in: text)
        text = newText
        generation += 1
        let current = generation
        setAccessibilityLabel(newText)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.finishRoll(generation: current) }
        resize(count: new.count)
        // Both strings share their right edge, so the digits that did not change stay in place.
        var rolled = 0
        for index in 0..<new.count {
            let column = columns[index]
            let oldCharacter = index >= new.count - old.count ? String(old[index - (new.count - old.count)]) : nil
            let newCharacter = String(new[index])
            widths[index] = Self.width(of: newCharacter, font: font)
            column.incoming.text = newCharacter
            guard animates, oldCharacter != newCharacter else { continue }
            roll(column, from: oldCharacter, rising: rising, delay: Double(rolled) * Self.stagger)
            rolled += 1
        }
        layoutColumns()
        CATransaction.commit()
        invalidateIntrinsicContentSize()
    }

    private func roll(_ column: Column, from oldCharacter: String?, rising: Bool, delay: CFTimeInterval) {
        let travel = (rising ? 1 : -1) * max(bounds.height, 1) * Self.travel
        let begin = column.incoming.convertTime(CACurrentMediaTime(), from: nil) + delay
        column.incoming.beginBlur()
        column.incoming.add(Self.transition(from: -travel, to: 0, opacity: (0, 1), blur: (Self.blurRadius, 0), begin: begin), forKey: "roll")
        guard let oldCharacter else { return }
        column.outgoing.text = oldCharacter
        column.outgoing.beginBlur()
        column.outgoing.add(Self.transition(from: 0, to: travel, opacity: (1, 0), blur: (0, Self.blurRadius), begin: begin), forKey: "roll")
    }

    private func finishRoll(generation: Int) {
        guard generation == self.generation else { return }
        columns.forEach { column in
            column.incoming.endBlur()
            column.outgoing.endBlur()
        }
    }

    private func layoutColumns() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var x = bounds.width
        for (column, width) in zip(columns, widths).reversed() {
            x -= width
            let frame = CGRect(x: x - Self.blurMargin, y: 0, width: width + 2 * Self.blurMargin, height: bounds.height)
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
                layer.needsDisplayOnBoundsChange = true
                layer.opacity = layer === column.outgoing ? 0 : 1
                layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "opacity": NSNull()]
            }
            layer?.addSublayer(column.incoming)
            layer?.addSublayer(column.outgoing)
            columns.append(column)
            widths.append(0)
        }
    }

    /// A critically damped spring that settles in about half a second, which is SwiftUI's default animation, driving the
    /// slide, the fade and the blur together.
    private static func transition(from: CGFloat, to: CGFloat, opacity: (CGFloat, CGFloat), blur: (CGFloat, CGFloat), begin: CFTimeInterval) -> CAAnimationGroup {
        let animations = [
            ("transform.translation.y", from, to),
            ("opacity", opacity.0, opacity.1),
            (GlyphLayer.blurKeyPath, blur.0, blur.1),
        ].map { keyPath, start, end -> CASpringAnimation in
            let spring = CASpringAnimation(keyPath: keyPath)
            spring.fromValue = start
            spring.toValue = end
            spring.mass = 1
            spring.stiffness = 158
            spring.damping = 25
            spring.duration = spring.settlingDuration
            return spring
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = animations.map(\.duration).max() ?? 0
        group.beginTime = begin
        group.fillMode = .backwards
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
