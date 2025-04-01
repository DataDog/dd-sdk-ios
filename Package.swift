// swift-tools-version: 5.9

import PackageDescription
import Foundation

// If the `OTEL_SWIFT` environment variable is set, `dd-sdk-ios` will be compiled against `OpenTelemetryApi` 
// from https://github.com/open-telemetry/opentelemetry-swift, which includes the full OpenTelemetry SDK.
// Otherwise, it will use our lightweight mirror from https://github.com/DataDog/opentelemetry-swift-packages.
//
// This split is driven by feedback from https://github.com/DataDog/dd-sdk-ios/issues/1877, where 
// users reported that fetching the full OpenTelemetry SDK significantly increased dependency size. 
//
// By using this environment variable, `dd-sdk-ios` consumers can choose whether to depend on the entire 
// OpenTelemetry SDK or just the API. This remains necessary until OpenTelemetry officially separates 
// the API and SDK packages (see https://github.com/open-telemetry/opentelemetry-swift/issues/486).
let useOTelSwiftPackage = ProcessInfo.processInfo.environment["OTEL_SWIFT"] != nil

let opentelemetry = useOTelSwiftPackage ? 
    (name: "opentelemetry-swift", url: "https://github.com/open-telemetry/opentelemetry-swift.git", version: Version("1.13.0")) :
    (name: "opentelemetry-swift-packages", url: "https://github.com/DataDog/opentelemetry-swift-packages.git", version: Version("1.13.1"))

// `dd-sdk-ios` supports a broader range of platform versions than `OpenTelemetryApi`. 
// When compiled in `OTEL_SWIFT` mode, we need to adjust the supported platforms accordingly.
let platforms: [SupportedPlatform] = useOTelSwiftPackage ?
    [.iOS(.v13), .tvOS(.v13), .macOS(.v12), .watchOS(.v7)] :
    [.iOS(.v12), .tvOS(.v12), .macOS(.v12), .watchOS(.v7)]

let internalSwiftSettings: [SwiftSetting] = ProcessInfo.processInfo.environment["DD_BENCHMARK"] != nil ?
    [.define("DD_BENCHMARK")] : []

let package = Package(
    name: "Datadog",
    platforms: platforms,
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
        .package(url: "https://github.com/microsoft/plcrashreporter.git", from: "1.12.0"),
        .package(url: opentelemetry.url, exact: opentelemetry.version),
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
