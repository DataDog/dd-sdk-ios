// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "Datadog",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "Datadog",
            type: .dynamic,
            targets: ["Datadog"]),
        .library(
            name: "DatadogObjc",
            type: .dynamic,
            targets: ["DatadogObjc"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Datadog",
            dependencies: ["_Datadog_Private", "OpenTracing"]),
        .target(
            name: "DatadogObjc",
            dependencies: ["Datadog"]),
        .target(
            name: "_Datadog_Private"
        ),
        .testTarget(
            name: "DatadogTests",
            dependencies: ["Datadog", "DatadogObjc", "OpenTracing"]),
    ]
)
