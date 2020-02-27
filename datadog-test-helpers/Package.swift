// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "DatadogTestHelpers",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_14),
    ],
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
