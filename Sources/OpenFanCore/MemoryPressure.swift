import Foundation

/// The memory pressure state macOS reports. These are the values of `kern.memorystatus_vm_pressure_level`,
/// the same source Activity Monitor colors its Memory Pressure graph with: 1 green, 2 yellow, 4 red.
public enum MemoryPressure: Int, CaseIterable, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4

    /// The current level, or nil when the sysctl fails or reports a value that is not one of the three states.
    /// One sysctl call.
    public static func read() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0,
              size == MemoryLayout<Int32>.size else { return nil }
        return MemoryPressure(rawValue: Int(level))
    }

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

/// Calls back when the system changes its memory pressure level, so nothing has to poll for it.
public final class MemoryPressureMonitor {
    private let source: DispatchSourceMemoryPressure

    public init(queue: DispatchQueue = .main, onChange: @escaping (MemoryPressure?) -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
        source.setEventHandler { onChange(MemoryPressure.read()) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
