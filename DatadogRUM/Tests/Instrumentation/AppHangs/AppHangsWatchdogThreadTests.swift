/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class AppHangsWatchdogThreadTests: XCTestCase {
    func testWhenQueueHangsAboveThreshold_itReportsAppHangStartAndEnd() {
        let trackHangStarts = expectation(description: "track start of 3 App Hangs")
        trackHangStarts.expectedFulfillmentCount = 3
        let trackHangEnds = expectation(description: "track end of 3 App Hangs")
        trackHangEnds.expectedFulfillmentCount = 3

        // Given
        let appHangThreshold: TimeInterval = 0.1
        let hangDuration: TimeInterval = appHangThreshold * 2
        let queue = DispatchQueue(label: "main-queue", qos: .userInteractive)

        let watchdogThread = AppHangsWatchdogThread(
            appHangThreshold: appHangThreshold,
            queue: queue,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            telemetry: TelemetryMock()
        )
        watchdogThread.onHangStarted = { _ in trackHangStarts.fulfill() }
        watchdogThread.onHangEnded = { _, _ in trackHangEnds.fulfill() }
        watchdogThread.onHangCancelled = { _ in XCTFail("It should not cancel the hang") }
        watchdogThread.start()

        // When (multiple hangs above threshold)
        queue.async {
            Thread.sleep(forTimeInterval: hangDuration)
            queue.async { // async from queue so watchdog thread can interleve with its own tasks
                Thread.sleep(forTimeInterval: hangDuration)
                queue.async {
                    Thread.sleep(forTimeInterval: hangDuration)
                }
            }
        }

        // Then
        waitForExpectations(timeout: hangDuration * 10)
        watchdogThread.cancel()
    }

    func testWhenQueueHangsBelowThreshold_itDoesNotReportAppHangs() {
        let doNotTrackHangs = invertedExpectation(description: "track no App Hangs")

        // Given
        let appHangThreshold: TimeInterval = 0.5
        let hangDuration: TimeInterval = appHangThreshold * 0.1
        let queue = DispatchQueue(label: "main-queue", qos: .userInteractive)

        let watchdogThread = AppHangsWatchdogThread(
            appHangThreshold: appHangThreshold,
            queue: queue,
            dateProvider: SystemDateProvider(),
            backtraceReporter: BacktraceReporterMock(),
            telemetry: TelemetryMock()
        )
        watchdogThread.onHangStarted = { _ in doNotTrackHangs.fulfill() }
        watchdogThread.onHangEnded = { _, _ in doNotTrackHangs.fulfill() }
        watchdogThread.onHangCancelled = { _ in XCTFail("It should not cancel the hang") }
        watchdogThread.start()

        // When (multiple hangs below threshold)
        queue.async {
            Thread.sleep(forTimeInterval: hangDuration)
            queue.async { // async from queue so watchdog thread can interleve with its own tasks
                Thread.sleep(forTimeInterval: hangDuration)
                queue.async {
                    Thread.sleep(forTimeInterval: hangDuration)
                }
            }
        }

        // Then
        waitForExpectations(timeout: hangDuration * 10)
        watchdogThread.cancel()
    }

    func testItTracksHangDateStackAndDuration() {
        let trackHangStart = expectation(description: "track start of App Hang")
        let trackHangEnd = expectation(description: "track end of App Hang")

        // Given
        let appHangThreshold: TimeInterval = 0.5
        let hangDuration: TimeInterval = appHangThreshold * 2
        let queue = DispatchQueue(label: "main-queue", qos: .userInteractive)

        let watchdogThread = AppHangsWatchdogThread(
            appHangThreshold: appHangThreshold,
            queue: queue,
            dateProvider: DateProviderMock(now: .mockDecember15th2019At10AMUTC()),
            backtraceReporter: BacktraceReporterMock(backtrace: .mockWith(stack: "Main thread stack")),
            telemetry: TelemetryMock()
        )
        watchdogThread.onHangStarted = { hang in
            XCTAssertEqual(hang.startDate, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(hang.backtraceResult.stack, "Main thread stack")
            trackHangStart.fulfill()
        }
        watchdogThread.onHangEnded = { hang, duration in
            XCTAssertEqual(hang.startDate, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(hang.backtraceResult.stack, "Main thread stack")
            XCTAssertGreaterThanOrEqual(duration, hangDuration * (1 - AppHangsWatchdogThread.Constants.tolerance))
            XCTAssertLessThanOrEqual(duration, hangDuration * (1 + AppHangsWatchdogThread.Constants.tolerance))
            trackHangEnd.fulfill()
        }
        watchdogThread.onHangCancelled = { _ in XCTFail("It should not cancel the hang") }
        watchdogThread.start()

        // When
        queue.async {
            Thread.sleep(forTimeInterval: hangDuration)
        }

        // Then
        waitForExpectations(timeout: hangDuration * 10)
        watchdogThread.cancel()
    }

    func testWhenBacktraceGenerationIsNotSupported_itTracksAppHangWithErrorMessage() {
        let trackHangStart = expectation(description: "track start of App Hang")
        let trackHangEnd = expectation(description: "track end of App Hang")

        // Given
        let appHangThreshold: TimeInterval = 0.25
        let hangDuration: TimeInterval = appHangThreshold * 2
        let queue = DispatchQueue(label: "main-queue", qos: .userInteractive)

        let watchdogThread = AppHangsWatchdogThread(
            appHangThreshold: appHangThreshold,
            queue: queue,
            dateProvider: DateProviderMock(now: .mockDecember15th2019At10AMUTC()),
            backtraceReporter: BacktraceReporterMock(backtrace: nil), // backtrace generation not supported
            telemetry: TelemetryMock()
        )
        watchdogThread.onHangStarted = { hang in
            XCTAssertEqual(hang.backtraceResult.stack, AppHangsMonitor.Constants.appHangStackNotAvailableErrorMessage)
            trackHangStart.fulfill()
        }
        watchdogThread.onHangEnded = { hang, _ in
            XCTAssertEqual(hang.backtraceResult.stack, AppHangsMonitor.Constants.appHangStackNotAvailableErrorMessage)
            trackHangEnd.fulfill()
        }
        watchdogThread.onHangCancelled = { _ in XCTFail("It should not cancel the hang") }
        watchdogThread.start()

        // When
        queue.async {
            Thread.sleep(forTimeInterval: hangDuration)
        }

        // Then
        waitForExpectations(timeout: hangDuration * 10)
        watchdogThread.cancel()
    }

    func testWhenBacktraceGenerationThrows_itTracksAppHangWithErrorMessage() {
        let trackHangStart = expectation(description: "track start of App Hang")
        let trackHangEnd = expectation(description: "track end of App Hang")

        // Given
        let appHangThreshold: TimeInterval = 0.25
        let hangDuration: TimeInterval = appHangThreshold * 2
        let queue = DispatchQueue(label: "main-queue", qos: .userInteractive)

        let watchdogThread = AppHangsWatchdogThread(
            appHangThreshold: appHangThreshold,
            queue: queue,
            dateProvider: DateProviderMock(now: .mockDecember15th2019At10AMUTC()),
            backtraceReporter: BacktraceReporterMock(backtraceGenerationError: NSError.mockRandom()), // backtrace generation error
            telemetry: TelemetryMock()
        )
        watchdogThread.onHangStarted = { hang in
            XCTAssertEqual(hang.backtraceResult.stack, AppHangsMonitor.Constants.appHangStackGenerationFailedErrorMessage)
            trackHangStart.fulfill()
        }
        watchdogThread.onHangEnded = { hang, _ in
            XCTAssertEqual(hang.backtraceResult.stack, AppHangsMonitor.Constants.appHangStackGenerationFailedErrorMessage)
            trackHangEnd.fulfill()
        }
        watchdogThread.onHangCancelled = { _ in XCTFail("It should not cancel the hang") }
        watchdogThread.start()

        // When
        queue.async {
            Thread.sleep(forTimeInterval: hangDuration)
        }

        // Then
        waitForExpectations(timeout: hangDuration * 10)
        watchdogThread.cancel()
    }

    func testWhenHangDurationExceedsFalsePositiveThreshold_itReportsHangCancellation() {
        let trackHangStart = expectation(description: "track start of App Hang")
        let trackHangCancel = expectation(description: "track cancellation of App Hang")

        // Given
        let appHangThreshold: TimeInterval = 0.5
        let hangDuration: TimeInterval = appHangThreshold * 2
        let queue = DispatchQueue(label: "main-queue", qos: .userInteractive)

        let watchdogThread = AppHangsWatchdogThread(
            appHangThreshold: appHangThreshold,
            queue: queue,
            dateProvider: DateProviderMock(now: .mockDecember15th2019At10AMUTC()),
            backtraceReporter: BacktraceReporterMock(backtrace: .mockWith(stack: "Main thread stack")),
            telemetry: TelemetryMock(),
            falsePositiveThreshold: hangDuration * 0.75
        )
        watchdogThread.onHangStarted = { hang in
            XCTAssertEqual(hang.startDate, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(hang.backtraceResult.stack, "Main thread stack")
            trackHangStart.fulfill()
        }
        watchdogThread.onHangEnded = { _, _ in XCTFail("It should not end the hang") }
        watchdogThread.onHangCancelled = { hang in
            XCTAssertEqual(hang.startDate, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(hang.backtraceResult.stack, "Main thread stack")
            trackHangCancel.fulfill()
        }
        watchdogThread.start()

        // When
        queue.async {
            Thread.sleep(forTimeInterval: hangDuration)
        }

        // Then
        waitForExpectations(timeout: hangDuration * 10)
        watchdogThread.cancel()
    }
}
