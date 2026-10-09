import Foundation
import CheckKit
import FreeFanCore

// Executable check for FreeFanCore: fan curve model, preset store and helper wire protocol.
// XCTest / Swift Testing are unavailable on a Command Line Tools only install, so this binary
// exits non-zero on any failed assertion.

let check = Checker("CoreCheck")

// MARK: - Helpers

func silentCurve() -> FanCurve {
    FanCurve(points: [
        CurvePoint(t: 50, p: 0),
        CurvePoint(t: 70, p: 15),
        CurvePoint(t: 85, p: 45),
        CurvePoint(t: 95, p: 100),
    ])
}

func fallbackLibrary() -> PresetLibrary {
    PresetLibrary(version: 0, active: "unset", presets: [])
}

func expectCurveError(_ label: String, _ expected: CurveError, _ points: [CurvePoint], line: UInt = #line) {
    do {
        try FanCurve(points: points).validate()
        check.expect(false, "\(label): expected \(expected), got no error", line: line)
    } catch let error as CurveError {
        check.expectEqual(error, expected, label, line: line)
    } catch {
        check.expect(false, "\(label): expected \(expected), got \(error)", line: line)
    }
}

func expectProtoError(_ label: String, _ expected: ProtocolError, _ text: String, line: UInt = #line) {
    do {
        _ = try HelperCommand.parse(text)
        check.expect(false, "\(label): expected \(expected), got no error", line: line)
    } catch let error as ProtocolError {
        check.expectEqual(error, expected, label, line: line)
    } catch {
        check.expect(false, "\(label): expected \(expected), got \(error)", line: line)
    }
}

func expectRoundTrip(_ label: String, _ text: String, serializedAs expected: String? = nil) {
    let parsed = check.expectNoThrow("\(label): parse") { try HelperCommand.parse(text) }
    guard let command = parsed else { return }
    let serialized = command.serialized
    if let expected {
        check.expectEqual(serialized, expected, "\(label): serialized form")
    }
    let reparsed = check.expectNoThrow("\(label): re-parse") { try HelperCommand.parse(serialized) }
    guard let again = reparsed else { return }
    check.expectEqual(again, command, "\(label): round trip")
}

// MARK: - FanCurve.validate

check.expectNoThrow("silent curve validates") { try silentCurve().validate() }

expectCurveError("validate rejects 0 points", .tooFewPoints(0), [])
expectCurveError("validate rejects 1 point", .tooFewPoints(1), [CurvePoint(t: 50, p: 20)])
var thirteenPoints: [CurvePoint] = []
for index in 0..<13 { thirteenPoints.append(CurvePoint(t: Double(index) * 5, p: Double(index) * 5)) }
expectCurveError("validate rejects 13 points", .tooManyPoints(13), thirteenPoints)
expectCurveError("validate rejects non-increasing t", .notStrictlyIncreasing(index: 1),
                 [CurvePoint(t: 60, p: 10), CurvePoint(t: 50, p: 20)])
expectCurveError("validate rejects equal t", .notStrictlyIncreasing(index: 1),
                 [CurvePoint(t: 60, p: 10), CurvePoint(t: 60, p: 20)])
expectCurveError("validate rejects t below range", .temperatureOutOfRange(index: 0),
                 [CurvePoint(t: -1, p: 0), CurvePoint(t: 10, p: 10)])
expectCurveError("validate rejects t above range", .temperatureOutOfRange(index: 1),
                 [CurvePoint(t: 120, p: 0), CurvePoint(t: 131, p: 10)])
expectCurveError("validate rejects NaN t", .temperatureOutOfRange(index: 0),
                 [CurvePoint(t: .nan, p: 0), CurvePoint(t: 10, p: 10)])
expectCurveError("validate rejects p over 100", .percentOutOfRange(index: 1),
                 [CurvePoint(t: 50, p: 0), CurvePoint(t: 60, p: 101)])
expectCurveError("validate rejects p below 0", .percentOutOfRange(index: 0),
                 [CurvePoint(t: 50, p: -1), CurvePoint(t: 60, p: 10)])
