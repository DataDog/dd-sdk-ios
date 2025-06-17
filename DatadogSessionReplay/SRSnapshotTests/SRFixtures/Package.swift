// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "SRFixtures",
    platforms: [.iOS(.v11)],
    products: [
        .library(name: "SRFixtures", targets: ["SRFixtures"]),
    ],
    dependencies: [
        .package(path: "../../../")
    ],
    targets: [
        .target(
            name: "SRFixtures",
            dependencies: [
                .product(name: "DatadogSessionReplay", package: "dd-sdk-ios")
            ]
        ),
    ]
)
