// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenTrackerMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TokenTrackerCore", targets: ["TokenTrackerCore"]),
        .executable(name: "TokenTrackerMenuBar", targets: ["TokenTrackerMenuBar"]),
        .executable(name: "TokenTrackerSmokeTests", targets: ["TokenTrackerSmokeTests"])
    ],
    targets: [
        .target(name: "TokenTrackerCore", path: "Sources/TokenTrackerCore"),
        .executableTarget(
            name: "TokenTrackerMenuBar",
            dependencies: ["TokenTrackerCore"],
            path: "Sources/TokenTrackerMenuBar",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "TokenTrackerSmokeTests",
            dependencies: ["TokenTrackerCore"],
            path: "Sources/TokenTrackerSmokeTests"
        )
    ]
)
