// swift-tools-version: 5.7.1

import PackageDescription

let package = Package(
    name: "TestUtilities",
    platforms: [
        .iOS(.v11),
        .tvOS(.v11),
    ],
    products: [
        .library(
            name: "TestUtilities",
            targets: ["TestUtilities"]
        ),
    ],
    dependencies: [
        .package(name: "Datadog", path: "../DDPatchForSR"), // needs patch because the main `Package.swift` defines conflicting `DatadogSessionReplay` module
    ],
    targets: [
        .target(
            name: "TestUtilities",
            dependencies: ["Datadog"],
            path: ".",
            sources: ["Helpers", "Mocks"]
        ),
    ]
)
