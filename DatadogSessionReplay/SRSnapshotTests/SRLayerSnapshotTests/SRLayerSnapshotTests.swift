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

    func testUIKitText() async throws {
        try await takeLayerSnapshotFor(
            TextFixtureViewController(),
            with: TextAndInputPrivacyLevel.allCases,
            shouldRecord: shouldRecord
        )
    }

    func testDrawingGroup() async throws {
        try await takeLayerSnapshotFor(
            DrawingGroupFixtureView(),
            with: [.maskAll, .maskSensitiveInputs],
            shouldRecord: shouldRecord
        )
    }

    func testCanvas() async throws {
        try await takeLayerSnapshotFor(
            CanvasFixtureView(),
            with: [.maskAll, .maskSensitiveInputs],
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

    func testVideoPlayer() async throws {
        try await takeLayerSnapshotFor(
            VideoPlayerFixtureView(),
            waitTime: 1.0,
            shouldRecord: shouldRecord
        )
    }

    func testSafari() async throws {
        func containsVisibleHost(_ layer: CALayer) -> Bool {
            guard let layerClass = NSClassFromString("CALayerHost"), !layer.isHidden, layer.opacity > 0 else {
                return false
            }
            return (layer.isKind(of: layerClass) && !layer.bounds.isEmpty)
                || layer.sublayers?.contains(where: containsVisibleHost) ?? false
        }

        let fixture = SafariFixtureViewController()
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let fixture = object as? SafariFixtureViewController,
                      let view = fixture.presentedViewController?.viewIfLoaded else {
                    return false
                }
                return containsVisibleHost(view.layer)
            },
            object: fixture
        )
        ready.expectationDescription = "Safari remote content"

        try await takeLayerSnapshotFor(
            fixture,
            beforeSnapshot: {
                fixture.showSafari()
                await self.fulfillment(of: [ready], timeout: 10.0)
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
