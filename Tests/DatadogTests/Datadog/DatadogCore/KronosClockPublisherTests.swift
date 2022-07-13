/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class KronosClockPublisherTests: XCTestCase {
    func testPickRandomDatadogNTPServers() throws {
        let kronos = KronosClockMock()
        let publisher = KronosClockPublisher(kronos: kronos)

        var pools: Set<String> = []

        try (0..<100).forEach { _ in
            publisher.publish { _ in }
            let pool = try XCTUnwrap(kronos.currentPool)
            XCTAssertTrue(pool.hasSuffix(".datadog.pool.ntp.org"))
            pools.insert(pool)
        }

        XCTAssertEqual(pools, Set(DatadogNTPServers), "Each time Datadog NTP server should be picked randomly.")
    }

    func testWhenSyncSucceedsOnce_itPrintsInfoMessage() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let kronos = KronosClockMock()
        let publisher = KronosClockPublisher(kronos: kronos)
        publisher.publish { XCTAssertEqual($0, -1) }
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
    }

    func testWhenSyncFails_itPrintsWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let kronos = KronosClockMock()
        let publisher = KronosClockPublisher(kronos: kronos)
        publisher.publish { XCTAssertEqual($0, 0) }
        kronos.complete()

        // Then
        XCTAssertEqual(
            dd.logger.errorLog?.message,
            """
            NTP time synchronization failed.
            Device time will be used for signing events.
            """
        )
    }
}
