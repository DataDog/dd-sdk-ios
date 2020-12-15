// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "rum-models-generator",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "rum-models-generator",
            targets: ["rum-models-generator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.2.0"),
        .package(name: "Difference", url: "https://github.com/krzysztofzablocki/Difference.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "rum-models-generator",
            dependencies: [
                "RUMModelsGeneratorCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .target(
            name: "RUMModelsGeneratorCore",
            dependencies: []
        ),
        .testTarget(
            name: "rum-models-generator-coreTests",
            dependencies: ["RUMModelsGeneratorCore", "Difference"]),
    ]
)
