// swift-tools-version:6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "FreeFan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FreeFan", targets: ["FreeFan"]),
        .executable(name: "FreeFanHelper", targets: ["FreeFanHelper"]),
    ],
    targets: [
        .target(name: "FreeFanSMC", swiftSettings: v5),
        .target(name: "FreeFanCore", dependencies: ["FreeFanSMC"], swiftSettings: v5),
        .target(name: "FreeFanControl", dependencies: ["FreeFanSMC", "FreeFanCore"], swiftSettings: v5),
        .target(name: "CheckKit", swiftSettings: v5),
        .executableTarget(name: "FreeFanHelper", dependencies: ["FreeFanSMC", "FreeFanCore", "FreeFanControl"], swiftSettings: v5),
        .target(name: "FreeFanUI", dependencies: ["FreeFanSMC", "FreeFanCore"], swiftSettings: v5),
        .executableTarget(name: "FreeFan", dependencies: ["FreeFanUI", "FreeFanSMC", "FreeFanCore", "FreeFanControl"], swiftSettings: v5),
        .executableTarget(name: "FreeFanPreview", dependencies: ["FreeFanUI", "FreeFanSMC", "FreeFanCore"], swiftSettings: v5),
        .executableTarget(name: "FreeFanProbe", dependencies: ["FreeFanSMC", "FreeFanCore"], swiftSettings: v5),
        .executableTarget(name: "SMCCheck", dependencies: ["FreeFanSMC", "CheckKit"], swiftSettings: v5),
        .executableTarget(name: "CoreCheck", dependencies: ["FreeFanCore", "CheckKit"], swiftSettings: v5),
        .executableTarget(name: "ControlCheck", dependencies: ["FreeFanControl", "CheckKit"], swiftSettings: v5),
    ]
)
