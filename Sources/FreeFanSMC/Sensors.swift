import Foundation

// MARK: - Temperature inputs

/// Which sensor feeds a curve.
public enum FanControlInput: String, Codable, CaseIterable, Sendable {
    case max
    case cpu
    case gpu
    /// Mean of every battery temperature sensor.
    case battery
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

    /// TB0T TB1T TB2T: the battery pack sensors (flt, Celsius). All three verified present on Mac17,9.
    public static let batteryKeys: [String] = ["TB0T", "TB1T", "TB2T"]

    /// Mean of the usable battery readings. A reading counts when it is finite, above 0 (a dead sensor reports
    /// 0.0) and not above the global ceiling; nil when none counts, so one bad sensor cannot skew the mean.
    public static func batteryMean(_ values: [Float]) -> Float? {
        let usable = values.filter { $0.isFinite && $0 > 0 && $0 <= temperatureCeiling }
        guard !usable.isEmpty else { return nil }
        return usable.reduce(0, +) / Float(usable.count)
    }

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
    /// Mean of the battery sensors.
    public let battery: Float?
    public let fans: [FanReading]

    public init(cpu: Float?, gpu: Float?, battery: Float? = nil, fans: [FanReading]) {
        self.cpu = cpu
        self.gpu = gpu
        self.battery = battery
        self.fans = fans
    }

    /// The temperature a preset's input selects.
    public func input(_ kind: FanControlInput) -> Float? {
        switch kind {
        case .cpu: return cpu
        case .gpu: return gpu
        case .battery: return battery
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

    private let smc: SMC
    private let presentCPUKeys: [String]
    private let presentGPUKeys: [String]
    private let presentBatteryKeys: [String]

    /// Discovery happens exactly once here. A key that does not exist is probed once during init and
    /// then never read again (an absent key costs about 50x a present one), so the discovered lists
    /// are what every later tick reads.
    public init(smc: SMC) throws {
        self.smc = smc

        self.presentCPUKeys = SensorCatalog.cpuKeys.filter { smc.keyExists($0) }
        self.presentGPUKeys = SensorCatalog.gpuKeys.filter { smc.keyExists($0) }
        self.presentBatteryKeys = SensorCatalog.batteryKeys.filter { smc.keyExists($0) }

        // FNum is a ui8 key on this platform; fall back to a ui32 variant if that is what is present.
        var fanCount = 0
        if let count = try? smc.readUInt8("FNum") {
            fanCount = Int(count)
        } else if let count = try? smc.readUInt32("FNum") {
            fanCount = Int(count)
        }

        var discovered: [FanInfo] = []
        for index in 0..<fanCount {
            // Read the real limits; never hardcode them. A fan whose limits cannot be read is not
            // usable (clamping to [0, 0] would stop it), so it is skipped rather than defaulted.
            guard let minRPM = try? smc.readFloat("F\(index)Mn"),
                  let maxRPM = try? smc.readFloat("F\(index)Mx"),
                  minRPM.isFinite, maxRPM.isFinite, minRPM > 0, maxRPM > minRPM else { continue }
            discovered.append(FanInfo(index: index, minRPM: minRPM, maxRPM: maxRPM))
        }
        self.fans = discovered
    }

    /// Reads CPU max, GPU max, the battery mean and per-fan actual/target/manual. Failed or out-of-range values are nil.
    public func read() -> SensorReading {
        let cpu = maxTemperature(presentCPUKeys)
        let gpu = maxTemperature(presentGPUKeys)

        var readings: [FanReading] = []
        readings.reserveCapacity(fans.count)
        for fan in fans {
            let rpm = validRPM(try? smc.readFloat(fan.actualKey), fan: fan)
            let target = validRPM(try? smc.readFloat(fan.targetKey), fan: fan)
            let manual = (try? smc.readUInt8(fan.modeKey)) == 1
            readings.append(FanReading(index: fan.index, rpm: rpm, targetRPM: target, manual: manual))
        }

        let battery = SensorCatalog.batteryMean(presentBatteryKeys.compactMap { try? smc.readFloat($0) })
        return SensorReading(cpu: cpu, gpu: gpu, battery: battery, fans: readings)
    }

    // MARK: Internals

    /// Highest valid reading among the keys, or nil when none is valid.
    private func maxTemperature(_ keys: [String]) -> Float? {
        var best: Float?
        for key in keys {
            guard let raw = try? smc.readFloat(key), let value = validTemperature(raw) else { continue }
            best = best.map { max($0, value) } ?? value
        }
        return best
    }

    private func validTemperature(_ value: Float) -> Float? {
        guard value.isFinite,
              value >= SensorCatalog.temperatureFloor,
              value <= SensorCatalog.temperatureCeiling else { return nil }
        return value
    }

    /// A fan RPM is valid when it is finite, non-negative and not absurdly above the fan's own maximum.
    private func validRPM(_ value: Float?, fan: FanInfo) -> Float? {
        guard let value, value.isFinite, value >= 0, value <= fan.maxRPM + 500 else { return nil }
        return value
    }
}
