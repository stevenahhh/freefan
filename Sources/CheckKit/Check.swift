import Foundation

/// Minimal assertion harness. XCTest and Swift Testing are unavailable with Command Line Tools only,
/// so every check target is an executable that exits non-zero on failure.
public final class Checker {
    public let name: String
    private var failures: [String] = []
    private var passes: Int = 0

    public init(_ name: String) { self.name = name }

    public func expect(_ condition: Bool, _ label: String, file: StaticString = #fileID, line: UInt = #line) {
        if condition { passes += 1 } else { failures.append("\(label) (\(file):\(line))") }
    }

    public func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String, file: StaticString = #fileID, line: UInt = #line) {
        expect(actual == expected, "\(label): expected \(expected), got \(actual)", file: file, line: line)
    }

    public func expectClose(_ actual: Double, _ expected: Double, tolerance: Double, _ label: String, file: StaticString = #fileID, line: UInt = #line) {
        expect(abs(actual - expected) <= tolerance, "\(label): expected \(expected) +/- \(tolerance), got \(actual)", file: file, line: line)
    }

    public func expectThrows(_ label: String, _ body: () throws -> Void, file: StaticString = #fileID, line: UInt = #line) {
        do {
            try body()
            expect(false, "\(label): expected a throw", file: file, line: line)
        } catch {
            passes += 1
        }
    }

    public func expectNoThrow<T>(_ label: String, _ body: () throws -> T, file: StaticString = #fileID, line: UInt = #line) -> T? {
        do {
            let value = try body()
            passes += 1
            return value
        } catch {
            expect(false, "\(label): unexpected throw \(error)", file: file, line: line)
            return nil
        }
    }

    public func summary() -> Int32 {
        if failures.isEmpty {
            print("[\(name)] PASS (\(passes) checks)")
            return 0
        }
        print("[\(name)] FAIL (\(failures.count) of \(passes + failures.count) checks)")
        for failure in failures { print("  - \(failure)") }
        return 1
    }
}
