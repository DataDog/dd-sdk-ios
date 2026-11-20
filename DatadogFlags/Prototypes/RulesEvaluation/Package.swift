// swift-tools-version: 5.9
/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import PackageDescription

let package = Package(
    name: "RulesEvaluationPrototype",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "RulesEvaluationPrototype", targets: ["RulesEvaluationPrototype"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1"),
    ],
    targets: [
        .target(
            name: "RulesEvaluationPrototype",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")]
        ),
        .testTarget(
            name: "RulesEvaluationPrototypeTests",
            dependencies: ["RulesEvaluationPrototype"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
