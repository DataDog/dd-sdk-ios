// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DatadogBenchmarks",
    platforms: [.iOS(.v12), .tvOS(.v12)],
    products: [
        .library(
            name: "DatadogBenchmarks",
            targets: ["DatadogBenchmarks"]
        )
    ],
    targets: [
        .target(
            name: "DatadogBenchmarks"
        )
    ]
)
