import AppKit
import FreeFanCore

/// Pure rules for editing a curve in data space (degrees C, percent of the fan's [Mn, Mx] range).
/// Every function returns a result that still satisfies FanCurve.validate() when its input does.
enum CurveGeometry {
    /// The graph shows 0...110 C; Core allows up to 130 C but the editor keeps points on the visible axis.
    static let maxTemperature: Double = 110
    static let maxPercent: Double = 100
    /// Neighbouring points must be at least this many degrees apart.
    static let minTemperatureGap: Double = 1

    static func snap(_ value: Double) -> Double {
        value.rounded()
    }

    /// New position for point `index` when the pointer asks for (temperature, percent).
    /// - temperature: snapped to 1 degree, kept inside 0...110 and at least 1 degree away from both neighbours
    /// - percent: snapped to 1 percent, kept inside 0...100, never below the previous point and never above the
    ///   next point (so a hotter point is never slower and the curve stays valid)
    /// When the neighbours leave no room on an axis the point keeps its current value on that axis.
    /// `index` must be a valid index of `points`.
    static func moved(_ points: [CurvePoint], index: Int, toTemperature temperature: Double, percent: Double) -> CurvePoint {
        let current = points[index]
        guard temperature.isFinite, percent.isFinite else { return current }

        var lowTemperature: Double = 0
        var highTemperature: Double = maxTemperature
        var lowPercent: Double = 0
        var highPercent: Double = maxPercent
        if index > 0 {
            lowTemperature = max(lowTemperature, points[index - 1].t + minTemperatureGap)
            lowPercent = max(lowPercent, points[index - 1].p)
        }
        if index < points.count - 1 {
            highTemperature = min(highTemperature, points[index + 1].t - minTemperatureGap)
            highPercent = min(highPercent, points[index + 1].p)
        }

        var result = current
        if lowTemperature <= highTemperature {
            result.t = min(max(snap(temperature), lowTemperature), highTemperature)
        }
        if lowPercent <= highPercent {
            result.p = min(max(snap(percent), lowPercent), highPercent)
        }
        return result
    }

    /// Inserts a point at (temperature, percent), snapped and clamped like a drag. Returns nil when the curve
    /// already has FanCurve.maxPoints points or the spot is closer than 1 degree to an existing point.
    static func inserting(into points: [CurvePoint], temperature: Double, percent: Double) -> [CurvePoint]? {
        guard points.count < FanCurve.maxPoints, temperature.isFinite, percent.isFinite else { return nil }
        let newTemperature = min(max(snap(temperature), 0), maxTemperature)
        let index = points.firstIndex { $0.t >= newTemperature } ?? points.count
        if index > 0, points[index - 1].t > newTemperature - minTemperatureGap { return nil }
        if index < points.count, points[index].t < newTemperature + minTemperatureGap { return nil }

        let lowPercent = index > 0 ? points[index - 1].p : 0
        let highPercent = index < points.count ? points[index].p : maxPercent
        let newPercent = min(max(snap(percent), lowPercent), highPercent)

        var result = points
        result.insert(CurvePoint(t: newTemperature, p: newPercent), at: index)
        return result
    }

    /// Removes point `index`. Returns nil when only FanCurve.minPoints points remain or the index is invalid.
    static func removing(from points: [CurvePoint], index: Int) -> [CurvePoint]? {
        guard points.count > FanCurve.minPoints, points.indices.contains(index) else { return nil }
        var result = points
        result.remove(at: index)
        return result
    }
}

/// Core Graphics graph of one fan curve: X = temperature 0...110 C, Y = speed 0...100 percent.
/// The base graph redraws only when the points, the size or the hover/drag state change. The live marker is made of
/// layers, so its once-a-second updates never redraw the backing store.
final class CurveEditorView: NSView {
    /// Fires after every accepted edit (drag step, insert, remove) with the new points.
    var onEdit: (([CurvePoint]) -> Void)?

    /// Fires once an edit is finished: when a drag ends, and after an insert or a remove.
    var onCommit: (([CurvePoint]) -> Void)?

    private(set) var points: [CurvePoint] = [] {
        didSet { updateLiveLayers() }
    }

