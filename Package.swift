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
        .library(
            name: "DatadogObjc",
            targets: ["DatadogObjc"]),

        // The `DatadogTestHelpers` library is a workaround for no local packages support in SPM.
        // TODO: RUMM-279 remove `DatadogTestHelpers` from `Package.swift` by linking this code differently to instrumented tests.
        .library(
            name: "DatadogTestHelpers",
            targets: ["DatadogTestHelpers"]),
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
            dependencies: ["Datadog", "DatadogObjc", "DatadogTestHelpers"]),

        // TODO: RUMM-279 remove `DatadogTestHelpers` from `Package.swift`
        .target(
            name: "DatadogTestHelpers",
            dependencies: [],
            path: "datadog-test-helpers/Sources"
        ),
    ]
)
