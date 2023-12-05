// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "SRFixtures",
    platforms: [.iOS(.v11)],
    products: [
        .library(name: "SRFixtures", targets: ["SRFixtures"]),
    ],
    targets: [
        .target(
            name: "SRFixtures"
        ),
    ]
)