    private var liveTemperature: Float?
    private var liveRPM: Float?
    private var liveFanMaxRPM: Float?

    private var dragIndex: Int?
    private var dragMoved = false
    private var dragOffset = NSSize.zero
    private var hoverIndex: Int?
    private var trackingArea: NSTrackingArea?

    private let liveLine = CAShapeLayer()
    private let liveDot = CAShapeLayer()
    private let livePill = CALayer()
    private let liveText = CATextLayer()

    // Layout, size and opacity constants. Colors come from NSColor semantic system colors only, so the
    // graph follows light/dark appearance and the user's accent color.
    private enum Style {
        static let leftMargin: CGFloat = 46
        static let rightMargin: CGFloat = 14
        static let topMargin: CGFloat = 12
        static let bottomMargin: CGFloat = 38
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
        static let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        static let titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        static let pillFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Fan curve graph")

        wantsLayer = true
        liveLine.fillColor = nil
        liveLine.lineWidth = Style.liveLineWidth
        liveLine.lineDashPattern = [5, 3]
        liveDot.lineWidth = Style.dotRingWidth
        livePill.borderWidth = 1
        liveText.font = Style.pillFont
        liveText.fontSize = Style.pillFont.pointSize
        liveText.alignmentMode = .left
        liveText.truncationMode = .none
        livePill.addSublayer(liveText)
        for layer in [liveLine, liveDot, livePill] {
            layer.isHidden = true
            self.layer?.addSublayer(layer)
        }
        applyLiveColors()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setPoints(_ newPoints: [CurvePoint]) {
        guard newPoints != points else { return }
        points = newPoints
        dragIndex = nil
        hoverIndex = nil
        needsDisplay = true
    }

    /// Updates the live marker. Values are rounded to what is displayed (0.1 C, whole rpm) and the view only
    /// redraws when a displayed value changed.
    func setLive(temperature: Float?, actualRPM: Float?, fanMaxRPM: Float?) {
        let newTemperature = temperature.flatMap { $0.isFinite ? ($0 * 10).rounded() / 10 : nil }
        let newRPM = actualRPM.flatMap { $0.isFinite && $0 >= 0 && $0 <= 1_000_000 ? $0.rounded() : nil }
        let newMax = fanMaxRPM.flatMap { $0.isFinite && $0 > 0 && $0 <= 1_000_000 ? $0.rounded() : nil }
        guard newTemperature != liveTemperature || newRPM != liveRPM || newMax != liveFanMaxRPM else { return }
        liveTemperature = newTemperature
        liveRPM = newRPM
        liveFanMaxRPM = newMax
        updateLiveLayers()
    }

    private var plotRect: NSRect {
        NSRect(
            x: bounds.minX + Style.leftMargin,
            y: bounds.minY + Style.bottomMargin,
            width: max(bounds.width - Style.leftMargin - Style.rightMargin, 1),
            height: max(bounds.height - Style.bottomMargin - Style.topMargin, 1)
        )
    }

    private func viewPoint(t: Double, p: Double, in plot: NSRect) -> NSPoint {
        NSPoint(
            x: plot.minX + CGFloat(t / CurveGeometry.maxTemperature) * plot.width,
            y: plot.minY + CGFloat(p / CurveGeometry.maxPercent) * plot.height
        )
    }

    private func dataPoint(at location: NSPoint, in plot: NSRect) -> (t: Double, p: Double) {
        (
            t: Double((location.x - plot.minX) / plot.width) * CurveGeometry.maxTemperature,
            p: Double((location.y - plot.minY) / plot.height) * CurveGeometry.maxPercent
        )
    }

