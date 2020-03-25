// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "Datadog",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_14),
    ],
    products: [
        .library(
            name: "Datadog",
            targets: ["Datadog"]),
        .library(
            name: "DatadogObjc",
            targets: ["DatadogObjc"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "Datadog",
            dependencies: []),
        .target(
            name: "DatadogObjc",
            dependencies: ["Datadog"]),
        .testTarget(
            name: "DatadogTests",
            dependencies: ["Datadog", "DatadogObjc"]),
    ]
)
