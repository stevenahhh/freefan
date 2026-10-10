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

    public var isBuiltIn: Bool { PresetLibrary.builtInIDs.contains(id) }

    /// Full holds both fans at maximum speed whatever the temperature, so the editor shows its note instead of a graph.
    public var isFullSpeed: Bool { id == PresetLibrary.fullID }

    /// What the editor says about the preset it cannot edit; empty for the user's own presets.
    public var editorNote: String {
        if isFullSpeed {
            return "Full: both fans run at maximum speed.\n" + PresetLibrary.chooseHint
        }
        return isBuiltIn ? "Built-in preset. Duplicate it to make your own curve." : ""
    }
}

public struct PresetLibrary: Codable, Equatable, Sendable {
    public static let autoID = "auto"
    public static let fullID = "full"
    static let chooseHint = "Choose a preset above to apply it, or duplicate one to make it yours."
    /// What the editor says instead of a graph while the fans follow the system.
    public static let autoNote = "Auto: macOS controls the fans.\n" + chooseHint
    /// Version 2 stores only the user's presets; version 1 also stored copies of the built-ins.
    public static let currentVersion = 2

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

    public var customPresets: [Preset] { presets.filter { !$0.isBuiltIn } }

    /// Every built-in curve stops the fans (0 %) at or below 30 C. Full is not a curve: it holds both fans at
    /// maximum speed whatever the temperature.
    public static let builtIns: [Preset] = [
        Preset(id: "silent", name: "Silent", input: .max, points: [
            CurvePoint(t: 30, p: 0), CurvePoint(t: 50, p: 5), CurvePoint(t: 70, p: 15),
            CurvePoint(t: 85, p: 45), CurvePoint(t: 95, p: 100),
        ]),
        Preset(id: "balanced", name: "Balanced", input: .max, points: [
            CurvePoint(t: 30, p: 0), CurvePoint(t: 45, p: 5), CurvePoint(t: 60, p: 20),
            CurvePoint(t: 75, p: 45), CurvePoint(t: 90, p: 80), CurvePoint(t: 95, p: 100),
        ]),
        Preset(id: "performance", name: "Performance", input: .max, points: [
            CurvePoint(t: 30, p: 0), CurvePoint(t: 40, p: 20), CurvePoint(t: 55, p: 40),
            CurvePoint(t: 70, p: 70), CurvePoint(t: 85, p: 100),
        ]),
        Preset(id: fullID, name: "Full", input: .max, points: [
            CurvePoint(t: 0, p: 100), CurvePoint(t: 130, p: 100),
        ]),
    ]

    static let builtInIDs = Set(builtIns.map(\.id))

    public static func defaults() -> PresetLibrary {
        PresetLibrary(active: autoID, presets: builtIns)
    }

    public func newCustomID() -> String {
        Self.freeCustomID(taken: Set(presets.map(\.id)))
    }

    /// The curve the editor offers when there is nothing to copy: zero fan up to 30 C, then a steady rise.
    public static let starterPoints = [
        CurvePoint(t: 30, p: 0),
        CurvePoint(t: 50, p: 15),
        CurvePoint(t: 70, p: 45),
        CurvePoint(t: 95, p: 100),
    ]

    /// A preset for the editor's "new" button: a copy of `source`, or the starter curve when `source` is nil. The id
    /// and the name are free of everything already in the library (built-ins included).
    public func newCustomPreset(copying source: Preset?) -> Preset {
        Preset(
            id: newCustomID(),
            name: freeName(based: source.map { "\($0.name) Copy" } ?? "New Preset"),
            input: source?.input ?? .max,
            points: source?.points ?? Self.starterPoints
        )
    }

