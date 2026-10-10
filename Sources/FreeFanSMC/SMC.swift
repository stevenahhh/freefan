import Foundation
import IOKit

// MARK: - Errors

public enum SMCError: Error, CustomStringConvertible, Equatable {
    case serviceNotFound
    case openFailed(kern_return_t)
    case keyNotFound(String)
    case callFailed(key: String, kern: kern_return_t, result: UInt8)
    case writeFailed(key: String, kern: kern_return_t, result: UInt8)
    case unexpectedSize(key: String, size: UInt32)
    case unexpectedType(key: String, type: UInt32)
    case notPrivileged

    public var description: String {
        switch self {
        case .serviceNotFound:
            return "AppleSMC service not found"
        case .openFailed(let kern):
            return String(format: "IOServiceOpen failed (0x%08x)", kern)
        case .keyNotFound(let key):
            return "SMC key not found: \(key)"
        case .callFailed(let key, let kern, let result):
            return String(format: "SMC call failed for %@ (kern 0x%08x, result 0x%02x)", key, kern, result)
        case .writeFailed(let key, let kern, let result):
            return String(format: "SMC write failed for %@ (kern 0x%08x, result 0x%02x)", key, kern, result)
        case .unexpectedSize(let key, let size):
            return "unexpected SMC data size for \(key): \(size)"
        case .unexpectedType(let key, let type):
            return "unexpected SMC data type for \(key): \(fourCCString(type))"
        case .notPrivileged:
            return "SMC write requires root"
        }
    }
}

// MARK: - Public types

public struct SMCKeyInfo: Equatable, Sendable {
    public let dataSize: UInt32
    public let dataType: UInt32
    public let attributes: UInt8

    public init(dataSize: UInt32, dataType: UInt32, attributes: UInt8) {
        self.dataSize = dataSize
        self.dataType = dataType
        self.attributes = attributes
    }

    /// True when the keyInfo attribute byte carries the write bit (0x40).
    public var isWritable: Bool { attributes & 0x40 != 0 }
}

/// Four-character-code helpers. Keys are big-endian ASCII, e.g. "F0md".
public func fourCC(_ key: String) -> UInt32 {
    var value: UInt32 = 0
    for byte in key.utf8.prefix(4) { value = (value << 8) | UInt32(byte) }
    return value
}

