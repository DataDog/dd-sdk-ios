// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Fixtures",
    products: [
        .library(name: "Fixtures", targets: ["Fixtures"])
    ],
    dependencies: [],
    targets: [
        .target(name: "Fixtures", dependencies: [])
    ]
)
