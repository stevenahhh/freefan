import Foundation
import OpenFanCore

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
