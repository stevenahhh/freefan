// Signs an update archive with the Ed25519 key in OPENFAN_UPDATE_SIGNING_KEY (the raw 32-byte key, base64) and prints
// the signature in base64. The release workflow runs it; the app checks the result against UpdateSignature.publicKey.
//
//   OPENFAN_UPDATE_SIGNING_KEY=... swift scripts/sign-update.swift build/OpenFan.zip > build/OpenFan.zip.sig
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sign-update: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: sign-update.swift <archive>") }
guard let encoded = ProcessInfo.processInfo.environment["OPENFAN_UPDATE_SIGNING_KEY"],
      let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
else { fail("OPENFAN_UPDATE_SIGNING_KEY is missing or not a base64 Ed25519 key") }
guard let archive = FileManager.default.contents(atPath: CommandLine.arguments[1]) else {
    fail("cannot read \(CommandLine.arguments[1])")
}
guard let signature = try? key.signature(for: archive) else { fail("signing failed") }
guard key.publicKey.isValidSignature(signature, for: archive) else { fail("the signature does not verify") }
print(signature.base64EncodedString())
FileHandle.standardError.write(Data("sign-update: public key \(key.publicKey.rawRepresentation.base64EncodedString())\n".utf8))
