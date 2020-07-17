// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "api-surface",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "0.2.0"),
        .package(url: "https://github.com/jpsim/SourceKitten.git", .exact("0.29.0")),
    ],
    targets: [
        .target(
            name: "api-surface",
            dependencies: [
                "APISurfaceCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "APISurfaceCore",
            dependencies: [
                .product(name: "SourceKittenFramework", package: "SourceKitten")
            ]
        ),
        .testTarget(
            name: "api-surfaceTests",
            dependencies: ["api-surface"]
        )
    ]
)
