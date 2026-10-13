import Foundation
import CheckKit
import OpenFanSMC

// Hardware check for the OpenFanSMC access layer. Every check prints one line; the process exits
// non-zero when any assertion fails. Requires a real AppleSMC on this machine.

let check = Checker("SMCCheck")

func report(_ ok: Bool, _ label: String) {
    print("[SMCCheck] \(ok ? "OK  " : "FAIL") \(label)")
    check.expect(ok, label)
}

func describe(_ value: Float?) -> String {
    guard let value else { return "nil" }
    return String(format: "%.1f", value)
}

// MARK: - Open the service

let smc: SMC
do {
    smc = try SMC()
    report(true, "AppleSMC service opened")
} catch {
    report(false, "AppleSMC service opened (\(error))")
    exit(check.summary())
}

// MARK: - 1. Key discovery and the absent-key path

// A smaller chip of a generation lacks some of its keys, so each group needs at least one, and every answer is stable.
for (group, keys) in [("CPU", SensorCatalog.cpuKeys), ("GPU", SensorCatalog.gpuKeys)] {
    var present = 0
    var stable = true
    for key in keys {
        let first = smc.keyExists(key)
        if first != smc.keyExists(key) { stable = false }
        if first { present += 1 }
    }
    report(present > 0 && stable, "\(group) keys: \(present) of \(keys.count) present, answers stable=\(stable)")
}

let absent = smc.keyExists("Tzz9")
let absentAgain = smc.keyExists("Tzz9")
report(!absent && !absentAgain, "a key no Mac has resolves false twice (exists=\(absent), again=\(absentAgain))")

// MARK: - 2. Fan count and per-fan limits

let fanCount = (try? smc.readUInt8("FNum")).map(Int.init)
report(fanCount != nil, "FNum reads (got \(fanCount.map(String.init) ?? "read failed"); 0 on a Mac without fans)")

var fans: [FanInfo] = []
for index in 0..<(fanCount ?? 0) {
    let minRPM = try? smc.readFloat("F\(index)Mn")
    let maxRPM = try? smc.readFloat("F\(index)Mx")
    let ok = (minRPM ?? 0) > 0 && (maxRPM ?? 0) > (minRPM ?? 0)
    report(ok, "fan \(index) has Mn > 0 and Mn < Mx (Mn=\(describe(minRPM)), Mx=\(describe(maxRPM)))")
    let modeKeys = ["F\(index)md", "F\(index)Md"].filter { smc.keyExists($0) }
    report(modeKeys.count == 1, "fan \(index) has exactly one mode key (found \(modeKeys))")
    if ok, let minRPM, let maxRPM {
        fans.append(FanInfo(index: index, minRPM: minRPM, maxRPM: maxRPM))
    }
}

// MARK: - 3. Fan 0 actual RPM

let hasFans = (fanCount ?? 0) > 0
if hasFans {
    let fan0Max = try? smc.readFloat("F0Mx")
    let fan0Actual = try? smc.readFloat("F0Ac")
    let actualOK: Bool
    if let fan0Actual, let fan0Max {
        actualOK = fan0Actual.isFinite && fan0Actual >= 0 && fan0Actual <= fan0Max + 500
    } else {
        actualOK = false
    }
    report(actualOK, "F0Ac finite within 0...F0Mx+500 (Ac=\(describe(fan0Actual)), Mx=\(describe(fan0Max)))")
} else {
    print("[SMCCheck] SKIP no fans: F0Ac and the write refusal are not checked")
}

// MARK: - 4. Telemetry discovery and a live reading

var telemetry: Telemetry?
do {
    telemetry = try Telemetry(smc: smc)
    report(true, "Telemetry.init does not throw (discovered \(telemetry?.fans.count ?? 0) fans)")
} catch {
    report(false, "Telemetry.init does not throw (\(error))")
}

if let telemetry {
    let reading = telemetry.read()
    let cpuOK = reading.cpu.map { $0.isFinite && $0 >= 0 && $0 <= 130 } ?? false
    let gpuOK = reading.gpu.map { $0.isFinite && $0 >= 0 && $0 <= 130 } ?? false
    report(cpuOK, "Telemetry.read CPU in 0...130 (cpu=\(describe(reading.cpu)))")
    report(gpuOK, "Telemetry.read GPU in 0...130 (gpu=\(describe(reading.gpu)))")
}

// MARK: - 4b. Battery sensors (a desktop has none)

let batteryDirect = SensorCatalog.batteryKeys.compactMap { try? smc.readFloat($0) }
let presentBattery = SensorCatalog.batteryKeys.filter { smc.keyExists($0) }
report(batteryDirect.count == presentBattery.count,
       "every battery key present reads (\(batteryDirect.count) of \(presentBattery.count) present)")
if presentBattery.isEmpty {
    print("[SMCCheck] SKIP no battery sensors (a desktop Mac)")
    report(telemetry?.hasBattery == false, "Telemetry reports no battery")
} else if let telemetry {
    let reading = telemetry.read()
    let expected = SensorCatalog.batteryMean(batteryDirect)
    var matches = false
    if let battery = reading.battery, let expected { matches = abs(battery - expected) < 1.0 }
    report(matches, "Telemetry.read battery is the mean of the direct sensor reads (battery=\(describe(reading.battery)), expected=\(describe(expected)))")
    report(reading.input(.battery) == reading.battery, "SensorReading.input(.battery) returns the battery mean")
}
report(SensorCatalog.batteryMean([30, 32]) == 31, "battery mean of 30 and 32 is 31")
report(SensorCatalog.batteryMean([30, .nan, 0, -4, 200, 32]) == 31, "battery mean ignores NaN, zero, negative and out-of-range sensors")
report(SensorCatalog.batteryMean([]) == nil, "battery mean of no sensors is nil")
report(SensorCatalog.batteryMean([0, .nan, .infinity]) == nil, "battery mean of only invalid sensors is nil")

// MARK: - 5. Unprivileged write is refused

if !hasFans {
    print("[SMCCheck] SKIP no fans to write to")
} else if geteuid() != 0 {
    var notPrivileged = false
    do {
        try smc.writeFloat("F0Tg", 4000)
    } catch SMCError.notPrivileged {
        notPrivileged = true
    } catch {
        print("[SMCCheck]     unexpected error: \(error)")
    }
    report(notPrivileged, "unprivileged writeFloat(F0Tg, 4000) throws notPrivileged")
} else {
    print("[SMCCheck] SKIP running as root; notPrivileged write assertion skipped")
}

exit(check.summary())
