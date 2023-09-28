// swift-tools-version: 5.7.1

import PackageDescription

let package = Package(
    name: "sr-snapshots",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "sr-snapshots", targets: ["SRSnapshots"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "SRSnapshots",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "SRSnapshotsCore",
            ]
        ),
        .target(
            name: "SRSnapshotsCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Files",
                "Git",
            ]
        ),
        .testTarget(
            name: "SRSnapshotsCoreTests",
            dependencies: ["SRSnapshotsCore"]
        ),
        .target(name: "Files"),
        .testTarget(name: "FilesTests", dependencies: ["Files"]),
        .target(name: "Shell"),
        .testTarget(name: "ShellTests", dependencies: ["Shell"]),
        .target(name: "Git", dependencies: ["Files", "Shell"]),
    ]
)
