// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "Datadog",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_14),
    ],
    products: [
        .library(
            name: "Datadog",
            targets: ["Datadog"]),
    ],
    dependencies: [
        .package(path: "datadog-test-helpers/"),
    ],
    targets: [
        .target(
            name: "Datadog",
            dependencies: []),
        .testTarget(
            name: "DatadogTests",
            dependencies: ["Datadog", "DatadogTestHelpers"]),
    ]
)
