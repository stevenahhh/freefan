import AppKit
import OpenFanCore

struct CurveDrawing {
    var points: [CurvePoint]
    var mapping: CurvePlot
    var bounds: NSRect
    var isEditable: Bool
    var dragIndex: Int?
    var hoverIndex: Int?
    var speed: FanSpeedFormat

    func draw() {
        let plot = mapping.rect
        guard plot.width > 8, plot.height > 8 else { return }

        let frame = NSBezierPath(roundedRect: plot, xRadius: CurveStyle.cornerRadius, yRadius: CurveStyle.cornerRadius)
        CurveStyle.plotBackground.setFill()
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
            let x = mapping.point(t: temperature, p: 0).x
            grid.move(to: NSPoint(x: x, y: plot.minY))
            grid.line(to: NSPoint(x: x, y: plot.maxY))
        }
        for percent in stride(from: 0.0, through: CurveGeometry.maxPercent, by: 10) {
            let y = mapping.point(t: 0, p: percent).y
            grid.move(to: NSPoint(x: plot.minX, y: y))
            grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        NSColor.gridColor.setStroke()
        grid.stroke()
    }

    private func drawCurve(in plot: NSRect) {
        guard let first = points.first, let last = points.last else { return }
        let start = mapping.point(t: 0, p: first.p)
        let end = mapping.point(t: CurveGeometry.maxTemperature, p: last.p)
        let firstPoint = mapping.point(t: first.t, p: first.p)
        let lastPoint = mapping.point(t: last.t, p: last.p)

        // Area under the curve, including the flat extensions the controller applies outside the points.
        let area = NSBezierPath()
        area.move(to: NSPoint(x: start.x, y: plot.minY))
        area.line(to: start)
        for point in points {
            area.line(to: mapping.point(t: point.t, p: point.p))
        }
        area.line(to: end)
        area.line(to: NSPoint(x: end.x, y: plot.minY))
        area.close()
        NSColor.controlAccentColor.withAlphaComponent(CurveStyle.fillAlpha).setFill()
        area.fill()

        // Flat extensions: below the first point and above the last point the curve holds its end value.
        let extensions = NSBezierPath()
        extensions.lineWidth = CurveStyle.curveWidth - 1
        extensions.setLineDash([4, 3], count: 2, phase: 0)
        extensions.move(to: start)
        extensions.line(to: firstPoint)
        extensions.move(to: lastPoint)
        extensions.line(to: end)
        NSColor.controlAccentColor.withAlphaComponent(CurveStyle.extensionAlpha).setStroke()
        extensions.stroke()

        let line = NSBezierPath()
        line.lineWidth = CurveStyle.curveWidth
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        line.move(to: firstPoint)
        for point in points.dropFirst() {
            line.line(to: mapping.point(t: point.t, p: point.p))
        }
        NSColor.controlAccentColor.setStroke()
        line.stroke()
    }

    private func drawDots(in plot: NSRect) {
        guard isEditable else { return }
        for (index, point) in points.enumerated() where point.t >= 0 && point.t <= CurveGeometry.maxTemperature {
            let center = mapping.point(t: point.t, p: point.p)
            let active = index == dragIndex || (dragIndex == nil && index == hoverIndex)
            let radius = active ? CurveStyle.dotRadiusActive : CurveStyle.dotRadius
            let dot = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            NSColor.controlAccentColor.setFill()
            dot.fill()
            NSColor.textBackgroundColor.setStroke()
            dot.lineWidth = CurveStyle.dotRingWidth
            dot.stroke()
        }
    }

    /// Each axis is a title followed by an arrow that runs to the end of the plot: "Temperature (°C) ——→".
    private func drawAxes(in plot: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CurveStyle.titleFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.secondaryLabelColor.setStroke()

        let xTitle = "Temperature (\u{00B0}C)" as NSString
        let xSize = xTitle.size(withAttributes: attributes)
        let xBaseline = bounds.minY + (CurveStyle.bottomMargin - xSize.height) / 2
        xTitle.draw(at: NSPoint(x: plot.minX, y: xBaseline), withAttributes: attributes)
        drawArrow(length: plot.maxX - plot.minX - xSize.width - CurveStyle.arrowGap,
                  origin: CGPoint(x: plot.minX + xSize.width + CurveStyle.arrowGap, y: xBaseline + xSize.height / 2))

        // The Y title reads bottom to top, so the whole axis is drawn rotated 90 degrees counter-clockwise.
        let yTitle = "Fan speed" as NSString
        let ySize = yTitle.size(withAttributes: attributes)
        context.saveGState()
        context.translateBy(x: bounds.minX + (CurveStyle.leftMargin + ySize.height) / 2, y: plot.minY)
        context.rotate(by: .pi / 2)
        yTitle.draw(at: .zero, withAttributes: attributes)
        drawArrow(length: plot.height - ySize.width - CurveStyle.arrowGap,
                  origin: CGPoint(x: ySize.width + CurveStyle.arrowGap, y: ySize.height / 2))
        context.restoreGState()
    }

    private func drawArrow(length: CGFloat, origin: CGPoint) {
        guard length > CurveStyle.arrowHead * 2 else { return }
        let tip = CGPoint(x: origin.x + length, y: origin.y)
        let arrow = NSBezierPath()
        arrow.lineWidth = 1
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: origin)
        arrow.line(to: tip)
        arrow.move(to: CGPoint(x: tip.x - CurveStyle.arrowHead, y: tip.y + CurveStyle.arrowHead * 0.7))
        arrow.line(to: tip)
        arrow.line(to: CGPoint(x: tip.x - CurveStyle.arrowHead, y: tip.y - CurveStyle.arrowHead * 0.7))
        arrow.stroke()
    }

    private func drawDragReadout(in plot: NSRect) {
        guard let index = dragIndex, points.indices.contains(index) else { return }
        let point = points[index]
        let lines = [String(format: "%.0f\u{00B0}C", point.t), speed.text(forCurvePercent: point.p)]
        let size = CurvePill.size(for: lines)
        let center = mapping.point(t: point.t, p: point.p)
        // Prefer up and to the right of the dot; flip to the other side near the plot edges.
        var x = center.x + CurveStyle.pillOffset + CurveStyle.dotRadiusActive
        if x + size.width > plot.maxX {
            x = center.x - CurveStyle.pillOffset - CurveStyle.dotRadiusActive - size.width
        }
        var y = center.y + CurveStyle.pillOffset + CurveStyle.dotRadiusActive
        if y + size.height > plot.maxY {
            y = center.y - CurveStyle.pillOffset - CurveStyle.dotRadiusActive - size.height
        }
        let origin = NSPoint(
            x: min(max(x, plot.minX), plot.maxX - size.width),
            y: min(max(y, plot.minY), plot.maxY - size.height)
        )
        CurvePill.draw(lines, at: origin, size: size, tint: .controlAccentColor)
    }
}
