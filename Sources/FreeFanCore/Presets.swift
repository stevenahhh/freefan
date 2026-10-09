import Foundation
import FreeFanSMC

public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var input: FanControlInput
    public var points: [CurvePoint]

    public init(id: String, name: String, input: FanControlInput, points: [CurvePoint]) {
        self.id = id
        self.name = name
        self.input = input
        self.points = points
    }

    public var curve: FanCurve { FanCurve(points: points) }
}

/// On-disk shape of ~/Library/Application Support/FreeFan/presets.json.
public struct PresetLibrary: Codable, Equatable, Sendable {
    public static let autoID = "auto"
    public static let currentVersion = 1

    public var version: Int
    /// A preset id, or PresetLibrary.autoID when the fans follow the system (F{n}md = 0).
    public var active: String
    public var presets: [Preset]

    public init(version: Int = PresetLibrary.currentVersion, active: String = PresetLibrary.autoID, presets: [Preset]) {
        self.version = version
        self.active = active
        self.presets = presets
    }

    public func preset(id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    public var activePreset: Preset? { preset(id: active) }

    // TODO(node-curve-presets): defaults() returns Auto active with these four presets:
    //   Silent      id "silent"       input max  50:0, 70:15, 85:45, 95:100
    //   Balanced    id "balanced"     input max  45:5, 60:20, 75:45, 90:80, 95:100
    //   Performance id "performance"  input max  40:20, 55:40, 70:70, 85:100
    //   Full        id "full"         input max  30:100, 100:100
    public static func defaults() -> PresetLibrary {
        PresetLibrary(presets: [])
    }
}

/// Loads and saves the preset library. File format:
/// { "version": 1, "active": "<id|auto>", "presets": [ { "id", "name", "input", "points": [ { "t", "p" } ] } ] }
public final class PresetStore {
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FreeFan").appendingPathComponent("presets.json")
    }

    public let url: URL
    public private(set) var library: PresetLibrary

    public init(url: URL = PresetStore.defaultURL) {
        self.url = url
        self.library = PresetLibrary.defaults()
    }

    // TODO(node-curve-presets): load() reads the file; when it is missing, write defaults(); when it is
    // unreadable or not decodable, move it aside to presets.json.bak and fall back to defaults; drop
    // presets whose curve fails validate(). save() writes atomically (create the parent directory first).
    // setActive/upsert/remove mutate then save. Keep the file human-readable (sorted keys, indented).

    @discardableResult
    public func load() throws -> PresetLibrary {
        library
    }

    public func save() throws {
    }

    public func setActive(_ id: String) throws {
    }

    public func upsert(_ preset: Preset) throws {
    }

    public func remove(id: String) throws {
    }
}
