// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TestUtilities",
    platforms: [
        .iOS(.v11),
        .tvOS(.v11),
    ],
    products: [
        .library(
            name: "TestUtilities",
            targets: ["TestUtilities"]),
    ],
    dependencies: [
        .package(name: "Datadog", path: ".."),
    ],
    targets: [
        .target(
            name: "TestUtilities",
            dependencies: []),
        .testTarget(
            name: "TestUtilitiesTests",
            dependencies: ["TestUtilities"]),
    ]
)
