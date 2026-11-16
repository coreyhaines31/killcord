// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KillCordCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KillCordCore", targets: ["KillCordCore"])
    ],
    targets: [
        .target(name: "KillCordCore"),
        // `swift run killcord-dev` prints the caps catalog and the sample spend, with no keys and no network.
        .executableTarget(name: "killcord-dev", dependencies: ["KillCordCore"]),
        .testTarget(name: "KillCordCoreTests", dependencies: ["KillCordCore"], resources: [.copy("Fixtures")])
    ]
)
