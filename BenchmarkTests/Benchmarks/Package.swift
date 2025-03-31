// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "DatadogBenchmarks",
    products: [
        .library(
            name: "DatadogBenchmarks",
            targets: ["DatadogBenchmarks"]
        )
    ]
)

func addOpenTelemetryDependency(_ version: Version) {
    // The project must be open with the 'OTEL_SWIFT' env variable.
    // Please run 'make benchmark-tests-open' from the root directory.
    //
    // Note: Carthage will still try to resolve dependencies of Xcode projects in
    // sub directories, in this case the project will depend on the default
    // 'DataDog/opentelemetry-swift-packages' depedency.
    if ProcessInfo.processInfo.environment["OTEL_SWIFT"] != nil {
        package.platforms = [.iOS(.v13), .tvOS(.v13)]

        package.dependencies = [
            .package(url: "https://github.com/open-telemetry/opentelemetry-swift", exact: version)
        ]

        package.targets = [
            .target(
                name: "DatadogBenchmarks",
                dependencies: [
                    .product(name: "OpenTelemetryApi", package: "opentelemetry-swift"),
                    .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift"),
                    .product(name: "DatadogExporter", package: "opentelemetry-swift")
                ],
                swiftSettings: [.define("OTEL_SWIFT")]
            )
        ]
    } else {
        package.platforms = [.iOS(.v12), .tvOS(.v12)]

        package.dependencies = [
            .package(url: "https://github.com/DataDog/opentelemetry-swift-packages", exact: version)
        ]

        package.targets = [
            .target(
                name: "DatadogBenchmarks",
                dependencies: [
                    .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-packages")
                ],
                swiftSettings: [.define("OTEL_API")]
            )
        ]
    }
}

if ProcessInfo.processInfo.environment["OTEL_SWIFT"] != nil {
    // RUM-9224: This condition was added to use DataDog/opentelemetry-swift-packages hotfix
    // release. It should be removed with the next upgrade of OTelApi.
    addOpenTelemetryDependency("1.13.0")
} else {
    addOpenTelemetryDependency("1.13.1")
}
