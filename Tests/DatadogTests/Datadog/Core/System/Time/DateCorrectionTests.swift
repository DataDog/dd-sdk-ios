/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private class ServerDateProviderMock: ServerDateProvider {
    private(set) var update: (TimeInterval) -> Void
    private(set) var completion: (TimeInterval?) -> Void

    init() {
        update = { _ in }
        completion = { _ in }
    }

    func synchronize(update: @escaping (TimeInterval) -> Void, completion:  @escaping (TimeInterval?) -> Void) {
        self.update = update
        self.completion = completion
    }
}

class DateCorrectorTests: XCTestCase {
    func testWhenNTPSynchronizationSucceeds_itPrintsInfoMessage() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let serverDateProvider = ServerDateProviderMock()

        // When
        _ = ServerDateCorrector(serverDateProvider: serverDateProvider)
        serverDateProvider.completion(-1)

        // Then
        XCTAssertEqual(
            dd.logger.debugLog?.message,
            """
            NTP time synchronization completed.
            Server time will be used for signing events (-1.0s difference with device time).
            """
        )
    }

    func testWhenNTPSynchronizationFails_itPrintsWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let serverDateProvider = ServerDateProviderMock()

        // When
        _ = ServerDateCorrector(serverDateProvider: serverDateProvider)
        serverDateProvider.completion(nil)

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
        let serverDateProvider = ServerDateProviderMock()

        // When
        let corrector = ServerDateCorrector(serverDateProvider: serverDateProvider)
        serverDateProvider.completion(nil)

        // Then
        let randomDeviceTime: Date = .mockRandomInThePast()
        XCTAssertEqual(randomDeviceTime.addingTimeInterval(corrector.offset), randomDeviceTime)
    }

    func testWhenServerTimeIsAvailable_itCorrectsDatesByTimeDifference() {
        let serverDateProvider = ServerDateProviderMock()
        let deviceDateProvider = RelativeDateProvider(using: .mockRandomInThePast())

        var serverOffset: TimeInterval = .mockRandomInThePast()

        // When
        let corrector = ServerDateCorrector(serverDateProvider: serverDateProvider)
        serverDateProvider.update(serverOffset)

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
        serverDateProvider.update(serverOffset)

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
        let serverDateProvider = ServerDateProviderMock()
        let corrector = ServerDateCorrector(serverDateProvider: serverDateProvider)
        serverDateProvider.completion(.mockRandomInThePast())

        DispatchQueue.concurrentPerform(iterations: 50) { iteration in
            _ = Date.mockRandomInThePast().addingTimeInterval(corrector.offset)
        }
    }
}
