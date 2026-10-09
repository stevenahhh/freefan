import Foundation
import FreeFanSMC
import FreeFanCore

public struct ControllerConfig: Equatable, Sendable {
    /// Downward hysteresis in Celsius: the used temperature only follows a drop after it exceeds this.
    public var hysteresis: Float = 2.0
    /// Write a new target only when it differs from the last written value by at least this many RPM.
    public var deadbandRPM: Float = 100
    /// At or above this input the fans go to Mx.
    public var panicOn: Float = 95
    /// Below this input the panic state clears.
    public var panicOff: Float = 88

    public init() {}
}

/// One write the helper must perform. Emitted in order: a fan's setTarget always precedes its setManual.
public enum FanAction: Equatable, Sendable {
    case setTarget(fan: Int, rpm: Float)
    case setManual(fan: Int, on: Bool)
}

public struct FanObservation: Equatable, Sendable {
    public var rpm: Float?
    /// Whether F{n}md currently reads 1 (the system may take control back at any time).
    public var manual: Bool

    public init(rpm: Float?, manual: Bool) {
        self.rpm = rpm
        self.manual = manual
    }
}

/// Pure decision engine: temperature plus per-fan observation in, ordered fan writes out.
/// It owns hysteresis, the write dead band, the panic override and re-engagement after a reclaim.
public final class FanController {
    public let fans: [FanInfo]
    public let config: ControllerConfig
    public private(set) var mode: HelperMode = .auto
    public private(set) var writes: Int = 0
    public private(set) var lastError: String?

    public init(fans: [FanInfo], config: ControllerConfig = ControllerConfig()) {
        self.fans = fans
        self.config = config
    }

    // TODO(node-control-engine): implement to this contract.
    // - setAuto(): mode .auto, clear panic/curve state.
    // - setCurve/setFixed: validate first (a curve that fails validate() throws; a null/non-finite or
    //   out-of-range fixed percent throws), then mode .curve/.fixed, panic cleared.
    // - noteWriteFailure(reason): lastError = reason, mode .monitor.
    // - tick(temperature:fans:) returns the ordered writes for this tick:
    //     * mode .auto or .monitor  -> []
    //     * temperature nil or not finite or outside SensorCatalog 0...130 -> release every fan that is
    //       currently manual (.setManual(fan:on:false)) and drop to .auto: a dead sensor must hand the
    //       fans back to the system, never hold a stale target;
    //     * panic latches at panicOn and clears below panicOff; while panicking the target is each fan's
    //       maxRPM (bypassing the dead band on the way in and out);
    //     * otherwise target = fans[i].rpm(percent: curve.percent(at: usedTemperature)) where usedTemperature
    //       tracks the raw temperature up instantly but only follows it down once it has fallen more than
    //       config.hysteresis below the last used value;
    //     * a fan whose F{n}md is not 1 is re-engaged: emit its setTarget FIRST and then setManual(true),
    //       even when the target is inside the dead band of the last written value;
    //     * otherwise emit setTarget only when the new target differs from the last written value for that
    //       fan by at least config.deadbandRPM;
    //     * mode reflects .curve/.fixed, or .panic while panicking.
    // - noteApplied(actions): bump writes for each setTarget/setManual emitted and record the last written
    //   target per fan (this is what the dead band compares against).
    // Keep it free of I/O: it must be fully exercisable from ControlCheck without hardware.

    public func setAuto() {
    }

    public func setCurve(_ curve: FanCurve, input: FanControlInput) throws {
    }

    public func setFixed(percent: Double) throws {
    }

    public func noteWriteFailure(_ reason: String) {
        lastError = reason
        mode = .monitor
    }

    public func tick(temperature: Float?, fans: [FanObservation]) -> [FanAction] {
        []
    }

    public func noteApplied(_ actions: [FanAction]) {
    }
}
