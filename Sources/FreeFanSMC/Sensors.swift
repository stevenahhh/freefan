import Foundation

// MARK: - Temperature inputs

/// Which sensor feeds a curve.
public enum FanControlInput: String, Codable, CaseIterable, Sendable {
    case max
    case cpu
    case gpu
}

// MARK: - Key catalogue (verified present on Mac17,9 / M5 Pro)

public enum SensorCatalog {
    /// Super cores: Tp00 Tp04 Tp08 Tp0C Tp0G Tp0K. Performance cores: Tp0O Tp0R Tp0U Tp0X Tp0a Tp0d
    /// Tp0g Tp0j Tp0m Tp0p Tp0u Tp0y. All 18 keys verified present on this machine.
    public static let cpuKeys: [String] = [
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d",
        "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y",
    ]

    /// Tg0U Tg0X Tg0d Tg0g Tg0j Tg1Y Tg1c. Tg1g is absent on Mac17,9.
    public static let gpuKeys: [String] = [
        "Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c",
    ]

    /// Readings outside this window (or NaN) are discarded.
    public static let temperatureFloor: Float = 0
    public static let temperatureCeiling: Float = 130
}

// MARK: - Fan types

public struct FanInfo: Codable, Equatable, Sendable {
    public let index: Int
    public let minRPM: Float
    public let maxRPM: Float

    public init(index: Int, minRPM: Float, maxRPM: Float) {
        self.index = index
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    public var modeKey: String { "F\(index)md" }
    public var targetKey: String { "F\(index)Tg" }
    public var actualKey: String { "F\(index)Ac" }

    /// Clamp a requested RPM into the fan's [Mn, Mx] range. Never returns a value outside it.
    public func clamp(_ rpm: Float) -> Float {
        min(max(rpm, minRPM), maxRPM)
    }

    /// Map a 0...100 percent of [Mn, Mx] to RPM. Out-of-band percents are clamped first.
    public func rpm(percent: Double) -> Float {
        let p = Float(min(max(percent, 0), 100))
        return clamp(minRPM + p / 100 * (maxRPM - minRPM))
    }
}

public struct FanReading: Equatable, Sendable {
    public let index: Int
    public let rpm: Float?
    public let targetRPM: Float?
    public let manual: Bool

    public init(index: Int, rpm: Float?, targetRPM: Float?, manual: Bool) {
        self.index = index
        self.rpm = rpm
        self.targetRPM = targetRPM
        self.manual = manual
    }
}

public struct SensorReading: Equatable, Sendable {
    public let cpu: Float?
    public let gpu: Float?
    public let fans: [FanReading]

    public init(cpu: Float?, gpu: Float?, fans: [FanReading]) {
        self.cpu = cpu
        self.gpu = gpu
        self.fans = fans
    }

    /// The temperature a preset's input selects.
    public func input(_ kind: FanControlInput) -> Float? {
        switch kind {
        case .cpu: return cpu
        case .gpu: return gpu
        case .max:
            switch (cpu, gpu) {
            case let (c?, g?): return max(c, g)
            case let (c?, nil): return c
            case let (nil, g?): return g
            default: return nil
            }
        }
    }
}

// MARK: - Reader

/// Discovers which sensor keys exist once, then reads them each tick.
public final class Telemetry {
    public private(set) var fans: [FanInfo] = []

    /// TODO(node-sensor-read): discover which CPU/GPU keys are present ONCE (a missing key costs about
    /// 50x a present one to read, so never read an absent key twice), keep the discovered lists, read
    /// FNum, and read each fan's Mn/Mx for FanInfo. Keep the SMC connection for the life of the object.
    public init(smc: SMC) throws {
        throw SMCError.serviceNotFound
    }

    /// Reads CPU max, GPU max and per-fan actual/target/manual. Failed or out-of-range values are nil.
    public func read() -> SensorReading {
        SensorReading(cpu: nil, gpu: nil, fans: [])
    }
}
