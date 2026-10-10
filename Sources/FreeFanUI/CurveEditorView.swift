import AppKit
import FreeFanCore

/// Core Graphics graph of one fan curve: X = temperature 0...110 C, Y = speed 0...100 percent.
/// The base graph redraws only when the points, the size or the hover/drag state change. The live marker is made of
/// layers, so its once-a-second updates never redraw the backing store.
final class CurveEditorView: NSView {
    /// Fires after every accepted edit (drag step, insert, remove) with the new points.
    var onEdit: (([CurvePoint]) -> Void)?

    /// Fires once an edit is finished: when a drag ends, and after an insert or a remove.
    var onCommit: (([CurvePoint]) -> Void)?

    /// Built-in presets are shown but cannot be dragged, extended or trimmed.
    var isEditable = true {
        didSet {
            guard isEditable != oldValue else { return }
            dragIndex = nil
            hoverIndex = nil
            needsDisplay = true
        }
    }

    private(set) var points: [CurvePoint] = [] {
        didSet { renderLive() }
    }

    private var dragIndex: Int?
    private var dragMoved = false
    private var dragOffset = NSSize.zero
    private var hoverIndex: Int?
    private var trackingArea: NSTrackingArea?
    private let live = CurveLiveMarker()
    private var speed = FanSpeedFormat(fan: nil, showsRPM: false)

    var plot: CurvePlot { CurvePlot(bounds: bounds) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Fan curve graph")
        wantsLayer = true
        live.attach(to: layer!, contentsScale: window?.backingScaleFactor ?? 2)
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

    /// Hands the live values to the marker; the graph itself redraws only when a displayed value changed.
    func setLive(temperature: Float?, speed: FanSpeedFormat) {
        self.speed = speed
        if live.set(temperature: temperature, speed: speed) {
            renderLive()
        }
    }

    override func layout() {
        super.layout()
        renderLive()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        live.setContentsScale(window?.backingScaleFactor ?? 2)
        applyLiveColors()
        renderLive()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyLiveColors()
    }

    override func draw(_ dirtyRect: NSRect) {
        CurveDrawing(
            points: points,
            mapping: plot,
            bounds: bounds,
            isEditable: isEditable,
            dragIndex: dragIndex,
            hoverIndex: hoverIndex,
            speed: speed
        ).draw()
    }

    private func applyLiveColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { live.applyColors() }
    }

    private func renderLive() {
        live.render(points: points, plot: plot, suppressed: dragIndex != nil)
    }

    private func hitIndex(at location: NSPoint) -> Int? {
        let mapping = plot
        var best: Int?
        var bestDistance = CurveStyle.hitRadius
        for (index, point) in points.enumerated() {
            let center = mapping.point(t: point.t, p: point.p)
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
        guard isEditable else { return }
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
        guard isEditable else { return }
        let location = convert(event.locationInWindow, from: nil)
        let hit = hitIndex(at: location)

        // Control-click acts as a right click.
        if event.modifierFlags.contains(.control) {
            if let hit { removePoint(at: hit) }
            return
        }

        if let hit {
            let center = plot.point(t: points[hit].t, p: points[hit].p)
            dragIndex = hit
            dragMoved = false
            dragOffset = NSSize(width: center.x - location.x, height: center.y - location.y)
            needsDisplay = true
            renderLive()
            return
        }

        if event.clickCount == 2, plot.rect.contains(location) {
            insertPoint(at: location)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = dragIndex, points.indices.contains(index) else { return }
        let location = convert(event.locationInWindow, from: nil)
        let target = plot.data(at: NSPoint(x: location.x + dragOffset.width, y: location.y + dragOffset.height))
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
        renderLive()
    }

    override func rightMouseDown(with event: NSEvent) {
        // No super call: the default implementation would look for a context menu.
        guard isEditable else { return }
        if let hit = hitIndex(at: convert(event.locationInWindow, from: nil)) {
            removePoint(at: hit)
        }
    }

    private func insertPoint(at location: NSPoint) {
        let target = plot.data(at: location)
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
}
