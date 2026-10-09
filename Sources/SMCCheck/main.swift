import Foundation
import CheckKit
import FreeFanSMC

// Hardware check for the FreeFanSMC access layer. Every check prints one line; the process exits
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

for key in SensorCatalog.cpuKeys {
    let first = smc.keyExists(key)
    let second = smc.keyExists(key)
    report(first && second, "CPU key \(key) resolves (exists=\(first), again=\(second))")
}

for key in SensorCatalog.gpuKeys {
    let first = smc.keyExists(key)
    let second = smc.keyExists(key)
    report(first && second, "GPU key \(key) resolves (exists=\(first), again=\(second))")
}

// Tg1g is absent on this machine (Mac17,9); the catalog still lists it so discovery can prove it.
let tg1g = smc.keyExists("Tg1g")
let tg1gAgain = smc.keyExists("Tg1g")
report(!tg1g && !tg1gAgain, "absent GPU key Tg1g resolves false (exists=\(tg1g), again=\(tg1gAgain))")

// MARK: - 2. Fan count and per-fan limits

let fanCount = (try? smc.readUInt8("FNum")).map(Int.init)
report(fanCount == 2, "FNum reads 2 (got \(fanCount.map(String.init) ?? "read failed"))")

var fans: [FanInfo] = []
for index in 0..<(fanCount ?? 0) {
    let minRPM = try? smc.readFloat("F\(index)Mn")
    let maxRPM = try? smc.readFloat("F\(index)Mx")
    let ok = (minRPM ?? 0) > 0 && (maxRPM ?? 0) > (minRPM ?? 0)
    report(ok, "fan \(index) has Mn > 0 and Mn < Mx (Mn=\(describe(minRPM)), Mx=\(describe(maxRPM)))")
    if ok, let minRPM, let maxRPM {
        fans.append(FanInfo(index: index, minRPM: minRPM, maxRPM: maxRPM))
    }
}

// MARK: - 3. Fan 0 actual RPM

let fan0Max = try? smc.readFloat("F0Mx")
let fan0Actual = try? smc.readFloat("F0Ac")
let actualOK: Bool
if let fan0Actual, let fan0Max {
    actualOK = fan0Actual.isFinite && fan0Actual >= 0 && fan0Actual <= fan0Max + 500
} else {
    actualOK = false
}
report(actualOK, "F0Ac finite within 0...F0Mx+500 (Ac=\(describe(fan0Actual)), Mx=\(describe(fan0Max)))")

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

// MARK: - 5. Unprivileged write is refused

if geteuid() != 0 {
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
