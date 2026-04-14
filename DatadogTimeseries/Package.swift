// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DatadogTimeseries",
    products: [
        .library(
            name: "DatadogTimeseries",
            targets: ["DatadogTimeseries"]
        ),
    ],
    targets: [
        .target(
            name: "DatadogTimeseries",
            dependencies: [],
            path: "Sources/DatadogTimeseries"
        ),
        .testTarget(
            name: "DatadogTimeseriesTests",
            dependencies: ["DatadogTimeseries"],
            path: "Tests/DatadogTimeseriesTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
