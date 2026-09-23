// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TestUtilities",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .macOS(.v12),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "TestUtilities",
            targets: ["TestUtilities"]
        ),
    ],
    dependencies: [
        .package(name: "Datadog", path: ".."),
        .package(url: "https://github.com/DataDog/dd-sdk-swift-testing.git", .upToNextMinor(from: "2.7.10")),
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
                .product(name: "DatadogWebViewTracking",package: "Datadog"),
                .product(name: "DatadogSDKTesting", package: "dd-sdk-swift-testing")
            ],
            path: ".",
            sources: ["Sources"],
            swiftSettings: [.define("SPM_BUILD")]
        ),
    ]
)