public func fourCCString(_ value: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

// MARK: - AppleSMC wire format

// Layout verified on Mac17,9 / macOS 27.0.1: MemoryLayout size is 80 bytes, matching the kernel struct
// used by Stats, fand and fanctl. Field order and widths are part of the ABI: do not reorder.
private struct SMCVersionParam {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimitParam {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpu: UInt32 = 0
    var gpu: UInt32 = 0
    var memory: UInt32 = 0
}

private struct SMCKeyInfoParam {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCBytes32 = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersionParam()
    var powerLimit = SMCPowerLimitParam()
    var keyInfo = SMCKeyInfoParam()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

// data8 selectors
private let kSMCSelectorReadKeyInfo: UInt8 = 9
private let kSMCSelectorReadBytes: UInt8 = 5
private let kSMCSelectorReadIndex: UInt8 = 8
private let kSMCSelectorWriteBytes: UInt8 = 6

// Four-character-type codes as they arrive in keyInfo.dataType.
private let kSMCTypeFloat: UInt32 = fourCC("flt ")
private let kSMCTypeUInt8: UInt32 = fourCC("ui8 ")
private let kSMCTypeUInt32: UInt32 = fourCC("ui32")

// 0xe00002c1 = kIOReturnNotPrivileged. Spelled out so the mapping does not depend on an IOKit symbol.
private let kIOMessageNotPrivileged = kern_return_t(bitPattern: 0xe00002c1)

// The wire struct carries exactly 32 data bytes.
private let kSMCBytesCapacity = 32

// MARK: - SMC

/// One AppleSMC user-client connection.
///
/// Reads work from an unprivileged process; writes return kIOReturnNotPrivileged (0xe00002c1) unless the
/// process runs as root. Instances are NOT thread-safe: confine each instance to one queue.
public final class SMC {
    private var connection: io_connect_t = 0

    /// One keyInfo call per key, cached so a read costs a dictionary lookup plus the kernel call.
    private var keyInfoCache: [String: SMCKeyInfo] = [:]
    /// Keys already proven absent. A missing key read costs about 50x a present one, so never re-probe.
    private var absentKeys: Set<String> = []

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        var conn: io_connect_t = 0
        let kern = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        guard kern == KERN_SUCCESS, conn != 0 else { throw SMCError.openFailed(kern) }
        connection = conn
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Raw selector-2 struct call. Private: external code uses the typed methods below.
    private func rawCall(_ input: inout SMCKeyData) throws -> SMCKeyData {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let kern = IOConnectCallStructMethod(
            connection, 2,
            &input, MemoryLayout<SMCKeyData>.stride,
            &output, &outputSize
        )
        let key = fourCCString(input.key)
        guard kern == KERN_SUCCESS else {
            throw SMCError.callFailed(key: key, kern: kern, result: output.result)
        }
        // Success requires BOTH kern_return == 0 and the result byte == 0.
        guard output.result == 0 else {
            throw SMCError.callFailed(key: key, kern: kern, result: output.result)
        }
        return output
    }

    // MARK: Public surface

    /// Declared size, type and attribute byte for a key. The first call for a key hits the SMC; later
    /// calls are served from the cache. A key the SMC rejects is remembered as absent and reports
    /// keyNotFound on every later call without touching the kernel again.
    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        if let cached = keyInfoCache[key] { return cached }
        if absentKeys.contains(key) { throw SMCError.keyNotFound(key) }

        var input = SMCKeyData()
        input.key = fourCC(key)
        input.data8 = kSMCSelectorReadKeyInfo

        let output: SMCKeyData
        do {
            output = try rawCall(&input)
        } catch SMCError.callFailed {
            // A non-zero result byte means this key does not exist on this machine.
            absentKeys.insert(key)
            throw SMCError.keyNotFound(key)
        }

        let info = SMCKeyInfo(
            dataSize: output.keyInfo.dataSize,
            dataType: output.keyInfo.dataType,
            attributes: output.keyInfo.dataAttributes
        )
        // A key that resolves but declares zero bytes is not readable; treat it as absent.
        guard info.dataSize > 0 else {
            absentKeys.insert(key)
            throw SMCError.keyNotFound(key)
        }
        keyInfoCache[key] = info
        return info
    }

    public func keyExists(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    /// How many keys this SMC lists (`#KEY`).
    public func keyCount() throws -> Int {
        Int(try readUInt32("#KEY"))
    }

    /// The name of the key at `index` in the SMC's own listing, for finding the sensors of a machine that is not
    /// catalogued yet.
    public func key(at index: Int) throws -> String {
        var input = SMCKeyData()
        input.data8 = kSMCSelectorReadIndex
        input.data32 = UInt32(index)
        return fourCCString(try rawCall(&input).key)
    }

    public func readFloat(_ key: String) throws -> Float {
        let info = try keyInfo(key)
        guard info.dataType == kSMCTypeFloat else { throw SMCError.unexpectedType(key: key, type: info.dataType) }
        guard info.dataSize == 4 else { throw SMCError.unexpectedSize(key: key, size: info.dataSize) }
        let bytes = try readBytes(key, info: info)
        // "flt " is 4-byte little-endian IEEE754.
        let bits = UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
        return Float(bitPattern: bits)
    }

    public func readUInt8(_ key: String) throws -> UInt8 {
        let info = try keyInfo(key)
        guard info.dataType == kSMCTypeUInt8 else { throw SMCError.unexpectedType(key: key, type: info.dataType) }
        guard info.dataSize == 1 else { throw SMCError.unexpectedSize(key: key, size: info.dataSize) }
        let bytes = try readBytes(key, info: info)
        return bytes[0]
    }

    public func readUInt32(_ key: String) throws -> UInt32 {
        let info = try keyInfo(key)
        guard info.dataType == kSMCTypeUInt32 else { throw SMCError.unexpectedType(key: key, type: info.dataType) }
        guard info.dataSize == 4 else { throw SMCError.unexpectedSize(key: key, size: info.dataSize) }
        let bytes = try readBytes(key, info: info)
        // ui32 is big-endian on the SMC wire.
        return (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }

    public func writeFloat(_ key: String, _ value: Float) throws {
        let info = try keyInfo(key)
        guard info.dataType == kSMCTypeFloat else { throw SMCError.unexpectedType(key: key, type: info.dataType) }
        guard info.dataSize == 4 else { throw SMCError.unexpectedSize(key: key, size: info.dataSize) }
        let bits = value.bitPattern
        let bytes: [UInt8] = [
            UInt8(bits & 0xff),
            UInt8((bits >> 8) & 0xff),
            UInt8((bits >> 16) & 0xff),
            UInt8((bits >> 24) & 0xff),
        ]
        try writeBytes(key, info: info, bytes: bytes)
    }

    public func writeUInt8(_ key: String, _ value: UInt8) throws {
        let info = try keyInfo(key)
        guard info.dataType == kSMCTypeUInt8 else { throw SMCError.unexpectedType(key: key, type: info.dataType) }
        guard info.dataSize == 1 else { throw SMCError.unexpectedSize(key: key, size: info.dataSize) }
        try writeBytes(key, info: info, bytes: [value])
    }

    public func rawRead(_ key: String) throws -> (type: String, bytes: [UInt8]) {
        let info = try keyInfo(key)
        let bytes = try readBytes(key, info: info)
        return (fourCCString(info.dataType), bytes)
    }

    // MARK: Internals

    /// Selector-5 read of exactly `info.dataSize` bytes for a key whose keyInfo is already known.
    private func readBytes(_ key: String, info: SMCKeyInfo) throws -> [UInt8] {
        var input = SMCKeyData()
        input.key = fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.keyInfo.dataType = info.dataType
        input.data8 = kSMCSelectorReadBytes

        let output = try rawCall(&input)
        let count = min(Int(info.dataSize), kSMCBytesCapacity)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(count)) }
    }

    /// Selector-6 write. dataSize and dataType come from keyInfo; the payload is little-endian already.
    private func writeBytes(_ key: String, info: SMCKeyInfo, bytes: [UInt8]) throws {
        var input = SMCKeyData()
        input.key = fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.keyInfo.dataType = info.dataType
        input.data8 = kSMCSelectorWriteBytes
        withUnsafeMutableBytes(of: &input.bytes) { raw in
            for (index, byte) in bytes.prefix(kSMCBytesCapacity).enumerated() { raw[index] = byte }
        }

        do {
            _ = try rawCall(&input)
        } catch let error as SMCError {
            guard case let .callFailed(failedKey, kern, result) = error else { throw error }
            if kern == kIOMessageNotPrivileged { throw SMCError.notPrivileged }
            throw SMCError.writeFailed(key: failedKey, kern: kern, result: result)
        }
    }
}
