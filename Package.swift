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
        .library(
            name: "DatadogStatic",
            type: .static,
            targets: ["Datadog"]),
        .library(
            name: "DatadogStaticObjc",
            type: .static,
            targets: ["DatadogObjc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/lyft/Kronos.git", .upToNextMinor(from: "4.1.0"))
    ],
    targets: [
        .target(
            name: "Datadog",
            dependencies: ["_Datadog_Private", "Kronos"]),
        .target(
            name: "DatadogObjc",
            dependencies: ["Datadog"]),
        .target(
            name: "_Datadog_Private"
        ),
        .testTarget(
            name: "DatadogTests",
            dependencies: ["Datadog", "DatadogObjc"]),
    ]
)
