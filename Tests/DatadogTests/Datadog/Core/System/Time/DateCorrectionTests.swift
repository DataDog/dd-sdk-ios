/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DateCorrectorTests: XCTestCase {
    func testWhenInitialized_itSynchronizesWithOneOfDatadogNTPServers() throws {
        let kronos = KronosClockMock()
        let serverDateProvider = DatadogNTPDateProvider(kronos: kronos)

        var randomlyChosenServers: Set<String> = []

        try (0..<100).forEach { _ in
            serverDateProvider.synchronize { _ in }
            let pool = try XCTUnwrap(kronos.currentPool)
            XCTAssertTrue(pool.hasSuffix(".datadog.pool.ntp.org"))
            randomlyChosenServers.insert(pool)
        }

        let allAvailableServers = Set(DatadogNTPServers)
        XCTAssertEqual(randomlyChosenServers, allAvailableServers, "Each time Datadog NTP server should be picked randomly.")
    }

    func testWhenNTPSynchronizationSucceedsOnce_itPrintsInfoMessage() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let kronos = KronosClockMock()
        let serverDateProvider = DatadogNTPDateProvider(kronos: kronos)
        serverDateProvider.synchronize { _ in }
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

    func testWhenNTPSynchronizationSucceeds_itPrintsInfoMessage() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let kronos = KronosClockMock()
        let serverDateProvider = DatadogNTPDateProvider(kronos: kronos)
        serverDateProvider.synchronize { _ in }
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

    func testWhenNTPSynchronizationFails_itPrintsWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let kronos = KronosClockMock()
        let serverDateProvider = DatadogNTPDateProvider(kronos: kronos)
        serverDateProvider.synchronize { _ in }
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

    func testWhenServerTimeIsNotAvailable_itDoesNoCorrection() {
        let kronos = KronosClockMock()
        let serverDateProvider = DatadogNTPDateProvider(kronos: kronos)

        // When
        let corrector = ServerDateCorrector(serverDateProvider: serverDateProvider)
        kronos.complete()

        // Then
        let randomDeviceTime: Date = .mockRandomInThePast()
        XCTAssertEqual(randomDeviceTime.addingTimeInterval(corrector.offset), randomDeviceTime)
    }

    func testWhenServerTimeIsAvailable_itCorrectsDatesByTimeDifference() {
        let deviceDateProvider = RelativeDateProvider(using: .mockRandomInThePast())

        let kronos = KronosClockMock()
        let serverDateProvider = DatadogNTPDateProvider(kronos: kronos)

        // When
        var serverOffset: TimeInterval = .mockRandomInThePast()
        let corrector = ServerDateCorrector(serverDateProvider: serverDateProvider)
        kronos.update(offset: serverOffset)

        // Then
        XCTAssertTrue(
            datesEqual(
                deviceDateProvider.now.addingTimeInterval(corrector.offset),
                deviceDateProvider.now.addingTimeInterval(serverOffset)
            ),
            "The device current time should be corrected to the server time."
        )

        let randomDeviceTime: Date = .mockRandomInThePast()
        XCTAssertTrue(
            datesEqual(
                randomDeviceTime.addingTimeInterval(corrector.offset),
                randomDeviceTime.addingTimeInterval(serverOffset)
            ),
            "Any device time should be corrected by the server-to-device time difference."
        )

        serverOffset = .mockRandomInThePast()
        kronos.update(offset: serverOffset)
        kronos.complete()

        XCTAssertTrue(
            datesEqual(
                randomDeviceTime.addingTimeInterval(corrector.offset),
                randomDeviceTime.addingTimeInterval(serverOffset)
            ),
            "When the server time goes on, any next correction should include new server-to-device time difference."
        )
    }

    /// As we randomize dates in this tests, they must be compared using some granularity, otherwise comparison may fail due to precision error.
    private func datesEqual(_ date1: Date, _ date2: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.compare(date1, to: date2, toGranularity: .nanosecond) == .orderedSame
    }

    // MARK: - Thread Safety

    func testRandomlyCallingCorrectionConcurrentlyDoesNotCrash() {
        let kronos = KronosClockMock()
        let serverDateProvider = DatadogNTPDateProvider(kronos: kronos)
        let corrector = ServerDateCorrector(serverDateProvider: serverDateProvider)
        kronos.update(offset: .mockRandomInThePast())

        DispatchQueue.concurrentPerform(iterations: 50) { iteration in
            _ = Date.mockRandomInThePast().addingTimeInterval(corrector.offset)
        }
    }
}
