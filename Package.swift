// swift-tools-version:6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "OpenFan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenFan", targets: ["OpenFan"]),
        .executable(name: "OpenFanHelper", targets: ["OpenFanHelper"]),
    ],
    targets: [
        .target(name: "OpenFanSMC", swiftSettings: v5),
        .target(name: "OpenFanCore", dependencies: ["OpenFanSMC"], swiftSettings: v5),
        .target(name: "OpenFanControl", dependencies: ["OpenFanSMC", "OpenFanCore"], swiftSettings: v5),
        .target(name: "CheckKit", swiftSettings: v5),
        .executableTarget(name: "OpenFanHelper", dependencies: ["OpenFanSMC", "OpenFanCore", "OpenFanControl"], swiftSettings: v5),
        .target(name: "OpenFanUI", dependencies: ["OpenFanSMC", "OpenFanCore"], swiftSettings: v5),
        .executableTarget(name: "OpenFan", dependencies: ["OpenFanUI", "OpenFanSMC", "OpenFanCore", "OpenFanControl"], swiftSettings: v5),
        .executableTarget(name: "OpenFanPreview", dependencies: ["OpenFanUI", "OpenFanSMC", "OpenFanCore"], swiftSettings: v5),
        .executableTarget(name: "OpenFanProbe", dependencies: ["OpenFanSMC", "OpenFanCore"], swiftSettings: v5),
        .executableTarget(name: "SMCCheck", dependencies: ["OpenFanSMC", "CheckKit"], swiftSettings: v5),
        .executableTarget(name: "CoreCheck", dependencies: ["OpenFanCore", "CheckKit"], swiftSettings: v5),
        .executableTarget(name: "ControlCheck", dependencies: ["OpenFanControl", "CheckKit"], swiftSettings: v5),
    ]
)
