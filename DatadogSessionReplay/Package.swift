// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "DatadogSessionReplay",
    platforms: [
        .iOS(.v11),
        .tvOS(.v11),
    ],
    products: [
        .library(
            name: "DatadogSessionReplay",
            targets: ["DatadogSessionReplay"]
        ),
    ],
    dependencies: [
        .package(name: "Datadog", path: ".."),
        .package(name: "TestUtilities", path: "../TestUtilities"),
    ],
    targets: [
        .target(
            name: "DatadogSessionReplay",
            dependencies: ["Datadog"]
        ),
        .testTarget(
            name: "DatadogSessionReplayTests",
            dependencies: ["DatadogSessionReplay", "TestUtilities"]
        ),
    ]
)
