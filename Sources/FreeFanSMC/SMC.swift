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
private let kSMCSelectorWriteBytes: UInt8 = 6

// MARK: - SMC

/// One AppleSMC user-client connection.
///
/// Reads work from an unprivileged process; writes return kIOReturnNotPrivileged (0xe00002c1) unless the
/// process runs as root. Instances are NOT thread-safe: confine each instance to one queue.
public final class SMC {
    private var connection: io_connect_t = 0

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

    // TODO(node-sensor-read): implement the public surface below. Requirements:
    // - cache keyInfo per key in a dictionary so a read costs one dictionary lookup plus the kernel call;
    // - memoize absent keys in a Set so a missing key is probed once, never re-probed;
    // - "flt " is 4-byte little-endian IEEE754; "ui8 " is one byte; ui16/ui32 are big-endian;
    // - readUInt8/readFloat throw unexpectedSize/unexpectedType when the key's declared size or type
    //   does not match;
    // - writeFloat/writeUInt8 use selector 6 and must set dataSize + dataType from keyInfo on the input;
    //   a non-zero result byte or a kern failure is a writeFailed; 0xe00002c1 means notPrivileged;
    // - rawRead returns the declared type string and the leading dataSize bytes.
    // Public signatures are frozen: do not change them.

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        throw SMCError.keyNotFound(key)
    }

    public func keyExists(_ key: String) -> Bool {
        false
    }

    public func readFloat(_ key: String) throws -> Float {
        throw SMCError.keyNotFound(key)
    }

    public func readUInt8(_ key: String) throws -> UInt8 {
        throw SMCError.keyNotFound(key)
    }

    public func readUInt32(_ key: String) throws -> UInt32 {
        throw SMCError.keyNotFound(key)
    }

    public func writeFloat(_ key: String, _ value: Float) throws {
        throw SMCError.notPrivileged
    }

    public func writeUInt8(_ key: String, _ value: UInt8) throws {
        throw SMCError.notPrivileged
    }

    public func rawRead(_ key: String) throws -> (type: String, bytes: [UInt8]) {
        throw SMCError.keyNotFound(key)
    }
}
