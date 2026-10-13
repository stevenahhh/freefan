import AppKit
import OpenFanCore

/// Checks GitHub for a newer release and installs it. Nothing is shown unless an update exists; a failed check is
/// silent and tried again at the next opportunity. The check runs at launch and when the popover opens, at most once a
/// day, so a closed app has no timer for it.
final class Updater {
    enum State: Equatable {
        case idle
        case available(AvailableUpdate)
        case installing(AppVersion)
        case failed(AvailableUpdate, String)
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onChange?() } }
    }
    var onChange: (() -> Void)?

    private static let latestURL = URL(string: "https://api.github.com/repos/stevenahhh/openfan/releases/latest")!
    private static let lastCheckKey = "UpdateLastCheck"
    private let session: URLSession
    private var checking = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "OpenFan", "Accept": "application/vnd.github+json"]
        session = URLSession(configuration: configuration)
    }

    private var currentVersion: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        guard UpdateSchedule.isDue(lastCheck: last, now: Date()) else { return }
        check()
    }

    private func check() {
        guard !checking, let current = currentVersion else { return }
        if case .installing = state { return }
        checking = true
        session.dataTask(with: Self.latestURL) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                if let update = AvailableUpdate.parse(data, newerThan: current) {
                    self.state = .available(update)
                } else {
                    switch self.state {
                    case .available, .failed: self.state = .idle
                    case .idle, .installing: break
                    }
                }
            }
        }.resume()
    }

    /// Downloads the archive and its signature, verifies the signature, unpacks the app next to the running one,
    /// checks that it is OpenFan with the announced version and a valid code signature, swaps it in and relaunches.
    func install() {
        let update: AvailableUpdate
        switch state {
        case let .available(found), let .failed(found, _): update = found
        case .idle, .installing: return
        }
        state = .installing(update.version)
        let target = Bundle.main.bundleURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self, session] in
            let result = Result { try Self.prepare(update, replacing: target, session: session) }
            DispatchQueue.main.async {
                switch result {
                case let .success(staged):
                    do {
                        try Self.swap(staged: staged, into: target)
                        Self.relaunch(target)
                    } catch {
                        self?.state = .failed(update, error.localizedDescription)
                    }
                case let .failure(error):
                    self?.state = .failed(update, error.localizedDescription)
                }
            }
        }
    }

    // MARK: Steps

    struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static func download(_ url: URL, session: URLSession) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(UpdateError("no response"))
        session.dataTask(with: url) { data, response, error in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                result = .success(data)
            } else {
                result = .failure(error ?? UpdateError("download returned \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result.get()
    }

    /// The new app, unpacked and checked, in a folder next to the running one (same volume, so the swap is a rename).
    private static func prepare(_ update: AvailableUpdate, replacing target: URL, session: URLSession) throws -> URL {
        let archive = try download(update.archiveURL, session: session)
        let signature = try download(update.signatureURL, session: session)
        guard UpdateSignature.isValid(archive: archive, signature: signature) else {
            throw UpdateError("the download is not signed by OpenFan's release key")
        }
        let fileManager = FileManager.default
        let staging = target.deletingLastPathComponent().appendingPathComponent(".OpenFan-update-\(update.version)")
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let zip = staging.appendingPathComponent(AvailableUpdate.archiveName)
        try archive.write(to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        try? fileManager.removeItem(at: zip)

        let app = staging.appendingPathComponent("OpenFan.app")
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init) == update.version
        else { throw UpdateError("the download is not OpenFan \(update.version)") }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        // Downloaded through URLSession the files carry no quarantine flag; clear it anyway so the new app opens.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// The running app moves aside, the new one takes its place, and the old one is deleted. If the second rename
    /// fails the old app is put back, so a failed update never leaves no app behind.
    private static func swap(staged: URL, into target: URL) throws {
        let fileManager = FileManager.default
        let aside = staged.deletingLastPathComponent().appendingPathComponent("OpenFan-previous.app")
        try? fileManager.removeItem(at: aside)
        try fileManager.moveItem(at: target, to: aside)
        do {
            try fileManager.moveItem(at: staged, to: target)
        } catch {
            try? fileManager.moveItem(at: aside, to: target)
            throw error
        }
        try? fileManager.removeItem(at: staged.deletingLastPathComponent())
    }

    /// A shell waits for this process to exit, then opens the new app, so the two never run at once.
    private static func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$1\"",
                             String(getpid()), app.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) failed (\(process.terminationStatus))")
        }
        return process.terminationStatus
    }
}
