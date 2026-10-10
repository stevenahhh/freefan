import AppKit
import FreeFanCore

/// The once-a-second overlay on the graph: a dashed line at the current temperature, a dot on the curve, and a pill
/// with the temperature and fan rpm. It is built from layers, so an update never redraws the graph's backing store.
final class CurveLiveMarker {
    private let line = CAShapeLayer()
    private let dot = CAShapeLayer()
    private let pill = CALayer()
    private let text = CATextLayer()

    private var temperature: Float?
    private var rpm: Float?
    private var maxRPM: Float?

    /// No layer property ever fades or slides: the live readout jumps to each new value.
    private static let noAnimations: [String: CAAction] = Dictionary(
        uniqueKeysWithValues: ["contents", "string", "bounds", "position", "frame", "path", "hidden", "opacity"]
            .map { ($0, NSNull()) }
    )

    init() {
        line.fillColor = nil
        line.lineWidth = CurveStyle.liveLineWidth
        line.lineDashPattern = [5, 3]
        dot.lineWidth = CurveStyle.dotRingWidth
        pill.borderWidth = 1
        text.font = CurveStyle.pillFont
        text.fontSize = CurveStyle.pillFont.pointSize
        text.alignmentMode = .left
        text.truncationMode = .none
        pill.addSublayer(text)
        text.actions = Self.noAnimations
        for layer in shapeLayers {
            layer.actions = Self.noAnimations
            layer.isHidden = true
        }
    }

    private var allLayers: [CALayer] {
        [line, dot, pill, text]
    }

    private var shapeLayers: [CALayer] {
        [line, dot, pill]
    }

    func attach(to host: CALayer, contentsScale: CGFloat) {
        for layer in shapeLayers { host.addSublayer(layer) }
        text.contentsScale = contentsScale
    }

    func setContentsScale(_ scale: CGFloat) {
        text.contentsScale = scale
    }

    /// Keeps the values as shown (0.1 C, whole rpm). Returns true when a displayed value changed.
    @discardableResult
    func set(temperature: Float?, rpm: Float?, maxRPM: Float?) -> Bool {
        let newTemperature = temperature.flatMap { $0.isFinite ? ($0 * 10).rounded() / 10 : nil }
        let newRPM = rpm.flatMap { $0.isFinite && $0 >= 0 && $0 <= 1_000_000 ? $0.rounded() : nil }
        let newMax = maxRPM.flatMap { $0.isFinite && $0 > 0 && $0 <= 1_000_000 ? $0.rounded() : nil }
        guard newTemperature != self.temperature || newRPM != self.rpm || newMax != self.maxRPM else { return false }
        self.temperature = newTemperature
        self.rpm = newRPM
        self.maxRPM = newMax
        return true
    }

    func applyColors() {
        let orange = NSColor.systemOrange.cgColor
        line.strokeColor = orange
        dot.fillColor = orange
        dot.strokeColor = NSColor.textBackgroundColor.cgColor
        pill.borderColor = orange
        pill.backgroundColor = NSColor.controlBackgroundColor.cgColor
        text.foregroundColor = NSColor.labelColor.cgColor
    }

    func render(points: [CurvePoint], plot: CurvePlot) {
        let bounds = plot.rect
        let visible = temperature != nil && !points.isEmpty && bounds.width > 8 && bounds.height > 8
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for layer in shapeLayers where layer.isHidden == visible {
            layer.isHidden = !visible
        }
        guard visible, let temperature else { return }

        let clamped = min(max(Double(temperature), 0), CurveGeometry.maxTemperature)
        let percent = FanCurve(points: points).percent(at: Double(temperature))
        let center = plot.point(t: clamped, p: percent)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x, y: bounds.minY))
        path.addLine(to: CGPoint(x: center.x, y: bounds.maxY))
        line.path = path
        dot.path = CGPath(
            ellipseIn: CGRect(
                x: center.x - CurveStyle.liveDotRadius,
                y: center.y - CurveStyle.liveDotRadius,
                width: CurveStyle.liveDotRadius * 2,
                height: CurveStyle.liveDotRadius * 2
            ),
            transform: nil
        )

        var label = String(format: "%.1f\u{00B0}C", temperature)
        if let rpm {
            label += maxRPM.map { String(format: "   %.0f / %.0f rpm", rpm, $0) } ?? String(format: "   %.0f rpm", rpm)
        }
        let size = CurvePill.size(for: label)
        var x = center.x + CurveStyle.pillOffset
        if x + size.width > bounds.maxX {
            x = center.x - CurveStyle.pillOffset - size.width
        }
        pill.frame = CGRect(
            x: min(max(x, bounds.minX), bounds.maxX - size.width),
            y: bounds.maxY - size.height - CurveStyle.pillOffset,
            width: size.width,
            height: size.height
        )
        pill.cornerRadius = size.height / 2
        let textSize = (label as NSString).size(withAttributes: CurvePill.attributes)
        text.frame = CGRect(
            x: CurveStyle.pillPaddingX,
            y: CurveStyle.pillPaddingY,
            width: ceil(textSize.width) + 2,
            height: ceil(textSize.height)
        )
        if text.string as? String != label {
            text.string = label
        }
    }
}
