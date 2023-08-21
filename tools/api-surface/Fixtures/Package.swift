// swift-tools-version: 5.8.1

import PackageDescription

let package = Package(
    name: "Fixtures",
    products: [
        .library(name: "Fixture1", targets: ["Fixture1"]),
        .library(name: "Fixture2", targets: ["Fixture2"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "Fixture1", dependencies: []),
        .target(
            name: "Fixture2",
            path: "Fixture2/Sources"
        )
    ]
)
