// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-scoped-state",
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
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-docc-plugin",
            from: "1.5.0"
        ),
    ],
    targets: [
        .target(name: "ScopedState"),
        .testTarget(
            name: "ScopedStateTests",
            dependencies: ["ScopedState"]
        ),
    ]
)
