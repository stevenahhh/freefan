import Foundation
import FreeFanSMC

/// How a fan speed is worded for the person looking at it, so the header and the graph's readouts say the same thing
/// about the same speed: a percentage of the fan's top speed, or rpm.
public struct FanSpeedFormat: Equatable, Sendable {
    public var fan: FanInfo?
    public var showsRPM: Bool

    public init(fan: FanInfo?, showsRPM: Bool) {
        self.fan = fan
        self.showsRPM = showsRPM
    }

    /// What a curve value asks the fan to do. A curve is drawn between the fan's slowest and fastest speed, so its own
    /// percentage is not a percentage of top speed and is never shown. At 0 or below the fans go back to macOS.
    public func text(forCurvePercent percent: Double) -> String {
        guard let fan else { return "--" }
        guard percent > 0 else { return "Auto" }
        let rpm = fan.rpm(percent: percent)
        if showsRPM { return "\(Int(rpm.rounded())) rpm" }
        return "\(Int((rpm / fan.maxRPM * 100).rounded()))%"
    }
}
