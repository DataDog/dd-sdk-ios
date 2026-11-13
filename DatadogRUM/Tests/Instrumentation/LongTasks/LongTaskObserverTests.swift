/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

class LongTaskObserverTests: XCTestCase {
    private let dateProvider = DateProviderMock()
    private let subscriber = RUMCommandSubscriberMock()

    /// Runs one iteration of the main run loop whose work advances the mocked clock by `workDuration`.
    private func runMainRunLoopIteration(advancingClockBy workDuration: TimeInterval) {
        RunLoop.main.perform { [dateProvider] in
            dateProvider.now.addTimeInterval(workDuration)
        }
        RunLoop.main.run(until: Date() + 0.1)
    }

    func testWhenRunLoopIterationExceedsThreshold_itSendsLongTaskWithItsThreshold() throws {
        // Given
        let observer = LongTaskObserver(threshold: 0.5, dateProvider: dateProvider)
        observer.publish(to: subscriber)
        observer.start()
        defer { observer.stop() }

        // When
        runMainRunLoopIteration(advancingClockBy: 1)

        // Then
        let longTasks = subscriber.receivedCommands.compactMap { $0 as? RUMAddLongTaskCommand }
        let longTask = try XCTUnwrap(longTasks.first)
        XCTAssertEqual(longTasks.count, 1)
        XCTAssertEqual(longTask.mainRunLoopThreshold, 0.5)
        XCTAssertEqual(longTask.duration, 1)
        XCTAssertEqual(longTask.time, dateProvider.now)
    }

    func testWhenRunLoopIterationIsBelowThreshold_itSendsNoCommand() {
        // Given
        let observer = LongTaskObserver(threshold: 0.5, dateProvider: dateProvider)
        observer.publish(to: subscriber)
        observer.start()
        defer { observer.stop() }

        // When
        runMainRunLoopIteration(advancingClockBy: 0.1)

        // Then
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
    }
}
