// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SPMProject",
    platforms: [
        .macOS(.v10_14),
    ],
    dependencies: [
        .package(
            url: "https://github.com/DataDog/dd-sdk-ios",
            .branch("ncreated/RUMM-279-fix-spm-installation")
        )
    ],
    targets: [
        .target(
            name: "SPMProject",
            dependencies: ["Datadog"]),
    ]
)
