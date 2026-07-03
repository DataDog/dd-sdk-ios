/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

@available(iOS 16.0, *)
final class SRLayerSnapshotTests: LayerSnapshotTestCase {
    private let snapshotsFolderPath = "_snapshots_/png"
    private var shouldRecord = false

    @MainActor
    func testSwiftUIText() async throws {
        try await takeLayerSnapshotFor(
            TextFixtureView(),
            with: TextAndInputPrivacyLevel.allCases,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath
        )
    }

    @MainActor
    func testBasicControlsAndIndicators() async throws {
        try await takeLayerSnapshotFor(
            BasicControlsAndIndicatorsFixtureView(),
            imagePrivacyLevel: .maskAll,
            shouldRecord: shouldRecord,
            folderPath: snapshotsFolderPath
        )
    }
}
