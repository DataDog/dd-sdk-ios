/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

class ServerOffsetSourceTests: XCTestCase {
    func testPickRandomDatadogNTPServers() throws {
        var pools: Set<String> = []

        try (0..<100).forEach { _ in
            let kronos = KronosClockMock()
            let provider = DatadogNTPDateProvider(kronos: kronos)
            _ = ServerOffsetSource(provider: provider)
            let pool = try XCTUnwrap(kronos.currentPool)
            XCTAssertTrue(pool.hasSuffix(".datadog.pool.ntp.org"))
            pools.insert(pool)
        }

        XCTAssertEqual(pools, Set(DatadogNTPServers), "Each time Datadog NTP server should be picked randomly.")
    }

    func testWhenSyncSucceedsOnce_itPublishesOffset() async throws {
        // Given
        let kronos = KronosClockMock()
        let provider = DatadogNTPDateProvider(kronos: kronos)
        let source = ServerOffsetSource(provider: provider)

        var iterator = source.values.makeAsyncIterator()

        // When
        kronos.update(offset: -1)

        // Then
        let value = await iterator.next()
        XCTAssertEqual(value, -1)
    }

    func testWhenSyncCompletesSuccessfully_itPublishesOffset() async throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let kronos = KronosClockMock()
        let provider = DatadogNTPDateProvider(kronos: kronos)
        let source = ServerOffsetSource(provider: provider)

        var iterator = source.values.makeAsyncIterator()

        // When
        kronos.update(offset: -1)
        let firstValue = await iterator.next()
        XCTAssertEqual(firstValue, -1)

        kronos.complete()
        let secondValue = await iterator.next()
        XCTAssertEqual(secondValue, -1)

        // Then
        XCTAssertEqual(
            dd.logger.debugLog?.message,
            """
            NTP time synchronization completed.
            Server time will be used for signing events (-1.0s difference with device time).
            """
        )
    }

    func testWhenSyncFails_itPublishesZero() async throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let kronos = KronosClockMock()
        let provider = DatadogNTPDateProvider(kronos: kronos)
        let source = ServerOffsetSource(provider: provider)

        var iterator = source.values.makeAsyncIterator()

        // When
        kronos.complete()

        // Then
        let value = await iterator.next()
        XCTAssertEqual(value, .zero)

        XCTAssertEqual(
            dd.logger.errorLog?.message,
            """
            NTP time synchronization failed.
            Device time will be used for signing events.
            """
        )
    }
}
