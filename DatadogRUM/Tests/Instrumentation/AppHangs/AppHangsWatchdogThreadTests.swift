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
    func testWhenQueueHangsAboveThreshold_itReportsAppHangs() {
        let trackHangs = expectation(description: "track 3 App Hangs")
        trackHangs.expectedFulfillmentCount = 3

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
        watchdogThread.onHangEnded = { _ in
            trackHangs.fulfill()
        }
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
        watchdogThread.onHangEnded = { _ in
            doNotTrackHangs.fulfill()
        }
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
        let trackHang = expectation(description: "track App Hang")

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
        watchdogThread.onHangEnded = { hang in
            XCTAssertEqual(hang.date, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(hang.backtrace?.stack, "Main thread stack")
            XCTAssertGreaterThanOrEqual(hang.duration, hangDuration * (1 - AppHangsWatchdogThread.Constants.tolerance))
            XCTAssertLessThanOrEqual(hang.duration, hangDuration * (1 + AppHangsWatchdogThread.Constants.tolerance))
            trackHang.fulfill()
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
