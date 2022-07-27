/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LogEventBuilderTests: XCTestCase {
    func testItBuildsLogEventWithLogInformation() throws {
        let randomDate: Date = .mockRandomInThePast()
        let randomLevel: LogLevel = .mockRandom()
        let randomMessage: String = .mockRandom()
        let randomError: DDError = .mockRandom()
        let randomAttributes: LogEvent.Attributes = .mockRandom()
        let randomTags: Set<String> = .mockRandom()
        let randomService: String = .mockRandom()
        let randomLoggerName: String = .mockRandom()
        let randomThreadName: String = .mockRandom()

        // Given
        let builder = LogEventBuilder(
            service: randomService,
            loggerName: randomLoggerName,
            sendNetworkInfo: .mockAny(),
            eventMapper: nil
        )

        // When
        let event = builder.createLogEvent(
            date: randomDate,
            level: randomLevel,
            message: randomMessage,
            error: randomError,
            attributes: randomAttributes,
            tags: randomTags,
            context: .mockWith(dateCorrector: DateCorrectorMock(offset: 0)),
            threadName: randomThreadName
        )
        let log = try XCTUnwrap(event)

        // Then
        XCTAssertEqual(log.date, randomDate)
        XCTAssertEqual(log.status, expectedLogStatus(for: randomLevel))
        XCTAssertEqual(log.message, randomMessage)
        XCTAssertEqual(log.error?.kind, randomError.type)
        XCTAssertEqual(log.error?.message, randomError.message)
        XCTAssertEqual(log.error?.stack, randomError.stack)
        XCTAssertEqual(log.attributes, randomAttributes)
        XCTAssertEqual(log.tags.map { Set($0) }, randomTags)
        XCTAssertEqual(log.serviceName, randomService)
        XCTAssertEqual(log.loggerName, randomLoggerName)
        XCTAssertEqual(log.threadName, randomThreadName)
    }

    func testItBuildsLogEventWithSDKContextInformation() throws {
        let randomDate: Date = .mockRandomInThePast()
        let randomApplicationVersion: String = .mockRandom()
        let randomEnvironment: String = .mockRandom()
        let randomSDKVersion: String = .mockRandom()
        let randomUserInfo: UserInfo = .mockRandom()
        let randomNetworkInfo: NetworkConnectionInfo = .mockRandom()
        let randomCarrierInfo: CarrierInfo = .mockRandom()
        let randomServerOffset: TimeInterval = .mockRandom(min: -10, max: 10)
        let randomSDKContext: DatadogV1Context = .mockWith(
            env: randomEnvironment,
            version: randomApplicationVersion,
            sdkVersion: randomSDKVersion,
            dateCorrector: DateCorrectorMock(offset: randomServerOffset),
            networkConnectionInfoProvider: NetworkConnectionInfoProviderMock(networkConnectionInfo: randomNetworkInfo),
            carrierInfoProvider: CarrierInfoProviderMock(carrierInfo: randomCarrierInfo),
            userInfoProvider: .mockWith(userInfo: randomUserInfo)
        )

        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            sendNetworkInfo: true,
            eventMapper: nil
        )

        // When
        let event = builder.createLogEvent(
            date: randomDate,
            level: .mockAny(),
            message: .mockAny(),
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: randomSDKContext,
            threadName: .mockAny()
        )
        let log = try XCTUnwrap(event)

        // Then
        XCTAssertEqual(log.date, randomDate.addingTimeInterval(randomServerOffset), "It must correct date with server offset")
        XCTAssertEqual(log.environment, randomSDKContext.env)
        XCTAssertEqual(log.applicationVersion, randomSDKContext.version)
        XCTAssertEqual(log.loggerVersion, randomSDKContext.sdkVersion)
        XCTAssertEqual(log.userInfo.id, randomUserInfo.id)
        XCTAssertEqual(log.userInfo.name, randomUserInfo.name)
        XCTAssertEqual(log.userInfo.email, randomUserInfo.email)
        AssertDictionariesEqual(log.userInfo.extraInfo, randomUserInfo.extraInfo)
        XCTAssertEqual(log.networkConnectionInfo, randomNetworkInfo)
        XCTAssertEqual(log.mobileCarrierInfo, randomCarrierInfo)
    }

    func testGivenSendNetworkInfoDisabled_whenBuildingLog_itDoesNotSetConnectionAndCarrierInfo() throws {
        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            sendNetworkInfo: false,
            eventMapper: nil
        )

        // When
        let event = builder.createLogEvent(
            date: .mockAny(),
            level: .mockAny(),
            message: .mockAny(),
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: .mockWith(
                networkConnectionInfoProvider: NetworkConnectionInfoProviderMock(networkConnectionInfo: .mockAny()),
                carrierInfoProvider: CarrierInfoProviderMock(carrierInfo: .mockAny())
            ),
            threadName: .mockAny()
        )
        let log = try XCTUnwrap(event)

        // Then
        XCTAssertNil(log.networkConnectionInfo)
        XCTAssertNil(log.mobileCarrierInfo)
    }

    // MARK: - Events Mapping

    func testGivenBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() throws {
        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            sendNetworkInfo: .mockAny(),
            eventMapper: { log in
                var mutableLog = log
                mutableLog.message = "modified message"
                return mutableLog
            }
        )

        // When
        let event = builder.createLogEvent(
            date: .mockAny(),
            level: .mockAny(),
            message: "original message",
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: .mockAny(),
            threadName: .mockAny()
        )
        let log = try XCTUnwrap(event)

        // Then
        XCTAssertEqual(log.message, "modified message")
    }

    func testGivenBuilderWithEventMapper_whenEventIsDropped_itReturnsNil() throws {
        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            sendNetworkInfo: .mockAny(),
            eventMapper: { _ in
                return nil
            }
        )

        // When
        let event = builder.createLogEvent(
            date: .mockAny(),
            level: .mockAny(),
            message: .mockAny(),
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: .mockAny(),
            threadName: .mockAny()
        )

        // Then
        XCTAssertNil(event)
    }

    // MARK: - Helpers

    private func expectedLogStatus(for logLevel: LogLevel) -> LogEvent.Status {
        switch logLevel {
        case .debug:    return .debug
        case .info:     return .info
        case .notice:   return .notice
        case .warn:     return .warn
        case .error:    return .error
        case .critical: return .critical
        }
    }
}
