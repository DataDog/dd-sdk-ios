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
            targets: ["Datadog"]),
        .library(
            name: "DatadogObjc",
            targets: ["DatadogObjc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/DataDog/opentracing-swift.git", .branch("master")),
    ],
    targets: [
        .target(
            name: "Datadog",
            dependencies: ["OpenTracing"]),
        .target(
            name: "DatadogObjc",
            dependencies: ["Datadog"]),
        .testTarget(
            name: "DatadogTests",
            dependencies: ["Datadog", "DatadogObjc", "OpenTracing"]),
    ]
)
