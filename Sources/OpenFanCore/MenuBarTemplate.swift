import Foundation
import OpenFanSMC

public struct MenuBarValues: Equatable, Sendable {
    public var max: Float?
    public var cpu: Float?
    public var gpu: Float?
    public var battery: Float?
    public var fanRPMs: [Float?]
    public var presetName: String?

    public init(
        max: Float? = nil,
        cpu: Float? = nil,
        gpu: Float? = nil,
        battery: Float? = nil,
        fanRPMs: [Float?] = [],
        presetName: String? = nil
    ) {
        self.max = max
        self.cpu = cpu
        self.gpu = gpu
        self.battery = battery
        self.fanRPMs = fanRPMs
        self.presetName = presetName
    }

    public init(reading: SensorReading?, presetName: String?) {
        self.init(
            max: reading?.input(.max),
            cpu: reading?.cpu,
            gpu: reading?.gpu,
            battery: reading?.battery,
            fanRPMs: reading?.fans.map { $0.rpm } ?? [],
            presetName: presetName
        )
    }
}

/// Renders the user's menu bar text. A token is `{name}` for one of `tokens`; anything else, including a brace
/// without a matching token, stays literal. Substituted values are never expanded again. An empty template renders
/// as empty text.
public enum MenuBarTemplate {
    public static let tokens = ["max", "cpu", "gpu", "bat", "rpm", "rpm0", "rpm1", "preset"]
    public static let maxRenderedLength = 40

    /// The sensor groups the template's tokens need, so a closed popover reads only those (none at all for a
    /// template without sensor tokens, empty included).
    public static func sensors(in template: String) -> SensorSet {
        var needed: SensorSet = []
        for token in tokens where template.contains("{\(token)}") {
            switch token {
            case "max": needed.formUnion([.cpu, .gpu])
            case "cpu": needed.insert(.cpu)
            case "gpu": needed.insert(.gpu)
            case "bat": needed.insert(.battery)
            case "rpm", "rpm0", "rpm1": needed.insert(.fans)
            default: break
            }
        }
        return needed
    }

    public static func render(_ template: String, _ values: MenuBarValues) -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "{", let close = template[index...].firstIndex(of: "}") {
                let name = String(template[template.index(after: index)..<close])
                if let text = text(for: name, in: values) {
                    result += text
                    index = template.index(after: close)
                    continue
                }
            }
            result.append(character)
            index = template.index(after: index)
        }
        return String(result.prefix(maxRenderedLength))
    }

    private static func text(for token: String, in values: MenuBarValues) -> String? {
        switch token {
        case "max": return temperature(values.max)
        case "cpu": return temperature(values.cpu)
        case "gpu": return temperature(values.gpu)
        case "bat": return temperature(values.battery)
        case "rpm": return rpm(values.fanRPMs.compactMap { $0 }.max())
        case "rpm0": return rpm(values.fanRPMs.indices.contains(0) ? values.fanRPMs[0] : nil)
        case "rpm1": return rpm(values.fanRPMs.indices.contains(1) ? values.fanRPMs[1] : nil)
        case "preset": return values.presetName ?? "--"
        default: return nil
        }
    }

    private static func temperature(_ value: Float?) -> String {
        guard let value, value.isFinite, abs(value) < 1_000_000 else { return "--" }
        return String(Int(value.rounded()))
    }

    private static func rpm(_ value: Float?) -> String {
        guard let value, value.isFinite, value >= 0, value < 1_000_000 else { return "--" }
        return value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : String(Int(value.rounded()))
    }
}
