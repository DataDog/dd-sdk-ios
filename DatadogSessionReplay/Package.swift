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
        .package(name: "Datadog", path: "../DDPatchForSR"), // needs patch because the main `Package.swift` defines conflicting `DatadogSessionReplay` module
        .package(name: "TestUtilities", path: "../TestUtilities"),
    ],
    targets: [
        .target(
            name: "DatadogSessionReplay",
            dependencies: ["Datadog"],
            path: "Sources"
        ),
        .testTarget(
            name: "DatadogSessionReplayTests",
            dependencies: [
                .target(name: "DatadogSessionReplay"),
                "TestUtilities"
            ],
            path: "Tests"
        )
    ]
)