    public func freeName(based base: String) -> String {
        let taken = Set(presets.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
    }

    /// The built-ins followed by the stored user presets. A stored preset with a built-in id is a version 1 copy:
    /// dropped when untouched, otherwise kept as a user preset that the active selection follows.
    static func merging(_ stored: PresetLibrary) -> PresetLibrary {
        let valid = stored.presets.filter { (try? $0.curve.validate()) != nil }
        var taken = builtInIDs.union(valid.map(\.id))
        var active = stored.active
        var custom: [Preset] = []
        for preset in valid {
            guard preset.isBuiltIn else {
                custom.append(preset)
                continue
            }
            if preset == legacyBuiltIns[preset.id] { continue }
            let id = freeCustomID(taken: taken)
            taken.insert(id)
            let clashes = builtIns.contains { $0.name == preset.name }
            custom.append(Preset(id: id, name: clashes ? "\(preset.name) (edited)" : preset.name, input: preset.input, points: preset.points))
            if active == preset.id { active = id }
        }
        var merged = PresetLibrary(active: active, presets: builtIns + custom)
        if active != autoID && merged.preset(id: active) == nil { merged.active = autoID }
        return merged
    }

    private static func freeCustomID(taken: Set<String>) -> String {
        var number = 1
        while taken.contains("custom-\(number)") { number += 1 }
        return "custom-\(number)"
    }

    /// The built-ins as version 1 stored them, to recognise untouched copies.
    private static let legacyBuiltIns: [String: Preset] = Dictionary(uniqueKeysWithValues: [
        Preset(id: "silent", name: "Silent", input: .max, points: [
            CurvePoint(t: 50, p: 0), CurvePoint(t: 70, p: 15), CurvePoint(t: 85, p: 45), CurvePoint(t: 95, p: 100),
        ]),
        Preset(id: "balanced", name: "Balanced", input: .max, points: [
            CurvePoint(t: 45, p: 5), CurvePoint(t: 60, p: 20), CurvePoint(t: 75, p: 45),
            CurvePoint(t: 90, p: 80), CurvePoint(t: 95, p: 100),
        ]),
        Preset(id: "performance", name: "Performance", input: .max, points: [
            CurvePoint(t: 40, p: 20), CurvePoint(t: 55, p: 40), CurvePoint(t: 70, p: 70), CurvePoint(t: 85, p: 100),
        ]),
        Preset(id: fullID, name: "Full", input: .max, points: [CurvePoint(t: 30, p: 100), CurvePoint(t: 100, p: 100)]),
    ].map { ($0.id, $0) })
}

public enum PresetStoreError: Error, Equatable, CustomStringConvertible {
    case builtIn(String)

    public var description: String {
        switch self {
        case .builtIn(let id): return "\(id) is a built-in preset and cannot be changed"
        }
    }
}

/// Loads and saves the preset library. The file holds only the user's presets:
/// { "version": 2, "active": "<id|auto>", "presets": [ { "id", "name", "input", "points": [ { "t", "p" } ] } ] }
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

    /// Missing file: defaults are written. Unreadable file: moved aside to <url>.bak, defaults written. Otherwise
    /// the stored presets are merged with the built-ins, and the file is rewritten only when that changed it.
    @discardableResult
    public func load() throws -> PresetLibrary {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            library = PresetLibrary.defaults()
            try save()
            return library
        }

        let decoded: PresetLibrary
        do {
            decoded = try JSONDecoder().decode(PresetLibrary.self, from: Data(contentsOf: url))
        } catch {
            let backup = URL(fileURLWithPath: url.path + ".bak")
            try? fileManager.removeItem(at: backup)
            try? fileManager.moveItem(at: url, to: backup)
            library = PresetLibrary.defaults()
            try save()
            return library
        }

        library = PresetLibrary.merging(decoded)
        if stored != decoded {
            try save()
        }
        return library
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stored).write(to: url, options: [.atomic])
    }

    public func setActive(_ id: String) throws {
        library.active = id
        try save()
    }

    public func upsert(_ preset: Preset) throws {
        guard !preset.isBuiltIn else { throw PresetStoreError.builtIn(preset.id) }
        if let index = library.presets.firstIndex(where: { $0.id == preset.id }) {
            library.presets[index] = preset
        } else {
            library.presets.append(preset)
        }
        try save()
    }

    public func remove(id: String) throws {
        guard !(library.preset(id: id)?.isBuiltIn ?? false) else { throw PresetStoreError.builtIn(id) }
        library.presets.removeAll { $0.id == id }
        if library.active == id {
            library.active = PresetLibrary.autoID
        }
        try save()
    }

    private var stored: PresetLibrary {
        PresetLibrary(active: library.active, presets: library.customPresets)
    }
}
