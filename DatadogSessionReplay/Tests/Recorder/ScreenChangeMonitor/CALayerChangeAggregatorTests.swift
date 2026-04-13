/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import XCTest

@testable import DatadogSessionReplay

@MainActor
final class CALayerChangeAggregatorTests: XCTestCase {
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var layerChangeAggregator: CALayerChangeAggregator!

    override func setUp() {
        super.setUp()
        layerChangeAggregator = CALayerChangeAggregator()
    }

    func testAccumulatesAndMergesAspectsForSameLayer() {
        // given
        let layer = CALayer()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // when
        layerChangeAggregator.layerDidDisplay(layer)
        layerChangeAggregator.layerDidDraw(layer, in: context)
        layerChangeAggregator.layerDidLayoutSublayers(layer)

        // then
        let snapshot = layerChangeAggregator.takePendingChanges()
        XCTAssertEqual(
            snapshot,
            CALayerChangeSnapshot(
                [ObjectIdentifier(layer): CALayerChange(layer: layer, aspects: [.display, .draw, .layout])]
            )
        )
    }

    func testTracksMultipleLayersIndependently() {
        // given
        let layerA = CALayer()
        let layerB = CALayer()

        // when
        layerChangeAggregator.layerDidDisplay(layerA)
        layerChangeAggregator.layerDidLayoutSublayers(layerB)

        // then
        let snapshot = layerChangeAggregator.takePendingChanges()
        XCTAssertEqual(
            snapshot,
            CALayerChangeSnapshot(
                [
                    ObjectIdentifier(layerA): CALayerChange(layer: layerA, aspects: .display),
                    ObjectIdentifier(layerB): CALayerChange(layer: layerB, aspects: .layout),
                ]
            )
        )
    }

    func testTakePendingChangesResetsState() {
        // given
        let layer = CALayer()
        layerChangeAggregator.layerDidDisplay(layer)

        // when
        let firstSnapshot = layerChangeAggregator.takePendingChanges()
        let secondSnapshot = layerChangeAggregator.takePendingChanges()

        // then
        XCTAssertFalse(firstSnapshot.isEmpty)
        XCTAssertTrue(secondSnapshot.isEmpty)
    }

    func testTakePendingChangesRemovesDeallocatedLayers() {
        // given
        var layer: CALayer? = CALayer()
        layerChangeAggregator.layerDidDisplay(layer!)
        layer = nil

        // when
        let snapshot = layerChangeAggregator.takePendingChanges()

        // then
        XCTAssertTrue(snapshot.isEmpty)
    }
}
#endif
