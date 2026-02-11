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
    private let testTimerScheduler = TestTimerScheduler(now: 0)
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var screenChangeMonitor: ScreenChangeMonitor!
    private var changes: [CALayerChangeset] = []

    override func setUp() async throws {
        try await super.setUp()

        screenChangeMonitor = try ScreenChangeMonitor(
            minimumDeliveryInterval: 0.1,
            timerScheduler: testTimerScheduler
        ) { [weak self] changeset in
            self?.changes.append(changeset)
        }
    }

    override func tearDown() {
        changes.removeAll()
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
        XCTAssertEqual(changes.count, 0, "Should ignore layer changes before calling start()")

        // when
        screenChangeMonitor.start()

        testTimerScheduler.advance(to: 1.01)
        layer.display()
        testTimerScheduler.advance(to: 1.20)

        // then
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].aspects(for: .init(layer)), .display)

        // given
        changes.removeAll()

        // when
        screenChangeMonitor.stop()

        testTimerScheduler.advance(to: 2.00)
        layer.display()
        testTimerScheduler.advance(to: 3.00)

        // then
        XCTAssertEqual(changes.count, 0, "Should ignore layer changes after calling stop()")
    }
}
#endif
