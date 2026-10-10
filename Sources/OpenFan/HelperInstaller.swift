import Foundation
import OpenFanCore

/// Runs the app-bundle helper scripts through one administrator prompt: the script path is passed to
/// `/usr/bin/osascript -e "do shell script \"...\" with administrator privileges"`, so a cancelled
/// password prompt comes back as a non-zero status with "User canceled." instead of crashing.
final class HelperInstaller {
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperPaths.daemonPlistPath)
    }

    func install(completion: @escaping (Int32, String) -> Void) {
        run(script: "install-helper.sh", arguments: [String(getuid())], completion: completion)
    }

    func uninstall(completion: @escaping (Int32, String) -> Void) {
        run(script: "uninstall-helper.sh", arguments: [], completion: completion)
    }

    /// `completion` runs on the main queue with the exit status and the first non-empty output line.
    private func run(script: String, arguments: [String], completion: @escaping (Int32, String) -> Void) {
        let resourcePath = Bundle.main.resourcePath ?? Bundle.main.bundlePath
        let scriptPath = (resourcePath as NSString).appendingPathComponent(script)
        let command = ([scriptPath] + arguments).map(Self.shellQuote).joined(separator: " ")
        let source = "do shell script \"\(Self.appleScriptEscape(command))\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            var status: Int32 = -1
            var message = ""
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                status = process.terminationStatus
                message = Self.firstLine(String(decoding: data, as: UTF8.self))
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async { completion(status, message) }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func firstLine(_ output: String) -> String {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
