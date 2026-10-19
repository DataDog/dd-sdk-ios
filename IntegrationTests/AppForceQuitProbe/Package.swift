// swift-tools-version: 5.9
/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */
import PackageDescription

let package = Package(
    name: "AppForceQuitProbe",
    platforms: [.macOS(.v13), .iOS(.v15)],
    targets: [
        .target(name: "ProbeCore"),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"])
    ]
)
