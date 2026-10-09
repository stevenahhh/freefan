import Foundation
import FreeFanSMC

public enum ProtocolError: Error, CustomStringConvertible, Equatable {
    case emptyLine
    case tooLong(max: Int)
    case unknownCommand(String)
    case malformed(String)
    case badValue(String)

    public var description: String {
        switch self {
        case .emptyLine: return "empty command"
        case .tooLong(let max): return "line longer than \(max) bytes"
        case .unknownCommand(let c): return "unknown command: \(c)"
        case .malformed(let d): return "malformed command: \(d)"
        case .badValue(let d): return "bad value: \(d)"
        }
    }
}

/// Fixed filesystem paths shared by the app, the helper and the install scripts.
public enum HelperPaths {
    public static let label = "com.stevenahhh.freefan.helper"
    public static let socketPath = "/var/run/com.stevenahhh.freefan.sock"
    public static let toolPath = "/Library/PrivilegedHelperTools/com.stevenahhh.freefan.helper"
    public static let daemonPlistPath = "/Library/LaunchDaemons/com.stevenahhh.freefan.helper.plist"
    public static let logPath = "/var/log/com.stevenahhh.freefan.helper.log"
    public static let maxLineBytes = 512
}

/// One line-protocol command, newline terminated over the Unix socket.
///
/// PING | STATUS | AUTO | CURVE <max|cpu|gpu> <t:p,t:p,...> | FIXED <percent>
public enum HelperCommand: Equatable, Sendable {
    case ping
    case status
    case auto
    case curve(input: FanControlInput, points: [CurvePoint])
    case fixed(percent: Double)

    public static func parse(_ line: String) throws -> HelperCommand {
        throw ProtocolError.unknownCommand(line)
    }

    public var serialized: String {
        switch self {
        case .ping: return "PING"
        case .status: return "STATUS"
        case .auto: return "AUTO"
        case .curve(let input, let points):
            let list = points.map { "\(Self.number($0.t)):\(Self.number($0.p))" }.joined(separator: ",")
            return "CURVE \(input.rawValue) \(list)"
        case .fixed(let percent):
            return "FIXED \(Self.number(percent))"
        }
    }

    /// Shortest decimal form: integers print without a fractional part.
    public static func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
    }
}

public enum HelperMode: String, Equatable, Sendable, CaseIterable {
    case auto
    case curve
    case fixed
    case panic
    case monitor
}

/// Reply to STATUS; also carried as the tail of a PING reply when the app asks for it.
public struct HelperStatus: Equatable, Sendable {
    public var mode: HelperMode
    /// Temperature that drove the last decision (nil in auto/monitor).
    public var inputTemperature: Double?
    /// Per-fan target RPM in fan order.
    public var targetRPM: [Float]
    public var writes: Int
    /// e.g. "smc:0x82" when the helper degraded to monitor mode.
    public var error: String?

    public init(mode: HelperMode, inputTemperature: Double? = nil, targetRPM: [Float] = [], writes: Int = 0, error: String? = nil) {
        self.mode = mode
        self.inputTemperature = inputTemperature
        self.targetRPM = targetRPM
        self.writes = writes
        self.error = error
    }

    // TODO(node-curve-presets): serialized -> "OK mode=<mode> temp=<t|-> rpm=<r0,r1|-> writes=<n> [err=<e>]"
    // and parse() the inverse, returning nil on anything malformed. Keep both sides symmetric so a
    // CoreCheck round-trip passes.
    public var serialized: String {
        "OK mode=\(mode.rawValue)"
    }

    public static func parse(_ line: String) -> HelperStatus? {
        nil
    }
}
