import Foundation
import FreeFanSMC

public enum CurveError: Error, CustomStringConvertible, Equatable {
    case tooFewPoints(Int)
    case tooManyPoints(Int)
    case notStrictlyIncreasing(index: Int)
    case temperatureOutOfRange(index: Int)
    case percentOutOfRange(index: Int)
    case decreasingPercent(index: Int)

    public var description: String {
        switch self {
        case .tooFewPoints(let n): return "curve needs at least 2 points (has \(n))"
        case .tooManyPoints(let n): return "curve allows at most 12 points (has \(n))"
        case .notStrictlyIncreasing(let i): return "point \(i) is not strictly above the previous temperature"
        case .temperatureOutOfRange(let i): return "point \(i) temperature is outside 0...130"
        case .percentOutOfRange(let i): return "point \(i) percent is outside 0...100"
        case .decreasingPercent(let i): return "point \(i) percent is below the previous point (a hotter point must not slow the fan)"
        }
    }
}

/// One control point: temperature in Celsius, speed as percent of the fan's [Mn, Mx] range.
public struct CurvePoint: Codable, Equatable, Sendable {
    public var t: Double
    public var p: Double

    public init(t: Double, p: Double) {
        self.t = t
        self.p = p
    }
}

/// Piecewise-linear temperature-to-speed curve.
public struct FanCurve: Codable, Equatable, Sendable {
    public static let minPoints = 2
    public static let maxPoints = 12
    public static let minTemperature: Double = 0
    public static let maxTemperature: Double = 130

    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points
    }

    // TODO(node-curve-presets): implement validate() and percent(at:).
    // validate(): 2...12 points, finite values, t strictly increasing inside 0...130, p inside 0...100 and
    // non-decreasing (a hotter input must never lower the fan). percent(at:): clamp below the first and
    // above the last point, linear interpolation between neighbouring points.

    public func validate() throws {
        throw CurveError.tooFewPoints(points.count)
    }

    public func percent(at temperature: Double) -> Double {
        0
    }
}