expectCurveError("validate rejects decreasing p", .decreasingPercent(index: 1),
                 [CurvePoint(t: 50, p: 50), CurvePoint(t: 60, p: 10)])
var twelvePoints: [CurvePoint] = []
for index in 0..<12 { twelvePoints.append(CurvePoint(t: Double(index) * 5, p: Double(index) * 5)) }
check.expectNoThrow("validate accepts 12 points") { try FanCurve(points: twelvePoints).validate() }

// MARK: - FanCurve.percent(at:)

let silent = silentCurve()
check.expectClose(silent.percent(at: 40), 0, tolerance: 0.0001, "clamp below first point")
check.expectClose(silent.percent(at: 50), 0, tolerance: 0.0001, "first point exact")
check.expectClose(silent.percent(at: 60), 7.5, tolerance: 0.0001, "interpolate midpoint")
check.expectClose(silent.percent(at: 70), 15, tolerance: 0.0001, "interior vertex exact")
check.expectClose(silent.percent(at: 80), 35, tolerance: 0.0001, "interpolate second segment")
check.expectClose(silent.percent(at: 95), 100, tolerance: 0.0001, "last point exact")
check.expectClose(silent.percent(at: 120), 100, tolerance: 0.0001, "clamp above last point")

// MARK: - PresetLibrary.defaults

let defaults = PresetLibrary.defaults()
check.expectEqual(defaults.version, 1, "defaults version")
check.expectEqual(defaults.active, PresetLibrary.autoID, "defaults active is auto")
check.expectEqual(defaults.presets.count, 4, "defaults has 4 presets")
check.expectEqual(defaults.presets.map { $0.id }, ["silent", "balanced", "performance", "full"], "defaults ids")
check.expectEqual(defaults.presets.map { $0.name }, ["Silent", "Balanced", "Performance", "Full"], "defaults names")
let silentPreset = defaults.preset(id: "silent")
check.expect(silentPreset != nil, "silent preset exists")
check.expectEqual(silentPreset?.points ?? [], [
    CurvePoint(t: 50, p: 0),
    CurvePoint(t: 70, p: 15),
    CurvePoint(t: 85, p: 45),
    CurvePoint(t: 95, p: 100),
], "Silent points exactly as listed")
check.expectEqual(silentPreset.map { HelperCommand.curve(input: $0.input, points: $0.points).serialized } ?? "",
                  "CURVE max 50:0,70:15,85:45,95:100", "Silent input is max")
check.expectEqual(defaults.preset(id: "full")?.points ?? [], [
    CurvePoint(t: 30, p: 100), CurvePoint(t: 100, p: 100),
], "Full points exactly as listed")
for preset in defaults.presets {
    check.expectNoThrow("default preset \(preset.id) validates") { try preset.curve.validate() }
}
let maxInput = silentPreset!.input

// MARK: - PresetStore

let tmpRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("FreeFanCoreCheck-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
let storeURL = tmpRoot.appendingPathComponent("nested/presets.json")
let bakURL = URL(fileURLWithPath: storeURL.path + ".bak")

// Missing file -> defaults written.
let store = PresetStore(url: storeURL)
check.expect(!FileManager.default.fileExists(atPath: storeURL.path), "store file starts missing")
let loadedMissing = check.expectNoThrow("load() on missing file") { try store.load() }
check.expectEqual(loadedMissing ?? fallbackLibrary(), defaults, "missing file load returns defaults")
check.expect(FileManager.default.fileExists(atPath: storeURL.path), "missing file load writes defaults to disk")
check.expect(FileManager.default.fileExists(atPath: tmpRoot.appendingPathComponent("nested").path),
             "save creates the parent directory")

// Corrupt file -> moved to .bak, defaults restored.
let corruptText = "{ this is not json"
try? corruptText.data(using: .utf8)!.write(to: storeURL)
let loadedCorrupt = check.expectNoThrow("load() on corrupt file") { try store.load() }
check.expectEqual(loadedCorrupt ?? fallbackLibrary(), defaults, "corrupt file falls back to defaults")
check.expect(FileManager.default.fileExists(atPath: bakURL.path), "corrupt file moved to .bak")
check.expectEqual((try? String(contentsOf: bakURL, encoding: .utf8)) ?? "", corruptText, ".bak holds the corrupt bytes")

// save() then load() is equal, and the file is human readable with sorted keys.
let storeWrite = PresetStore(url: storeURL)
check.expectNoThrow("setActive writes defaults with active performance") { try storeWrite.setActive("performance") }
let reloadedWrite = check.expectNoThrow("reload after setActive") { try PresetStore(url: storeURL).load() }
check.expectEqual(reloadedWrite, storeWrite.library, "save then load equal")
let savedText = (try? String(contentsOf: storeURL, encoding: .utf8)) ?? ""
check.expect(savedText.contains("\n"), "saved file is pretty printed")
if let activeKey = savedText.range(of: "\"active\""),
   let presetsKey = savedText.range(of: "\"presets\""),
   let versionKey = savedText.range(of: "\"version\"") {
    check.expect(activeKey.lowerBound < presetsKey.lowerBound && presetsKey.lowerBound < versionKey.lowerBound,
                 "top-level keys are sorted")
} else {
    check.expect(false, "saved file contains version/active/presets keys")
}

// setActive persists.
let storeActive = PresetStore(url: storeURL)
check.expectNoThrow("setActive balanced") { try storeActive.setActive("balanced") }
let reloadedActive = check.expectNoThrow("reload after setActive balanced") { try PresetStore(url: storeURL).load() }
check.expectEqual(reloadedActive?.active ?? "", "balanced", "active persisted")

// upsert appends then replaces, both persisted.
let custom = Preset(id: "custom", name: "Custom", input: maxInput, points: [
    CurvePoint(t: 40, p: 10), CurvePoint(t: 80, p: 90),
])
check.expectNoThrow("upsert appends") { try storeActive.upsert(custom) }
let reloadedUpsert = check.expectNoThrow("reload after upsert") { try PresetStore(url: storeURL).load() }
check.expectEqual(reloadedUpsert?.preset(id: "custom"), custom, "upsert persisted")
check.expectEqual(reloadedUpsert?.presets.count ?? 0, 5, "upsert kept the defaults")
check.expectNoThrow("upsert replaces") { try storeActive.upsert(Preset(id: "custom", name: "Custom2", input: maxInput, points: [
    CurvePoint(t: 40, p: 10), CurvePoint(t: 80, p: 95),
])) }
let reloadedReplace = check.expectNoThrow("reload after replace") { try PresetStore(url: storeURL).load() }
check.expectEqual(reloadedReplace?.presets.count ?? 0, 5, "replace did not add a preset")
check.expectEqual(reloadedReplace?.preset(id: "custom")?.name ?? "", "Custom2", "replace updated the name")

check.expectNoThrow("remove custom") { try storeActive.remove(id: "custom") }
let reloadedRemove = check.expectNoThrow("reload after remove") { try PresetStore(url: storeURL).load() }
check.expectEqual(reloadedRemove?.preset(id: "custom"), nil, "remove persisted")
check.expectEqual(reloadedRemove?.presets.count ?? 0, 4, "remove dropped one preset")
check.expectNoThrow("remove active balanced") { try storeActive.remove(id: "balanced") }
let reloadedRemoveActive = check.expectNoThrow("reload after removing active") { try PresetStore(url: storeURL).load() }
check.expectEqual(reloadedRemoveActive?.active ?? "", PresetLibrary.autoID, "removing the active preset resets to auto")

// load() drops invalid presets and repairs a dangling active id.
let badJSON = """
{"version":1,"active":"broken","presets":[
{"id":"broken","name":"Broken","input":"max","points":[{"t":50,"p":0}]},
{"id":"good","name":"Good","input":"max","points":[{"t":30,"p":10},{"t":80,"p":90}]}
]}
"""
try? badJSON.data(using: .utf8)!.write(to: storeURL)
let repaired = check.expectNoThrow("load drops invalid presets") { try PresetStore(url: storeURL).load() }
check.expectEqual(repaired?.presets.count ?? -1, 1, "invalid preset dropped")
check.expectEqual(repaired?.preset(id: "broken"), nil, "broken preset removed")
check.expectEqual(repaired?.preset(id: "good")?.name ?? "", "Good", "valid preset kept")
check.expectEqual(repaired?.active ?? "", PresetLibrary.autoID, "dangling active repaired to auto")

try? FileManager.default.removeItem(at: tmpRoot)

// MARK: - HelperCommand round trips

expectRoundTrip("PING", "PING", serializedAs: "PING")
expectRoundTrip("STATUS", "STATUS", serializedAs: "STATUS")
expectRoundTrip("AUTO", "AUTO", serializedAs: "AUTO")
expectRoundTrip("CURVE max", "CURVE max 50:0,70:15,85:45,95:100",
                serializedAs: "CURVE max 50:0,70:15,85:45,95:100")
expectRoundTrip("CURVE cpu", "CURVE cpu 40:20,55:40,70:70,85:100",
                serializedAs: "CURVE cpu 40:20,55:40,70:70,85:100")
expectRoundTrip("CURVE gpu", "CURVE gpu 30:100,100:100",
                serializedAs: "CURVE gpu 30:100,100:100")
expectRoundTrip("CURVE decimals", "CURVE max 40:20.5,60.5:80.25",
                serializedAs: "CURVE max 40:20.50,60.50:80.25")
expectRoundTrip("CURVE lowercase verb", "curve max 30:0,90:100",
                serializedAs: "CURVE max 30:0,90:100")
expectRoundTrip("FIXED int", "FIXED 40", serializedAs: "FIXED 40")
expectRoundTrip("FIXED decimal", "FIXED 62.5", serializedAs: "FIXED 62.50")

// MARK: - HelperCommand rejections

expectProtoError("empty line", .emptyLine, "")
expectProtoError("whitespace line", .emptyLine, "   ")
expectProtoError("too long", .tooLong(max: HelperPaths.maxLineBytes), String(repeating: "PING", count: 200))
expectProtoError("unknown verb", .unknownCommand("FOO"), "FOO")
expectProtoError("unknown verb with args", .unknownCommand("PINGX"), "PINGX 1 2")
expectProtoError("PING extra args", .malformed("PING takes no arguments"), "PING now")
expectProtoError("STATUS extra args", .malformed("STATUS takes no arguments"), "STATUS now")
expectProtoError("AUTO extra args", .malformed("AUTO takes no arguments"), "AUTO now")
expectProtoError("CURVE no args", .malformed("CURVE needs <input> <points>"), "CURVE")
expectProtoError("CURVE one arg", .malformed("CURVE needs <input> <points>"), "CURVE max")
expectProtoError("CURVE unknown input", .badValue("unknown curve input bogus"), "CURVE bogus 1:1,2:2")
expectProtoError("CURVE one point", .badValue("curve needs at least 2 points (has 1)"), "CURVE max 50:0")
expectProtoError("CURVE missing colon", .malformed("point is not t:p: 50"), "CURVE max 50,60:10")
expectProtoError("CURVE non-increasing t", .badValue(CurveError.notStrictlyIncreasing(index: 1).description),
                 "CURVE max 60:10,50:20")
expectProtoError("CURVE decreasing p", .badValue(CurveError.decreasingPercent(index: 1).description),
                 "CURVE max 50:50,60:10")
expectProtoError("CURVE p out of range", .badValue(CurveError.percentOutOfRange(index: 1).description),
                 "CURVE max 50:0,60:200")
expectProtoError("CURVE t out of range", .badValue(CurveError.temperatureOutOfRange(index: 1).description),
                 "CURVE max 120:0,140:10")
expectProtoError("CURVE non-finite temperature", .badValue("non-finite temperature: inf"), "CURVE max inf:0,10:10")
expectProtoError("CURVE non-finite percent", .badValue("non-finite percent: nan"), "CURVE max 50:0,60:nan")
expectProtoError("CURVE bad number", .badValue("non-finite percent: abc"), "CURVE max 50:0,60:abc")
expectProtoError("CURVE 13 points", .badValue(CurveError.tooManyPoints(13).description),
                 "CURVE max 0:0,5:5,10:10,15:15,20:20,25:25,30:30,35:35,40:40,45:45,50:50,55:55,60:60")
expectProtoError("FIXED no arg", .malformed("FIXED needs <percent>"), "FIXED")
expectProtoError("FIXED too many args", .malformed("FIXED needs <percent>"), "FIXED 40 50")
expectProtoError("FIXED over 100", .badValue("fixed percent outside 0...100: 101"), "FIXED 101")
expectProtoError("FIXED negative", .badValue("fixed percent outside 0...100: -1"), "FIXED -1")
expectProtoError("FIXED non-numeric", .badValue("fixed percent is not a finite number: abc"), "FIXED abc")
expectProtoError("FIXED non-finite", .badValue("fixed percent is not a finite number: nan"), "FIXED nan")

// MARK: - HelperStatus serialize / parse

let statusCurve = HelperStatus(mode: .curve, inputTemperature: 62.5, targetRPM: [3200, 4100.5], writes: 7, error: nil)
check.expectEqual(statusCurve.serialized, "OK mode=curve temp=62.5 rpm=3200.0,4100.5 writes=7",
                  "status serialized without error")
check.expectEqual(HelperStatus.parse(statusCurve.serialized), statusCurve, "status round trip without error")

let statusError = HelperStatus(mode: .monitor, inputTemperature: nil, targetRPM: [], writes: 0, error: "smc:0x82")
check.expectEqual(statusError.serialized, "OK mode=monitor temp=- rpm=- writes=0 err=smc:0x82",
                  "status serialized with error")
check.expectEqual(HelperStatus.parse(statusError.serialized), statusError, "status round trip with error")

let statusAuto = HelperStatus(mode: .auto)
check.expectEqual(statusAuto.serialized, "OK mode=auto temp=- rpm=- writes=0", "status auto serialized")
check.expectEqual(HelperStatus.parse(statusAuto.serialized), statusAuto, "status auto round trip")

let statusPanic = HelperStatus(mode: .panic, inputTemperature: 96, targetRPM: [7826], writes: 12)
check.expectEqual(HelperStatus.parse(statusPanic.serialized), statusPanic, "status panic round trip")
let statusFixed = HelperStatus(mode: .fixed, inputTemperature: 50, targetRPM: [5000, 5000], writes: 3)
check.expectEqual(HelperStatus.parse(statusFixed.serialized), statusFixed, "status fixed round trip")

check.expect(HelperStatus.parse("") == nil, "status parse rejects empty")
check.expect(HelperStatus.parse("garbage") == nil, "status parse rejects junk")
check.expect(HelperStatus.parse("OK temp=50 rpm=- writes=0") == nil, "status parse rejects missing mode")
check.expect(HelperStatus.parse("OK mode=bogus temp=- rpm=- writes=0") == nil, "status parse rejects unknown mode")
check.expect(HelperStatus.parse("OK mode=curve temp=50 rpm=abc writes=0") == nil, "status parse rejects non-numeric rpm")
check.expect(HelperStatus.parse("OK mode=curve temp=abc rpm=- writes=0") == nil, "status parse rejects non-numeric temp")
check.expect(HelperStatus.parse("OK mode=curve temp=50 rpm=- writes=x") == nil, "status parse rejects non-numeric writes")
check.expect(HelperStatus.parse("OK mode=curve temp=50 rpm=- writes=0 extra") == nil, "status parse rejects trailing junk")
check.expect(HelperStatus.parse("NO mode=curve temp=50 rpm=- writes=0") == nil, "status parse rejects missing OK")

exit(check.summary())
