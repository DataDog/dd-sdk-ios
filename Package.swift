// swift-tools-version: 5.9

import PackageDescription
import Foundation

let opentelemetry = ProcessInfo.processInfo.environment["OTEL_SWIFT"] != nil ? 
    (name: "opentelemetry-swift", url: "https://github.com/open-telemetry/opentelemetry-swift.git") :
    (name: "opentelemetry-swift-packages", url: "https://github.com/DataDog/opentelemetry-swift-packages.git")

let internalSwiftSettings: [SwiftSetting] = ProcessInfo.processInfo.environment["DD_BENCHMARK"] != nil ?
    [.define("DD_BENCHMARK")] : []

let package = Package(
    name: "Datadog",
    platforms: [
        .iOS(.v12),
        .tvOS(.v12),
        .macOS(.v12),
        .watchOS(.v7)
    ],
    products: [
        .library(
            name: "DatadogCore",
            targets: ["DatadogCore"]
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
            name: "DatadogSessionReplay",
            targets: ["DatadogSessionReplay"]
        ),
        .library(
            name: "DatadogCrashReporting",
            targets: ["DatadogCrashReporting"]
        ),
        .library(
            name: "DatadogWebViewTracking",
            targets: ["DatadogWebViewTracking"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/plcrashreporter.git", from: "1.11.2"),
        .package(url: opentelemetry.url, exact: "1.6.0"),
    ],
    targets: [
        .target(
            name: "DatadogCore",
            dependencies: [
                .target(name: "DatadogInternal"),
                .target(name: "DatadogPrivate"),
            ],
            path: "DatadogCore",
            sources: ["Sources"],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [.define("SPM_BUILD")]
        ),
        .target(
            name: "DatadogObjc",
            dependencies: [
                .target(name: "DatadogCore"),
                .target(name: "DatadogLogs"),
                .target(name: "DatadogTrace"),
                .target(name: "DatadogRUM"),
            ],
            path: "DatadogObjc/Sources"
        ),
        .target(
            name: "DatadogPrivate",
            path: "DatadogCore/Private"
        ),

        .target(
            name: "DatadogInternal",
            path: "DatadogInternal/Sources",
            swiftSettings: internalSwiftSettings
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
                .product(name: "OpenTelemetryApi", package: opentelemetry.name)
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
            path: "DatadogRUM",
            sources: ["Sources"],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
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
            path: "DatadogCrashReporting",
            sources: ["Sources"],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
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
            path: "DatadogSessionReplay/Tests",
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        ),

        .target(
            name: "TestUtilities",
            dependencies: [
                .target(name: "DatadogInternal"),
            ],
            path: "TestUtilities",
            sources: ["Mocks", "Helpers", "Matchers"]
        )
    ]
)

// If the `DD_TEST_UTILITIES_ENABLED` development ENV is set, export additional utility packages.
// To set this ENV for Xcode projects that fetch this package locally, use `open --env DD_TEST_UTILITIES_ENABLED path/to/<project or workspace>`.
if ProcessInfo.processInfo.environment["DD_TEST_UTILITIES_ENABLED"] != nil {
    package.products.append(
        .library(
            name: "TestUtilities",
            targets: ["TestUtilities"]
        )
    )
}
