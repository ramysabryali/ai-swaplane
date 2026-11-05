// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swaplane",
    platforms: [.macOS(.v14)],
    products: [
        // Executable names must differ by more than case (case-insensitive filesystem).
        .executable(name: "SwaplaneApp", targets: ["SwaplaneApp"]),
        .executable(name: "swaplane", targets: ["swaplane-cli"]),
    ],
    targets: [
        .target(name: "SwaplaneCore"),
        .target(name: "Vault", dependencies: ["SwaplaneCore"]),
        .target(name: "Adapters", dependencies: ["SwaplaneCore"]),
        .target(name: "SwitchEngine", dependencies: ["SwaplaneCore", "Vault", "Adapters"]),
        .target(name: "SwaplaneUI", dependencies: ["SwaplaneCore", "Vault", "Adapters", "SwitchEngine"]),
        .executableTarget(name: "SwaplaneApp", dependencies: ["SwaplaneUI"]),
        .executableTarget(name: "swaplane-cli", dependencies: ["SwaplaneCore"]),
        .testTarget(
            name: "SwaplaneTests",
            dependencies: ["SwaplaneCore", "Vault", "Adapters", "SwitchEngine"]
        ),
    ]
)
