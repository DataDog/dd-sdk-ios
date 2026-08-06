/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import UIKit
import XCTest

@_spi(Internal)
import DatadogInternal

@testable import DatadogSessionReplay

@MainActor
final class ScreenChangeMonitorTests: XCTestCase {
    private let testTimerScheduler = TestTimerScheduler(now: 0)
    private let notificationCenter = NotificationCenter()
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var screenChangeMonitor: ScreenChangeMonitor!
    private var changesets: [CALayerChangeset] = []

    override func setUp() async throws {
        try await super.setUp()

        screenChangeMonitor = try ScreenChangeMonitor(
            minimumDeliveryInterval: 0.1,
            timerScheduler: testTimerScheduler,
            notificationCenter: notificationCenter
        ) { [weak self] changeset in
            self?.changesets.append(changeset)
        }
    }

    override func tearDown() {
        changesets.removeAll()
        super.tearDown()
    }

    func testStartAndStop() {
        // given
        let layer = CALayer()

        // when
        testTimerScheduler.advance(to: 0.01)
        layer.display() // ignored
        testTimerScheduler.advance(to: 1.00)

        // then
        XCTAssertEqual(changesets.count, 0, "Should ignore layer changes before calling start()")

        // when
        screenChangeMonitor.start()

        testTimerScheduler.advance(to: 1.01)
        layer.display()
        testTimerScheduler.advance(to: 1.20)

        // then
        XCTAssertEqual(changesets.count, 1)
        XCTAssertEqual(changesets[0].aspects(for: .init(layer)), .display)

        // given
        changesets.removeAll()

        // when
        screenChangeMonitor.stop()

        testTimerScheduler.advance(to: 2.00)
        layer.display()
        testTimerScheduler.advance(to: 3.00)

        // then
        XCTAssertEqual(changesets.count, 0, "Should ignore layer changes after calling stop()")
    }

    /// The monitor hops the notification onto the main queue before recording it, so this waits for
    /// that hop. FIFO ordering guarantees the monitor's block ran before this one is fulfilled.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    func testSlotIDAssignmentCountsAsAScreenChange() {
        // given — a view that is marked as an embedded content slot. Only CALayer display, draw and
        // layout are observed, and assigning a slot ID produces none of them — yet the placeholder
        // wireframe for the slot can only be recorded by a snapshot taken after the ID is in place.
        let view = UIView()
        screenChangeMonitor.start()

        // when
        testTimerScheduler.advance(to: 1.00)
        notificationCenter.post(name: .ddSessionReplaySlotIDDidChange, object: view)
        drainMainQueue()
        testTimerScheduler.advance(to: 1.20)

        // then
        XCTAssertEqual(changesets.count, 1)
        XCTAssertEqual(changesets[0].aspects(for: .init(view.layer)), .layout)
    }

    func testSlotIDAssignmentAfterStopIsIgnored() {
        // given
        let view = UIView()
        screenChangeMonitor.start()
        screenChangeMonitor.stop()

        // when
        testTimerScheduler.advance(to: 1.00)
        notificationCenter.post(name: .ddSessionReplaySlotIDDidChange, object: view)
        drainMainQueue()
        testTimerScheduler.advance(to: 1.20)

        // then
        XCTAssertEqual(changesets.count, 0, "Should ignore slot ID changes after calling stop()")
    }
}
#endif
