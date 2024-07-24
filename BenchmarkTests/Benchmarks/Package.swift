// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DatadogBenchmarks",
    products: [
        .library(
            name: "DatadogBenchmarks",
            targets: ["Benchmarks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Benchmarks",
            dependencies: [
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift")
            ]
        )
    ]
)
