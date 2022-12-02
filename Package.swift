// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Datadog",
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
            name: "DatadogDynamic",
            type: .dynamic,
            targets: ["Datadog"]
        ),
        .library(
            name: "DatadogDynamicObjc",
            type: .dynamic,
            targets: ["DatadogObjc"]
        ),
        .library( // TODO: RUMM-2387 Consider removing explicit linkage variants
            name: "DatadogStatic",
            type: .static,
            targets: ["Datadog"]
        ),
        .library( // TODO: RUMM-2387 Consider removing explicit linkage variants
            name: "DatadogStaticObjc",
            type: .static,
            targets: ["DatadogObjc"]
        ),
        .library(
            name: "DatadogCrashReporting",
            targets: ["DatadogCrashReporting"]
        ),
        .library(
            name: "DatadogAlamofireExtension",
            targets: ["DatadogAlamofireExtension"]
        )
    ],
    dependencies: [
        .package(name: "PLCrashReporter", url: "https://github.com/microsoft/plcrashreporter.git", from: "1.11.0"),
        .package(name: "Alamofire", url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "Datadog",
            dependencies: [
                "_Datadog_Private",
            ],
            swiftSettings: [.define("SPM_BUILD")]
        ),
        .target(
            name: "DatadogObjc",
            dependencies: [
                "Datadog",
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
            ]
        ),
        .target(
            name: "DatadogAlamofireExtension",
            dependencies: [
                "Datadog",
                "Alamofire"
            ],
            path: "Sources/DatadogExtensions/Alamofire/"
        ),
    ]
)
