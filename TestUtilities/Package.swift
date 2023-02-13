// swift-tools-version: 5.5

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
            targets: ["TestUtilities"]
        ),
    ],
    dependencies: [
        .package(name: "Datadog", path: ".."),
    ],
    targets: [
        .target(
            name: "TestUtilities",
            dependencies: ["Datadog"],
            path: ".",
            sources: ["Helpers", "Mocks"]
        ),
    ]
)
