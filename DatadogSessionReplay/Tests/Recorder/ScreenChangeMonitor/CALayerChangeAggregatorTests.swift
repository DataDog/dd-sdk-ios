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
    private let testTimerScheduler = TestTimerScheduler(now: 0)
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var layerChangeAggregator: CALayerChangeAggregator!
    private var changesets: [CALayerChangeset] = []

    override func setUp() {
        super.setUp()

        layerChangeAggregator = CALayerChangeAggregator(
            minimumDeliveryInterval: 0.1,
            timerScheduler: testTimerScheduler
        ) { [weak self] changeset in
            self?.changesets.append(changeset)
        }
    }

    override func tearDown() {
        changesets.removeAll()
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

        testTimerScheduler.advance(to: 0.016)
        layerChangeAggregator.layerDidDisplay(layer)

        testTimerScheduler.advance(to: 0.032)
        layerChangeAggregator.layerDidDraw(layer, in: context)
        layerChangeAggregator.layerDidLayoutSublayers(layer)

        // then
        XCTAssertEqual(changesets.count, 0, "Should not have delivered a changeset yet")

        // when
        testTimerScheduler.advance(to: 0.1)

        // then
        XCTAssertEqual(changesets.count, 1)
        XCTAssertEqual(
            changesets[0],
            CALayerChangeset(
                [ObjectIdentifier(layer): CALayerChange(layer: .init(layer), aspects: [.display, .draw, .layout])]
            )
        )
    }

    func testDefersDeliveryWhenOutsideThrottleWindow() {
        // given
        let layer = CALayer()

        // when
        layerChangeAggregator.start()

        testTimerScheduler.advance(to: 0.02)
        layerChangeAggregator.layerDidDisplay(layer)

        // then
        XCTAssertEqual(changesets.count, 0, "Should not have delivered a changeset yet")

        // when
        testTimerScheduler.advance(to: 0.1)

        // then
        XCTAssertEqual(changesets.count, 1)

        // when
        testTimerScheduler.advance(to: 0.5)
        layerChangeAggregator.layerDidLayoutSublayers(layer)

        // then
        XCTAssertEqual(changesets.count, 1, "Should not deliver synchronously from the layer callback")

        // when
        testTimerScheduler.advance(to: 0.5)

        // then
        XCTAssertEqual(changesets.count, 2)
        XCTAssertEqual(
            changesets,
            [
                .init(
                    [ObjectIdentifier(layer): CALayerChange(layer: .init(layer), aspects: .display)]
                ),
                .init(
                    [ObjectIdentifier(layer): CALayerChange(layer: .init(layer), aspects: .layout)]
                )
            ]
        )
    }

    func testMergesChangesRecordedBeforeDeferredDeliveryRuns() {
        // given
        let layer = CALayer()

        // when
        layerChangeAggregator.start()

        testTimerScheduler.advance(to: 0.5)
        layerChangeAggregator.layerDidDisplay(layer)
        layerChangeAggregator.layerDidLayoutSublayers(layer)

        // then
        XCTAssertTrue(changesets.isEmpty, "Should defer delivery until the scheduled task runs")

        // when
        testTimerScheduler.advance(to: 0.5)

        // then
        XCTAssertEqual(
            changesets,
            [
                .init(
                    [ObjectIdentifier(layer): CALayerChange(layer: .init(layer), aspects: [.display, .layout])]
                )
            ]
        )
    }

    func testIgnoresChangesTriggeredWhileDelivering() {
        // given
        let layer = CALayer()
        let reentrantLayer = CALayer()

        layerChangeAggregator = CALayerChangeAggregator(
            minimumDeliveryInterval: 0.1,
            timerScheduler: testTimerScheduler
        ) { [weak self] changeset in
            self?.changesets.append(changeset)
            self?.layerChangeAggregator.layerDidLayoutSublayers(reentrantLayer)
        }

        // when
        layerChangeAggregator.start()

        testTimerScheduler.advance(to: 0.02)
        layerChangeAggregator.layerDidDisplay(layer)

        testTimerScheduler.advance(to: 0.1)

        // then
        XCTAssertEqual(changesets.count, 1)
        XCTAssertEqual(
            changesets[0],
            CALayerChangeset(
                [ObjectIdentifier(layer): CALayerChange(layer: .init(layer), aspects: .display)]
            )
        )

        // when
        testTimerScheduler.advance(to: 0.5)

        // then
        XCTAssertEqual(changesets.count, 1, "Should ignore changes triggered while delivering")
    }

    func testMergesChangesForMultipleLayersIndependently() {
        // given
        let layerA = CALayer()
        let layerB = CALayer()

        // when
        layerChangeAggregator.start()

        testTimerScheduler.advance(to: 0.01)
        layerChangeAggregator.layerDidDisplay(layerA)

        testTimerScheduler.advance(to: 0.02)
        layerChangeAggregator.layerDidLayoutSublayers(layerB)

        testTimerScheduler.advance(to: 0.1)

        // then
        XCTAssertEqual(changesets.count, 1)
        XCTAssertEqual(
            changesets[0],
            CALayerChangeset(
                [
                    ObjectIdentifier(layerA): CALayerChange(layer: .init(layerA), aspects: .display),
                    ObjectIdentifier(layerB): CALayerChange(layer: .init(layerB), aspects: .layout)
                ]
            )
        )
    }

    func testNoChangesetsWhenNoChangesOccur() {
        // when
        layerChangeAggregator.start()
        testTimerScheduler.advance(to: 10.0) // time passes, but no changes

        // then
        XCTAssertTrue(changesets.isEmpty)
    }

    func testIgnoresChangesBeforeStartAndAfterStop() {
        // given
        let layer = CALayer()

        // when
        testTimerScheduler.advance(to: 0.01)
        layerChangeAggregator.layerDidDisplay(layer) // ignored
        testTimerScheduler.advance(to: 1.0)

        // then
        XCTAssertTrue(changesets.isEmpty)

        // when
        layerChangeAggregator.start()

        testTimerScheduler.advance(to: 1.01)
        layerChangeAggregator.layerDidDisplay(layer) // accepted and delivered
        testTimerScheduler.advance(to: 1.1)

        // then
        XCTAssertEqual(changesets.count, 1)

        // when
        layerChangeAggregator.stop()

        testTimerScheduler.advance(to: 2.000)
        layerChangeAggregator.layerDidLayoutSublayers(layer) // ignored
        testTimerScheduler.advance(to: 2.500)

        // then
        XCTAssertEqual(changesets.count, 1)
        XCTAssertEqual(
            changesets[0],
            CALayerChangeset(
                [ObjectIdentifier(layer): CALayerChange(layer: .init(layer), aspects: .display)]
            )
        )
    }
}
#endif
