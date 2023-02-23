// swift-tools-version: 5.7

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
            dependencies: [
                .product(name: "Datadog", package: "Datadog"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "DatadogSessionReplayTests",
            dependencies: [
                .target(name: "DatadogSessionReplay"),
                .product(name: "TestUtilities", package: "TestUtilities")
            ],
            path: "Tests"
        )
    ]
)
