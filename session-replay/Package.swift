// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "DatadogSessionReplay",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "DatadogSessionReplay",
            targets: ["DatadogSessionReplay"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "DatadogSessionReplay",
            dependencies: []
        ),
        .testTarget(
            name: "DatadogSessionReplayTests",
            dependencies: ["DatadogSessionReplay"]
        ),
    ]
)
