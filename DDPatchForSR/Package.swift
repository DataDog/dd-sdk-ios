// swift-tools-version: 5.5

import PackageDescription

let package = Package(
    name: "DatadogSDK",
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
            name: "DatadogCrashReporting",
            targets: ["DatadogCrashReporting"]
        ),
    ],
    dependencies: [
        .package(name: "PLCrashReporter", url: "https://github.com/microsoft/plcrashreporter.git", from: "1.11.0"),
    ],
    targets: [
        .target(
            name: "Datadog",
            dependencies: [
                "_Datadog_Private",
            ],
            swiftSettings: [
                .define("SPM_BUILD"),
                .define("DD_SDK_ENABLE_EXPERIMENTAL_APIS"),
            ]
        ),
        .target(
            name: "DatadogObjc",
            dependencies: [
                "Datadog",
            ],
            swiftSettings: [
                .define("DD_SDK_ENABLE_EXPERIMENTAL_APIS"),
            ]
        ),
        .target(
            name: "_Datadog_Private"
        ),
        .target(
            name: "DatadogCrashReporting",
            dependencies: [
                "Datadog",
                .product(name: "CrashReporter", package: "PLCrashReporter"),
            ],
            swiftSettings: [
                .define("DD_SDK_ENABLE_EXPERIMENTAL_APIS"),
            ]
        ),
    ]
)
