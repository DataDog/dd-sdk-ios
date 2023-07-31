// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "api-surface",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.2"),
        .package(url: "https://github.com/jpsim/SourceKitten", exact: "0.34.1"),
    ],
    targets: [
        .executableTarget(
            name: "api-surface",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "APISurfaceCore",
            ]
        ),
        .target(
            name: "APISurfaceCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SourceKittenFramework", package: "SourceKitten"),
            ]
        ),
        .testTarget(
            name: "APISurfaceCoreTests",
            dependencies: ["APISurfaceCore"]
        )
    ]
)
