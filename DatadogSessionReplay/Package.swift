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
        .library(
            name: "TestUtilities",
            targets: ["TestUtilities"]
        ),
    ],
    targets: [
        .target(
            name: "DatadogSessionReplay",
            dependencies: [
                .target(name: "DatadogInternal"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "DatadogSessionReplayTests",
            dependencies: [
                .target(name: "DatadogSessionReplay"),
                .target(name: "TestUtilities")
            ],
            path: "Tests"
        ),

        .target(
            name: "DatadogInternal",
            path: "DatadogInternal/Sources"
        ),
        .testTarget(
            name: "DatadogInternalTests",
            dependencies: [
                .target(name: "DatadogInternal"),
                .target(name: "TestUtilities"),
            ],
            path: "DatadogInternal/Tests"
        ),

        .target(
            name: "TestUtilities",
            dependencies: [
                .target(name: "DatadogInternal"),
            ],
            path: "TestUtilities",
            sources: ["Mocks", "Helpers"]
        )
    ]
)
