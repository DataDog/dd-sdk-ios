// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "Datadog",
    platforms: [
        .iOS(.v11),
        .tvOS(.v11)
    ],
    products: [
        .library(
            name: "Datadog",
            targets: ["Datadog"]
        ),
        .library(
            name: "DatadogObjc",
            targets: ["DatadogObjc"]
        ),
        .library(
            name: "DatadogLogs",
            targets: ["DatadogLogs"]
        ),
        .library(
            name: "DatadogTrace",
            targets: ["DatadogTrace"]
        ),
        .library(
            name: "DatadogRUM",
            targets: ["DatadogRUM"]
        ),
        .library(
            name: "DatadogCrashReporting",
            targets: ["DatadogCrashReporting"]
        ),
        .library(
            name: "DatadogWebViewTracking",
            targets: ["DatadogWebViewTracking"]
        ),
//        .library(
//            name: "DatadogSessionReplay",
//            targets: ["DatadogSessionReplay"]
//        ),
    ],
    dependencies: [
        .package(name: "PLCrashReporter", url: "https://github.com/microsoft/plcrashreporter.git", from: "1.11.0"),
    ],
    targets: [
        .target(
            name: "Datadog",
            dependencies: [
                .target(name: "DatadogInternal"),
                .target(name: "DatadogLogs"),
                .target(name: "DatadogTrace"),
                .target(name: "DatadogRUM"),
                .target(name: "_Datadog_Private"),
            ],
            swiftSettings: [.define("SPM_BUILD")]
        ),
        .target(
            name: "DatadogObjc",
            dependencies: [
                .target(name: "Datadog"),
                .target(name: "DatadogLogs"),
                .target(name: "DatadogTrace"),
                .target(name: "DatadogRUM"),
            ]
        ),
        .target(
            name: "_Datadog_Private"
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
            name: "DatadogLogs",
            dependencies: [
                .target(name: "DatadogInternal"),
            ],
            path: "DatadogLogs/Sources"
        ),
        .testTarget(
            name: "DatadogLogsTests",
            dependencies: [
                .target(name: "DatadogLogs"),
                .target(name: "TestUtilities"),
            ],
            path: "DatadogLogs/Tests"
        ),

        .target(
            name: "DatadogTrace",
            dependencies: [
                .target(name: "DatadogInternal"),
            ],
            path: "DatadogTrace/Sources"
        ),
        .testTarget(
            name: "DatadogTraceTests",
            dependencies: [
                .target(name: "DatadogTrace"),
                .target(name: "TestUtilities"),
            ],
            path: "DatadogTrace/Tests"
        ),

        .target(
            name: "DatadogRUM",
            dependencies: [
                .target(name: "DatadogInternal"),
            ],
            path: "DatadogRUM/Sources"
        ),
        .testTarget(
            name: "DatadogRUMTests",
            dependencies: [
                .target(name: "DatadogRUM"),
                .target(name: "TestUtilities"),
            ],
            path: "DatadogRUM/Tests"
        ),

        .target(
            name: "DatadogCrashReporting",
            dependencies: [
                .target(name: "DatadogInternal"),
                .product(name: "CrashReporter", package: "PLCrashReporter"),
            ],
            path: "DatadogCrashReporting/Sources"
        ),
        .testTarget(
            name: "DatadogCrashReportingTests",
            dependencies: [
                .target(name: "DatadogCrashReporting"),
                .target(name: "TestUtilities"),
            ],
            path: "DatadogCrashReporting/Tests"
        ),

        .target(
            name: "DatadogWebViewTracking",
            dependencies: [
                .target(name: "DatadogInternal"),
            ],
            path: "DatadogWebViewTracking/Sources"
        ),
        .testTarget(
            name: "DatadogWebViewTrackingTests",
            dependencies: [
                .target(name: "DatadogWebViewTracking"),
                .target(name: "TestUtilities"),
            ],
            path: "DatadogWebViewTracking/Tests"
        ),

        .target(
            name: "DatadogSessionReplay",
            dependencies: ["DatadogInternal"],
            path: "DatadogSessionReplay/Sources"
        ),
        .testTarget(
            name: "DatadogSessionReplayTests",
            dependencies: [
                .target(name: "DatadogSessionReplay"),
                .target(name: "TestUtilities"),
            ],
            path: "DatadogSessionReplay/Tests"
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
