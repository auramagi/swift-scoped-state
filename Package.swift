// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScopedState",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "ScopedState",
            targets: ["ScopedState"]
        ),
    ],
    targets: [
        .target(name: "ScopedState"),
    ]
)
