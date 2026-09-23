/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

@available(iOS 16.0, *)
@MainActor
final class SRLayerSnapshotTests: LayerSnapshotTestCase {
    private var shouldRecord = false

    func testSwiftUIText() async throws {
        try await takeLayerSnapshotFor(
            TextFixtureView(),
            with: TextAndInputPrivacyLevel.allCases,
            shouldRecord: shouldRecord
        )
    }

    func testBasicControlsAndIndicators() async throws {
        try await takeLayerSnapshotFor(
            BasicControlsAndIndicatorsFixtureView(),
            imagePrivacyLevel: .maskAll,
            shouldRecord: shouldRecord
        )
    }

    func testSteppers() async throws {
        try await takeLayerSnapshotFor(
            StepperFixtureView(),
            imagePrivacyLevel: .maskAll,
            shouldRecord: shouldRecord
        )
    }

    func testAlert() async throws {
        try await takeLayerSnapshotFor(
            AlertFixtureView(),
            with: [.maskAll, .maskSensitiveInputs],
            shouldRecord: shouldRecord
        )
    }

    func testSafari() async throws {
        let fixture = SafariFixtureViewController()
        try await takeLayerSnapshotFor(
            fixture,
            beforeSnapshot: {
                await fixture.showSafari()
            },
            shouldRecord: shouldRecord
        )
    }

    func testShareSheet() async throws {
        let fixture = ShareSheetFixtureViewController()
        try await takeLayerSnapshotFor(
            fixture,
            waitTime: 1.0,
            beforeSnapshot: {
                await fixture.showShareSheet()
            },
            shouldRecord: shouldRecord
        )
    }

    func testTab() async throws {
        try await takeLayerSnapshotFor(
            TabFixtureView(),
            with: [.maskAll, .maskSensitiveInputs],
            shouldRecord: shouldRecord
        )
    }

    func testToolbar() async throws {
        try await takeLayerSnapshotFor(
            ToolbarFixtureView(),
            shouldRecord: shouldRecord
        )
    }
}
