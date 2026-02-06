// swift-tools-version: 5.7.1

import PackageDescription

let package = Package(
    name: "TestUtilities",
    platforms: [.iOS(.v12), .tvOS(.v12), .macOS(.v12), .watchOS(.v7)],
    products: [
        .library(
            name: "TestUtilities",
            targets: ["TestUtilities"]
        ),
    ],
    dependencies: [
        .package(name: "Datadog", path: ".."),
    ],
    targets: [
        .target(
            name: "TestUtilities",
            dependencies: [
                .product(name: "DatadogCore", package: "Datadog"),
                .product(name: "DatadogRUM", package: "Datadog"),
                .product(name: "DatadogLogs",package: "Datadog"),
                .product(name: "DatadogTrace",package: "Datadog"),
                .product(name: "DatadogCrashReporting",package: "Datadog"),
                .product(name: "DatadogSessionReplay", package: "Datadog"),
                .product(name: "DatadogWebViewTracking",package: "Datadog")
            ],
            path: ".",
            sources: ["Sources"],
            swiftSettings: [.define("SPM_BUILD")]
        ),
    ]
)
