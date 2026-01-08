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
    private let testTimeProvider = TestTimeProvider(now: 0)
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var layerChangeAggregator: CALayerChangeAggregator<TestTimeProvider>!
    private var snapshots: [CALayerChangeSnapshot] = []

    override func setUp() {
        super.setUp()

        layerChangeAggregator = CALayerChangeAggregator(
            minimumDeliveryInterval: 0.1,
            timeProvider: testTimeProvider
        ) { [weak self] snapshot in
            self?.snapshots.append(snapshot)
        }
    }

    override func tearDown() {
        snapshots.removeAll()
        super.tearDown()
    }

    func testCoalescesChangesAndDeliversAtMostOncePerInterval() {
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
        layerChangeAggregator.start()

        testTimeProvider.advance(to: 0.016)
        layerChangeAggregator.layerDidDisplay(layer)

        testTimeProvider.advance(to: 0.032)
        layerChangeAggregator.layerDidDraw(layer, in: context)
        layerChangeAggregator.layerDidLayoutSublayers(layer)

        // then
        XCTAssertEqual(snapshots.count, 0, "Should not have delivered a snapshot yet")

        // when
        testTimeProvider.advance(to: 0.1)

        // then
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(
            snapshots[0],
            CALayerChangeSnapshot(
                [ObjectIdentifier(layer): CALayerChange(layer: layer, aspects: [.display, .draw, .layout])]
            )
        )
    }

    func testDeliversImmediatelyWhenOutsideThrottleWindow() {
        // given
        let layer = CALayer()

        // when
        layerChangeAggregator.start()

        testTimeProvider.advance(to: 0.02)
        layerChangeAggregator.layerDidDisplay(layer)

        // then
        XCTAssertEqual(snapshots.count, 0, "Should not have delivered a snapshot yet")

        // when
        testTimeProvider.advance(to: 0.1)

        // then
        XCTAssertEqual(snapshots.count, 1)

        // when
        testTimeProvider.advance(to: 0.5)
        layerChangeAggregator.layerDidLayoutSublayers(layer)

        // then
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(
            snapshots,
            [
                .init(
                    [ObjectIdentifier(layer): CALayerChange(layer: layer, aspects: .display)]
                ),
                .init(
                    [ObjectIdentifier(layer): CALayerChange(layer: layer, aspects: .layout)]
                ),
            ]
        )
    }

    func testMergesChangesForMultipleLayersIndependently() {
        // given
        let layerA = CALayer()
        let layerB = CALayer()

        // when
        layerChangeAggregator.start()

        testTimeProvider.advance(to: 0.01)
        layerChangeAggregator.layerDidDisplay(layerA)

        testTimeProvider.advance(to: 0.02)
        layerChangeAggregator.layerDidLayoutSublayers(layerB)

        testTimeProvider.advance(to: 0.1)

        // then
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(
            snapshots[0],
            CALayerChangeSnapshot(
                [
                    ObjectIdentifier(layerA): CALayerChange(layer: layerA, aspects: .display),
                    ObjectIdentifier(layerB): CALayerChange(layer: layerB, aspects: .layout)
                ]
            )
        )
    }

    func testNoSnapshotsWhenNoChangesOccur() {
        // when
        layerChangeAggregator.start()
        testTimeProvider.advance(to: 10.0) // time passes, but no changes

        // then
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testIgnoresChangesBeforeStartAndAfterStop() {
        // given
        let layer = CALayer()

        // when
        testTimeProvider.advance(to: 0.01)
        layerChangeAggregator.layerDidDisplay(layer) // ignored
        testTimeProvider.advance(to: 1.0)

        // then
        XCTAssertTrue(snapshots.isEmpty)

        // when
        layerChangeAggregator.start()

        testTimeProvider.advance(to: 1.01)
        layerChangeAggregator.layerDidDisplay(layer) // accepted and delivered
        testTimeProvider.advance(to: 1.1)

        // then
        XCTAssertEqual(snapshots.count, 1)

        // when
        layerChangeAggregator.stop()

        testTimeProvider.advance(to: 2.000)
        layerChangeAggregator.layerDidLayoutSublayers(layer) // ignored
        testTimeProvider.advance(to: 2.500)

        // then
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(
            snapshots[0],
            CALayerChangeSnapshot(
                [ObjectIdentifier(layer): CALayerChange(layer: layer, aspects: .display)]
            )
        )
    }
}
#endif
