/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class ServerOffsetPublisherTests: XCTestCase {
    func testPickRandomDatadogNTPServers() throws {
        let kronos = KronosClockMock()
        let provider = DatadogNTPDateProvider(kronos: kronos)
        let publisher = ServerOffsetPublisher(provider: provider)

        var pools: Set<String> = []

        try (0..<100).forEach { _ in
            publisher.publish { _ in }
            let pool = try XCTUnwrap(kronos.currentPool)
            XCTAssertTrue(pool.hasSuffix(".datadog.pool.ntp.org"))
            pools.insert(pool)
        }

        XCTAssertEqual(pools, Set(DatadogNTPServers), "Each time Datadog NTP server should be picked randomly.")
    }

    func testWhenSyncSucceedsOnce_itPublishesOffset() throws {
        let expectation = expectation(description: "kronos publisher publishes offset")

        // Given
        let kronos = KronosClockMock()
        let provider = DatadogNTPDateProvider(kronos: kronos)
        let publisher = ServerOffsetPublisher(provider: provider)

        // When
        publisher.publish {
            // Then
            XCTAssertEqual($0, -1)
            expectation.fulfill()
        }

        kronos.update(offset: -1)

        // KronosClockMock publishes in sync
        waitForExpectations(timeout: 0)
    }

    func testWhenSyncCompletesSuccessfully_itPublishesOffset() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let expectation = expectation(description: "kronos publisher publishes offset")
        expectation.expectedFulfillmentCount = 2

        // Given
        let kronos = KronosClockMock()
        let provider = DatadogNTPDateProvider(kronos: kronos)
        let publisher = ServerOffsetPublisher(provider: provider)

        // When
        publisher.publish {
            // Then
            XCTAssertEqual($0, -1)
            expectation.fulfill()
        }

        kronos.update(offset: -1)
        kronos.complete()

        // Then
        XCTAssertEqual(
            dd.logger.debugLog?.message,
            """
            NTP time synchronization completed.
            Server time will be used for signing events (-1.0s difference with device time).
            """
        )

        // KronosClockMock publishes in sync
        waitForExpectations(timeout: 0)
    }

    func testWhenSyncFails_itPublishesZero() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let expectation = expectation(description: "kronos publisher publishes 0")

        // Given
        let kronos = KronosClockMock()
        let provider = DatadogNTPDateProvider(kronos: kronos)
        let publisher = ServerOffsetPublisher(provider: provider)

        // When
        publisher.publish {
            // Then
            XCTAssertEqual($0, .zero)
            expectation.fulfill()
        }

        kronos.complete()

        // Then
        XCTAssertEqual(
            dd.logger.errorLog?.message,
            """
            NTP time synchronization failed.
            Device time will be used for signing events.
            """
        )

        // KronosClockMock publishes in sync
        waitForExpectations(timeout: 0)
    }
}