    private func hitIndex(at location: NSPoint) -> Int? {
        let plot = plotRect
        var best: Int?
        var bestDistance = Style.hitRadius
        for (index, point) in points.enumerated() {
            let center = viewPoint(t: point.t, p: point.p, in: plot)
            let distance = hypot(center.x - location.x, center.y - location.y)
            if distance <= bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(to: hitIndex(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(to: nil)
    }

    private func updateHover(to index: Int?) {
        guard index != hoverIndex else { return }
        hoverIndex = index
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hit = hitIndex(at: location)

        // Control-click acts as a right click.
        if event.modifierFlags.contains(.control) {
            if let hit { removePoint(at: hit) }
            return
        }

        if let hit {
            let center = viewPoint(t: points[hit].t, p: points[hit].p, in: plotRect)
            dragIndex = hit
            dragMoved = false
            dragOffset = NSSize(width: center.x - location.x, height: center.y - location.y)
            needsDisplay = true
            return
        }

        if event.clickCount == 2, plotRect.contains(location) {
            insertPoint(at: location)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = dragIndex, points.indices.contains(index) else { return }
        let location = convert(event.locationInWindow, from: nil)
        let target = dataPoint(
            at: NSPoint(x: location.x + dragOffset.width, y: location.y + dragOffset.height),
            in: plotRect
        )
        let moved = CurveGeometry.moved(points, index: index, toTemperature: target.t, percent: target.p)
        if moved != points[index] {
            points[index] = moved
            dragMoved = true
            onEdit?(points)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragIndex != nil else { return }
        dragIndex = nil
        if dragMoved {
            dragMoved = false
            onCommit?(points)
        }
        hoverIndex = hitIndex(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        // No super call: the default implementation would look for a context menu.
        if let hit = hitIndex(at: convert(event.locationInWindow, from: nil)) {
            removePoint(at: hit)
        }
    }

    private func insertPoint(at location: NSPoint) {
        let target = dataPoint(at: location, in: plotRect)
        guard let updated = CurveGeometry.inserting(into: points, temperature: target.t, percent: target.p) else {
            NSSound.beep()
            return
        }
        points = updated
        hoverIndex = nil
        onEdit?(points)
        onCommit?(points)
        needsDisplay = true
    }

    private func removePoint(at index: Int) {
        guard let updated = CurveGeometry.removing(from: points, index: index) else {
            NSSound.beep()
            return
        }
        points = updated
        dragIndex = nil
        hoverIndex = nil
        onEdit?(points)
        onCommit?(points)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let plot = plotRect
        guard plot.width > 8, plot.height > 8 else { return }

        let frame = NSBezierPath(roundedRect: plot, xRadius: Style.cornerRadius, yRadius: Style.cornerRadius)
        NSColor.textBackgroundColor.setFill()
        frame.fill()

        NSGraphicsContext.saveGraphicsState()
        frame.addClip()
        drawGrid(in: plot)
        drawCurve(in: plot)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.setStroke()
        frame.lineWidth = 1
        frame.stroke()

        drawDots(in: plot)
        drawAxes(in: plot)
        drawDragReadout(in: plot)
    }

    private func drawGrid(in plot: NSRect) {
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for temperature in stride(from: 0.0, through: CurveGeometry.maxTemperature, by: 10) {
            let x = viewPoint(t: temperature, p: 0, in: plot).x
            grid.move(to: NSPoint(x: x, y: plot.minY))
            grid.line(to: NSPoint(x: x, y: plot.maxY))
        }
        for percent in stride(from: 0.0, through: CurveGeometry.maxPercent, by: 10) {
            let y = viewPoint(t: 0, p: percent, in: plot).y
            grid.move(to: NSPoint(x: plot.minX, y: y))
            grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        NSColor.gridColor.setStroke()
        grid.stroke()
    }

    private func drawCurve(in plot: NSRect) {
        guard let first = points.first, let last = points.last else { return }
        let start = viewPoint(t: 0, p: first.p, in: plot)
        let end = viewPoint(t: CurveGeometry.maxTemperature, p: last.p, in: plot)
        let firstPoint = viewPoint(t: first.t, p: first.p, in: plot)
        let lastPoint = viewPoint(t: last.t, p: last.p, in: plot)

        // Area under the curve, including the flat extensions the controller applies outside the points.
        let area = NSBezierPath()
        area.move(to: NSPoint(x: start.x, y: plot.minY))
        area.line(to: start)
        for point in points {
            area.line(to: viewPoint(t: point.t, p: point.p, in: plot))
        }
        area.line(to: end)
        area.line(to: NSPoint(x: end.x, y: plot.minY))
        area.close()
        NSColor.controlAccentColor.withAlphaComponent(Style.fillAlpha).setFill()
        area.fill()

        // Flat extensions: below the first point and above the last point the curve holds its end value.
        let extensions = NSBezierPath()
        extensions.lineWidth = Style.curveWidth - 1
        extensions.setLineDash([4, 3], count: 2, phase: 0)
        extensions.move(to: start)
        extensions.line(to: firstPoint)
        extensions.move(to: lastPoint)
        extensions.line(to: end)
        NSColor.controlAccentColor.withAlphaComponent(Style.extensionAlpha).setStroke()
        extensions.stroke()

        let line = NSBezierPath()
        line.lineWidth = Style.curveWidth
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.move(to: firstPoint)
        for point in points.dropFirst() {
            line.line(to: viewPoint(t: point.t, p: point.p, in: plot))
        }
        NSColor.controlAccentColor.setStroke()
        line.stroke()
    }

    private func drawDots(in plot: NSRect) {
        for (index, point) in points.enumerated() where point.t >= 0 && point.t <= CurveGeometry.maxTemperature {
            let center = viewPoint(t: point.t, p: point.p, in: plot)
            let active = index == dragIndex || (dragIndex == nil && index == hoverIndex)
            let radius = active ? Style.dotRadiusActive : Style.dotRadius
            let dot = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            NSColor.controlAccentColor.setFill()
            dot.fill()
            NSColor.textBackgroundColor.setStroke()
            dot.lineWidth = Style.dotRingWidth
            dot.stroke()
        }
    }

    private func drawAxes(in plot: NSRect) {
        let axisAttributes: [NSAttributedString.Key: Any] = [
            .font: Style.axisFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: Style.titleFont,
            .foregroundColor: NSColor.labelColor,
        ]

        for temperature in stride(from: 0, through: Int(CurveGeometry.maxTemperature), by: 10) {
            let text = String(temperature) as NSString
            let size = text.size(withAttributes: axisAttributes)
            let x = viewPoint(t: Double(temperature), p: 0, in: plot).x
            text.draw(at: NSPoint(x: x - size.width / 2, y: plot.minY - 6 - size.height), withAttributes: axisAttributes)
        }
        for percent in stride(from: 0, through: Int(CurveGeometry.maxPercent), by: 10) {
            let text = String(percent) as NSString
            let size = text.size(withAttributes: axisAttributes)
            let y = viewPoint(t: 0, p: Double(percent), in: plot).y
            text.draw(at: NSPoint(x: plot.minX - 6 - size.width, y: y - size.height / 2), withAttributes: axisAttributes)
        }

        let xTitle = "Temperature (\u{00B0}C)" as NSString
        let xSize = xTitle.size(withAttributes: titleAttributes)
        xTitle.draw(at: NSPoint(x: plot.midX - xSize.width / 2, y: bounds.minY + 4), withAttributes: titleAttributes)

        // The Y title is rotated 90 degrees counter-clockwise so it reads bottom to top.
        let yTitle = "Fan speed (% of range)" as NSString
        let ySize = yTitle.size(withAttributes: titleAttributes)
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.translateBy(x: bounds.minX + 4 + ySize.height, y: plot.midY - ySize.width / 2)
            context.rotate(by: .pi / 2)
            yTitle.draw(at: .zero, withAttributes: titleAttributes)
            context.restoreGState()
        }
    }

    override func layout() {
        super.layout()
        updateLiveLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        liveText.contentsScale = window?.backingScaleFactor ?? 2
        applyLiveColors()
        updateLiveLayers()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyLiveColors()
    }

    private func applyLiveColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let orange = NSColor.systemOrange.cgColor
            liveLine.strokeColor = orange
            liveDot.fillColor = orange
            liveDot.strokeColor = NSColor.textBackgroundColor.cgColor
            livePill.borderColor = orange
            livePill.backgroundColor = NSColor.controlBackgroundColor.cgColor
            liveText.foregroundColor = NSColor.labelColor.cgColor
        }
    }

    private func updateLiveLayers() {
        let plot = plotRect
        let visible = liveTemperature != nil && !points.isEmpty && plot.width > 8 && plot.height > 8
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for layer in [liveLine, liveDot, livePill] where layer.isHidden == visible {
            layer.isHidden = !visible
        }
        guard visible, let temperature = liveTemperature else { return }

        let clamped = min(max(Double(temperature), 0), CurveGeometry.maxTemperature)
        let percent = FanCurve(points: points).percent(at: Double(temperature))
        let center = viewPoint(t: clamped, p: percent, in: plot)

        let line = CGMutablePath()
        line.move(to: CGPoint(x: center.x, y: plot.minY))
        line.addLine(to: CGPoint(x: center.x, y: plot.maxY))
        liveLine.path = line
        liveDot.path = CGPath(
            ellipseIn: CGRect(
                x: center.x - Style.liveDotRadius,
                y: center.y - Style.liveDotRadius,
                width: Style.liveDotRadius * 2,
                height: Style.liveDotRadius * 2
            ),
            transform: nil
        )

        var text = String(format: "%.1f\u{00B0}C", temperature)
        if let rpm = liveRPM {
            if let maximum = liveFanMaxRPM {
                text += String(format: "   %.0f / %.0f rpm", rpm, maximum)
            } else {
                text += String(format: "   %.0f rpm", rpm)
            }
        }
        let textSize = (text as NSString).size(withAttributes: pillAttributes)
        let size = pillSize(for: text)
        var x = center.x + Style.pillOffset
        if x + size.width > plot.maxX {
            x = center.x - Style.pillOffset - size.width
        }
        livePill.frame = CGRect(
            x: min(max(x, plot.minX), plot.maxX - size.width),
            y: plot.maxY - size.height - Style.pillOffset,
            width: size.width,
            height: size.height
        )
        livePill.cornerRadius = size.height / 2
        liveText.frame = CGRect(x: Style.pillPaddingX, y: Style.pillPaddingY, width: ceil(textSize.width) + 2, height: ceil(textSize.height))
        if liveText.string as? String != text {
            liveText.string = text
        }
    }

    private func drawDragReadout(in plot: NSRect) {
        guard let index = dragIndex, points.indices.contains(index) else { return }
        let point = points[index]
        let text = String(format: "%.0f\u{00B0}C   %.0f%%", point.t, point.p)
        let size = pillSize(for: text)
        let center = viewPoint(t: point.t, p: point.p, in: plot)
        // Prefer up and to the right of the dot; flip to the other side near the plot edges.
        var x = center.x + Style.pillOffset + Style.dotRadiusActive
        if x + size.width > plot.maxX {
            x = center.x - Style.pillOffset - Style.dotRadiusActive - size.width
        }
        var y = center.y + Style.pillOffset + Style.dotRadiusActive
        if y + size.height > plot.maxY {
            y = center.y - Style.pillOffset - Style.dotRadiusActive - size.height
        }
        let origin = NSPoint(
            x: min(max(x, plot.minX), plot.maxX - size.width),
            y: min(max(y, plot.minY), plot.maxY - size.height)
        )
        drawPill(text, at: origin, size: size, tint: .controlAccentColor)
    }

    private var pillAttributes: [NSAttributedString.Key: Any] {
        [.font: Style.pillFont, .foregroundColor: NSColor.labelColor]
    }

    private func pillSize(for text: String) -> NSSize {
        let textSize = (text as NSString).size(withAttributes: pillAttributes)
        return NSSize(
            width: ceil(textSize.width) + Style.pillPaddingX * 2,
            height: ceil(textSize.height) + Style.pillPaddingY * 2
        )
    }

    private func drawPill(_ text: String, at origin: NSPoint, size: NSSize, tint: NSColor) {
        let rect = NSRect(origin: origin, size: size)
        let pill = NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2)
        NSColor.controlBackgroundColor.setFill()
        pill.fill()
        tint.setStroke()
        pill.lineWidth = 1
        pill.stroke()
        (text as NSString).draw(
            at: NSPoint(x: origin.x + Style.pillPaddingX, y: origin.y + Style.pillPaddingY),
            withAttributes: pillAttributes
        )
    }
}
