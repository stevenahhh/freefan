import CryptoKit
import Foundation

/// A `MAJOR.MINOR` version, as in `CFBundleShortVersionString` and the release tags (`v1.4`).
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// Accepts `1.4` and `v1.4`; anything else (a patch number, a suffix, a negative part) is nil.
    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        self.init(major: major, minor: minor)
    }

    public var description: String { "\(major).\(minor)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

/// The newest GitHub release, reduced to what an update needs: its version and the URLs of the signed app archive and
/// its signature.
public struct AvailableUpdate: Equatable, Sendable {
    public static let archiveName = "OpenFan.zip"
    public static let signatureName = "OpenFan.zip.sig"

    public let version: AppVersion
    public let archiveURL: URL
    public let signatureURL: URL
    public let pageURL: URL?

    public init(version: AppVersion, archiveURL: URL, signatureURL: URL, pageURL: URL?) {
        self.version = version
        self.archiveURL = archiveURL
        self.signatureURL = signatureURL
        self.pageURL = pageURL
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }

        let tag_name: String
        let draft: Bool?
        let prerelease: Bool?
        let html_url: String?
        let assets: [Asset]
    }

    /// Parses `GET /repos/{owner}/{repo}/releases/latest`. Nil unless the release is newer than `current`, is neither a
    /// draft nor a prerelease, has a `MAJOR.MINOR` tag and carries both assets over HTTPS on github.com.
    public static func parse(_ data: Data, newerThan current: AppVersion) -> AvailableUpdate? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true,
              let version = AppVersion(release.tag_name), version > current,
              let archive = asset(archiveName, in: release), let signature = asset(signatureName, in: release)
        else { return nil }
        return AvailableUpdate(version: version, archiveURL: archive, signatureURL: signature,
                               pageURL: release.html_url.flatMap(URL.init(string:)))
    }

    private static func asset(_ name: String, in release: Release) -> URL? {
        guard let text = release.assets.first(where: { $0.name == name })?.browser_download_url,
              let url = URL(string: text), url.scheme == "https",
              let host = url.host, host == "github.com" || host.hasSuffix(".githubusercontent.com")
        else { return nil }
        return url
    }
}

/// The archive's Ed25519 signature. The private key exists only as a repository secret used by the release workflow;
/// the app carries the public key, so an archive that was not produced by that workflow is never installed.
public enum UpdateSignature {
    public static let publicKey = "8RX0kPTXUXhUiO2BPa+NFJu2QqPE6Tvci/hH8CTOufc="

    /// `signature` is the `.sig` asset: the signature in base64, surrounding whitespace allowed.
    public static func isValid(archive: Data, signature: Data, publicKey: String = UpdateSignature.publicKey) -> Bool {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: text), let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return key.isValidSignature(raw, for: archive)
    }
}

/// When the next automatic check is due: once a day, counted from the last check that got an answer.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock set back must not postpone the check for as long as it was moved.
        return now.timeIntervalSince(lastCheck) >= interval || now < lastCheck
    }
}
