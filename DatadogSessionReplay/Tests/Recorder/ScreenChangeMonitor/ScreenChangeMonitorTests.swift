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
final class ScreenChangeMonitorTests: XCTestCase {
    private let testTimer = TestRepeatingTimer()
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var monitor: ScreenChangeMonitor!
    private var snapshots: [CALayerChangeSnapshot] = []

    override func setUp() async throws {
        try await super.setUp()

        monitor = try ScreenChangeMonitor(
            minimumDeliveryInterval: 0.1,
            timer: testTimer
        ) { [weak self] snapshot in
            self?.snapshots.append(snapshot)
        }
    }

    override func tearDown() {
        snapshots.removeAll()
        super.tearDown()
    }

    func testDeliversSnapshotWhenTimerFires() {
        // given
        let layer = CALayer()

        // when
        monitor.start()
        layer.display()
        testTimer.tick()

        // then
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].aspects(for: layer), .display)
    }

    func testDoesNotDeliverWhenNoChangesOccurred() {
        // when
        monitor.start()
        testTimer.tick()

        // then
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testIgnoresChangesBeforeStart() {
        // given
        let layer = CALayer()

        // when
        layer.display()
        testTimer.tick()

        // then
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testIgnoresChangesAfterStop() {
        // given
        let layer = CALayer()

        // when
        monitor.start()
        layer.display()
        testTimer.tick()

        // then
        XCTAssertEqual(snapshots.count, 1)

        // when
        monitor.stop()
        snapshots.removeAll()

        layer.display()
        testTimer.tick()

        // then
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testStartsAndStopsTimer() {
        // when
        monitor.start()

        // then
        XCTAssertTrue(testTimer.isRunning)

        // when
        monitor.stop()

        // then
        XCTAssertFalse(testTimer.isRunning)
    }
}
#endif
