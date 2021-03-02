/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private class ServerDateProviderMock: ServerDateProvider {
    private(set) var synchronizedNTPPool: String? = nil
    var serverTime: Date? = nil

    init(using serverTime: Date? = nil) {
        self.serverTime = serverTime
    }

    func synchronize(with ntpPool: String, completion: @escaping (Date?) -> Void) {
        synchronizedNTPPool = ntpPool
        completion(self.serverTime)
    }

    func currentDate() -> Date? {
        return serverTime
    }
}

class DateCorrectorTests: XCTestCase {
    private var previousUserLogger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional
    private var userLogOutput: LogOutputMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        self.previousUserLogger = userLogger
        self.userLogOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: userLogOutput)
    }

    override func tearDown() {
        userLogger = self.previousUserLogger
        super.tearDown()
    }

    func testWhenInitialized_itSynchronizesWithOneOfDatadogNTPServers() {
        let serverDateProvider = ServerDateProviderMock()
        let deviceDateProvider = SystemDateProvider()

        var randomlyChoosenServers: Set<String> = []

        (0..<100).forEach { _ in
            _ = DateCorrector(deviceDateProvider: deviceDateProvider, serverDateProvider: serverDateProvider)
            randomlyChoosenServers.insert(serverDateProvider.synchronizedNTPPool!)
        }

        let allAvailableServers = Set(DateCorrector.datadogNTPServers)
        XCTAssertEqual(randomlyChoosenServers, allAvailableServers, "Each time Datadog NTP server should be picked randomly.")
    }

    func testWhenNTPSynchronizationSucceeds_itPrintsInfoMessage() throws {
        let serverDateProvider = ServerDateProviderMock(using: .mockDecember15th2019At10AMUTC())
        let deviceDateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1))

        // When
        _ = DateCorrector(deviceDateProvider: deviceDateProvider, serverDateProvider: serverDateProvider)

        // Then
        let log = try XCTUnwrap(userLogOutput.recordedLog)
        XCTAssertEqual(log.status, .info)
        XCTAssertEqual(
            log.message,
            """
            NTP time synchronization completed.
            Server time will be used for signing events (current server time is 2019-12-15 10:00:00 +0000; -1.0s difference with device time).
            """
        )
    }

    func testWhenNTPSynchronizationFails_itPrintsWarning() throws {
        let serverDateProvider = ServerDateProviderMock(using: nil)
        let deviceDateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())

        // When
        _ = DateCorrector(deviceDateProvider: deviceDateProvider, serverDateProvider: serverDateProvider)

        // Then
        let log = try XCTUnwrap(userLogOutput.recordedLog)
        XCTAssertEqual(log.status, .warn)
        XCTAssertEqual(
            log.message,
            """
            NTP time synchronization failed.
            Device time will be used for signing events (current device time is 2019-12-15 10:00:00 +0000).
            """
        )
    }

    func testWhenServerTimeIsNotAvailable_itDoesNoCorrection() {
        let serverDateProvider = ServerDateProviderMock(using: nil)
        let deviceDateProvider = RelativeDateProvider(using: .mockAny())

        // When
        let corrector = DateCorrector(deviceDateProvider: deviceDateProvider, serverDateProvider: serverDateProvider)

        // Then
        let randomDeviceTime: Date = .mockRandomInThePast()
        XCTAssertEqual(corrector.currentCorrection.applying(to: randomDeviceTime), randomDeviceTime)
    }

    func testWhenServerTimeIsAvailable_itCorrectsDatesByTimeDifference() {
        let serverDateProvider = ServerDateProviderMock(using: .mockRandomInThePast())
        let deviceDateProvider = RelativeDateProvider(using: .mockRandomInThePast())

        func currentTimeDifference() -> TimeInterval {
            serverDateProvider.currentDate()!.timeIntervalSince(deviceDateProvider.currentDate())
        }

        // When
        let corrector = DateCorrector(deviceDateProvider: deviceDateProvider, serverDateProvider: serverDateProvider)

        // Then
        XCTAssertTrue(
            datesEqual(
                corrector.currentCorrection.applying(to: deviceDateProvider.currentDate()),
                serverDateProvider.currentDate()!
            ),
            "The device current time should be corrected to the server time."
        )

        let randomDeviceTime: Date = .mockRandomInThePast()
        XCTAssertTrue(
            datesEqual(
                corrector.currentCorrection.applying(to: randomDeviceTime),
                randomDeviceTime.addingTimeInterval(currentTimeDifference())
            ),
            "Any device time should be corrected by the server-to-device time difference."
        )

        serverDateProvider.serverTime = .mockRandomInThePast()
        XCTAssertTrue(
            datesEqual(
                corrector.currentCorrection.applying(to: randomDeviceTime),
                randomDeviceTime.addingTimeInterval(currentTimeDifference())
            ),
            "When the server time goes on, any next correction should include new server-to-device time difference."
        )
    }

    /// As we randomize dates in this tests, they must be compared using some granularity, otherwise comparison may fail due to precission error.
    private func datesEqual(_ date1: Date, _ date2: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.compare(date1, to: date2, toGranularity: .nanosecond) == .orderedSame
    }

    // MARK: - Thread Safety

    func testRandomlyCallingCorrectionConcurrentlyDoesNotCrash() {
        let serverDateProvider = ServerDateProviderMock(using: .mockRandomInThePast())
        let deviceDateProvider = RelativeDateProvider(using: .mockRandomInThePast())
        let corrector = DateCorrector(deviceDateProvider: deviceDateProvider, serverDateProvider: serverDateProvider)

        DispatchQueue.concurrentPerform(iterations: 50) { iteration in
            _ = corrector.currentCorrection.applying(to: .mockRandomInThePast())
        }
    }
}
