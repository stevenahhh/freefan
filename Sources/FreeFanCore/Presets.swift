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

    /// Auto active, version 1, with the four built-in presets.
    public static func defaults() -> PresetLibrary {
        PresetLibrary(
            version: currentVersion,
            active: autoID,
            presets: [
                Preset(id: "silent", name: "Silent", input: FanControlInput.max, points: [
                    CurvePoint(t: 50, p: 0),
                    CurvePoint(t: 70, p: 15),
                    CurvePoint(t: 85, p: 45),
                    CurvePoint(t: 95, p: 100),
                ]),
                Preset(id: "balanced", name: "Balanced", input: FanControlInput.max, points: [
                    CurvePoint(t: 45, p: 5),
                    CurvePoint(t: 60, p: 20),
                    CurvePoint(t: 75, p: 45),
                    CurvePoint(t: 90, p: 80),
                    CurvePoint(t: 95, p: 100),
                ]),
                Preset(id: "performance", name: "Performance", input: FanControlInput.max, points: [
                    CurvePoint(t: 40, p: 20),
                    CurvePoint(t: 55, p: 40),
                    CurvePoint(t: 70, p: 70),
                    CurvePoint(t: 85, p: 100),
                ]),
                Preset(id: "full", name: "Full", input: FanControlInput.max, points: [
                    CurvePoint(t: 30, p: 100),
                    CurvePoint(t: 100, p: 100),
                ]),
            ]
        )
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

    // load() reads the file; when it is missing, write defaults(); when it is unreadable or not decodable,
    // move it aside to <url>.bak and fall back to defaults; drop presets whose curve fails validate().
    // save() writes atomically (creating the parent directory first), sorted keys, indented.
    // setActive/upsert/remove mutate then save.

    @discardableResult
    public func load() throws -> PresetLibrary {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            library = PresetLibrary.defaults()
            try save()
            return library
        }

        let decoded: PresetLibrary
        do {
            let data = try Data(contentsOf: url)
            decoded = try JSONDecoder().decode(PresetLibrary.self, from: data)
        } catch {
            let backup = URL(fileURLWithPath: url.path + ".bak")
            try? fileManager.removeItem(at: backup)
            try? fileManager.moveItem(at: url, to: backup)
            library = PresetLibrary.defaults()
            try save()
            return library
        }

        var sanitized = decoded
        sanitized.presets = decoded.presets.filter { (try? $0.curve.validate()) != nil }
        if sanitized.active != PresetLibrary.autoID && sanitized.preset(id: sanitized.active) == nil {
            sanitized.active = PresetLibrary.autoID
        }
        library = sanitized
        if sanitized != decoded {
            try save()
        }
        return library
    }

    public func save() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try data.write(to: url, options: [.atomic])
    }

    public func setActive(_ id: String) throws {
        library.active = id
        try save()
    }

    public func upsert(_ preset: Preset) throws {
        if let index = library.presets.firstIndex(where: { $0.id == preset.id }) {
            library.presets[index] = preset
        } else {
            library.presets.append(preset)
        }
        try save()
    }

    public func remove(id: String) throws {
        library.presets.removeAll { $0.id == id }
        if library.active == id {
            library.active = PresetLibrary.autoID
        }
        try save()
    }
}
