import Foundation
import FreeFanCore

/// Command line: FreeFanHelper [--allow-uid <uid>]... [--socket <path>] [--tick <seconds>]
struct HelperOptions {
    static let usage = "usage: FreeFanHelper [--allow-uid <uid>]... [--socket <path>] [--tick <seconds>]"

    /// The lease is only checked from the tick, so a long tick would blunt the 12 s watchdog.
    static let tickRange: ClosedRange<Double> = 0.1...5.0

    var socketPath: String = HelperPaths.socketPath
    var tick: Double = 1.0
    /// Peers allowed to connect: root, the helper's own euid, plus every --allow-uid value.
    var allowedUIDs: Set<uid_t> = [0, geteuid()]

    /// Parses the arguments; prints the problem plus usage to stderr and exits 2 when they are invalid.
    static func parse(_ arguments: [String]) -> HelperOptions {
        var options = HelperOptions()
        var index = 1
        func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data("FreeFanHelper: \(message)\n\(usage)\n".utf8))
            exit(2)
        }
        func value(for flag: String) -> String {
            index += 1
            guard index < arguments.count else { fail("\(flag) needs a value") }
            return arguments[index]
        }
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--allow-uid":
                let text = value(for: flag)
                guard let uid = uid_t(text) else { fail("--allow-uid needs a numeric uid, got \(text)") }
                options.allowedUIDs.insert(uid)
            case "--socket":
                let text = value(for: flag)
                guard !text.isEmpty else { fail("--socket needs a non-empty path") }
                options.socketPath = text
            case "--tick":
                let text = value(for: flag)
                guard let seconds = Double(text), seconds.isFinite, tickRange.contains(seconds) else {
                    fail("--tick must be a number within \(tickRange.lowerBound)...\(tickRange.upperBound), got \(text)")
                }
                options.tick = seconds
            default:
                fail("unknown argument \(flag)")
            }
            index += 1
        }
        return options
    }
}
