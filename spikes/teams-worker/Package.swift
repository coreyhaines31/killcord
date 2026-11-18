// swift-tools-version: 6.0
import PackageDescription

// Unit 0 spike for Kill Cord Teams (docs/product/teams-spec.md). Not part of the app or the shipped
// KillCordCore: it only proves the worker design builds on Linux and behaves. Fake keys only.
let package = Package(
    name: "TeamsWorkerSpike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/KillCordCore"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0")
    ],
    targets: [
        .target(name: "TeamsWorkerSpike", dependencies: [
            .product(name: "KillCordCore", package: "KillCordCore"),
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "PostgresNIO", package: "postgres-nio")
        ]),
        .executableTarget(name: "killcord-worker-spike", dependencies: ["TeamsWorkerSpike"]),
        .testTarget(name: "TeamsWorkerSpikeTests", dependencies: ["TeamsWorkerSpike"])
    ]
)
