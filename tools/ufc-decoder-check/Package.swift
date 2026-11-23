// swift-tools-version: 6.2

import PackageDescription

// Development tool only. SwiftProtobuf is a dependency of this tool, not of the SDK.
let package = Package(
    name: "ufc-decoder-check",
    platforms: [.macOS("13.0")],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.1"),
    ],
    targets: [
        .executableTarget(
            name: "UFCDecoderCheck",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
