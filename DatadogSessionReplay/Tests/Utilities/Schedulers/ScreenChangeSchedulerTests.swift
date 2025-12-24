/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import QuartzCore
import TestUtilities
import XCTest

@testable import DatadogSessionReplay

final class ScreenChangeSchedulerTests: XCTestCase {
    private let telemetryMock = TelemetryMock()
    private let testTimeProvider = TestTimeProvider(now: 0)
    // swiftlint:disable:next implicitly_unwrapped_optional
    private var screenChangeScheduler: ScreenChangeScheduler<TestTimeProvider>!

    override func setUp() {
        super.setUp()
        screenChangeScheduler = ScreenChangeScheduler(
            minimumInterval: 0.1,
            telemetry: telemetryMock,
            timeProvider: testTimeProvider
        )
    }

    override func tearDown() {
        screenChangeScheduler.stop()
        super.tearDown()
    }

    func testScheduledOperationsExecuteOnScreenChanges() {
        // given
        let layer = CALayer()
        let operationExecuted = self.expectation(description: "operation executed")

        screenChangeScheduler.schedule { operationExecuted.fulfill() }
        screenChangeScheduler.start()

        // when
        layer.display()
        testTimeProvider.advance(by: 0.1)

        // then
        wait(for: [operationExecuted])
    }

    func testMultipleOperationsExecute() {
        // given
        let layer = CALayer()
        let operationExecuted = self.expectation(description: "operation executed")
        operationExecuted.expectedFulfillmentCount = 3

        screenChangeScheduler.schedule { operationExecuted.fulfill() }
        screenChangeScheduler.schedule { operationExecuted.fulfill() }
        screenChangeScheduler.schedule { operationExecuted.fulfill() }
        screenChangeScheduler.start()

        // when
        layer.display()
        testTimeProvider.advance(by: 0.1)

        // then
        wait(for: [operationExecuted])
    }
}
#endif
