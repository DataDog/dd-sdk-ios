// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "DatadogTestHelpers",
    products: [
        .library(
            name: "DatadogTestHelpers",
            targets: ["DatadogTestHelpers"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "DatadogTestHelpers",
            dependencies: []),
    ]
)
