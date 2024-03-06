/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogLogs

class LogEventBuilderTests: XCTestCase {
    func testItBuildsLogEventWithLogInformation() throws {
        let expectation = expectation(description: "build log event")

        let randomDate: Date = .mockRandomInThePast()
        let randomLevel: LogLevel = .mockRandom()
        let randomMessage: String = .mockRandom()
        let randomError: DDError = .mockRandom()
        let randomAttributes: LogEvent.Attributes = .mockRandom()
        let randomTags: Set<String> = .mockRandom()
        let randomService: String = .mockRandom()
        let randomLoggerName: String = .mockRandom()
        let randomThreadName: String = .mockRandom()
        let randomOsName: String = .mockRandom()
        let randomOsVersion: String = .mockRandom()
        let randomOsBuildNumber: String = .mockRandom()
        let randomName: String = .mockRandom()
        let randomModel: String = .mockRandom()
        let randomArchitecture: String = .mockRandom()

        // Given
        let builder = LogEventBuilder(
            service: randomService,
            loggerName: randomLoggerName,
            networkInfoEnabled: .mockAny(),
            eventMapper: nil
        )

        // When
        builder.createLogEvent(
            date: randomDate,
            level: randomLevel,
            message: randomMessage,
            error: randomError,
            attributes: randomAttributes,
            tags: randomTags,
            context: .mockWith(
                serverTimeOffset: 0,
                device: .mockWith(
                    name: randomName,
                    model: randomModel,
                    osName: randomOsName,
                    osVersion: randomOsVersion,
                    osBuildNumber: randomOsBuildNumber,
                    architecture: randomArchitecture
                )
            ),
            threadName: randomThreadName
        ) { log in
            // Then
            XCTAssertEqual(log.date, randomDate)
            XCTAssertEqual(log.status, self.expectedLogStatus(for: randomLevel))
            XCTAssertEqual(log.message, randomMessage)
            XCTAssertEqual(log.error?.kind, randomError.type)
            XCTAssertEqual(log.error?.message, randomError.message)
            XCTAssertEqual(log.error?.stack, randomError.stack)
            XCTAssertEqual(log.error?.sourceType, "ios")
            XCTAssertEqual(log.attributes, randomAttributes)
            XCTAssertEqual(log.tags.map { Set($0) }, randomTags)
            XCTAssertEqual(log.serviceName, randomService)
            XCTAssertEqual(log.loggerName, randomLoggerName)
            XCTAssertEqual(log.threadName, randomThreadName)
            XCTAssertEqual(log.dd.device.brand, "Apple")
            XCTAssertEqual(log.dd.device.name, randomName)
            XCTAssertEqual(log.dd.device.model, randomModel)
            XCTAssertEqual(log.dd.device.architecture, randomArchitecture)
            XCTAssertEqual(log.os.name, randomOsName)
            XCTAssertEqual(log.os.version, randomOsVersion)
            XCTAssertEqual(log.os.build, randomOsBuildNumber)

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0)
    }

    func testItBuildsLogEventWithSDKContextInformation() throws {
        let expectation = expectation(description: "build log event")

        let randomDate: Date = .mockRandomInThePast()
        let randomApplicationVersion: String = .mockRandom()
        let randomApplicationBuildNumber: String = .mockRandom()
        let randomEnvironment: String = .mockRandom()
        let randomSDKVersion: String = .mockRandom()
        let randomUserInfo: UserInfo = .mockRandom()
        let randomNetworkInfo: NetworkConnectionInfo = .mockRandom()
        let randomCarrierInfo: CarrierInfo = .mockRandom()
        let randomServerOffset: TimeInterval = .mockRandom(min: -10, max: 10)
        let randomName: String = .mockRandom()
        let randomModel: String = .mockRandom()
        let randomOSVersion: String = .mockRandom()
        let randomOSBuild: String = .mockRandom()

        let randomSDKContext: DatadogContext = .mockWith(
            env: randomEnvironment,
            version: randomApplicationVersion,
            buildNumber: randomApplicationBuildNumber,
            sdkVersion: randomSDKVersion,
            serverTimeOffset: randomServerOffset,
            device: .mockWith(
                name: randomName,
                model: randomModel,
                osVersion: randomOSVersion,
                osBuildNumber: randomOSBuild
            ),
            userInfo: randomUserInfo,
            networkConnectionInfo: randomNetworkInfo,
            carrierInfo: randomCarrierInfo
        )

        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            networkInfoEnabled: true,
            eventMapper: nil
        )

        // When
        builder.createLogEvent(
            date: randomDate,
            level: .mockAny(),
            message: .mockAny(),
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: randomSDKContext,
            threadName: .mockAny()
        ) { log in
            // Then
            XCTAssertEqual(log.date, randomDate.addingTimeInterval(randomServerOffset), "It must correct date with server offset")
            XCTAssertEqual(log.environment, randomSDKContext.env)
            XCTAssertEqual(log.applicationVersion, randomSDKContext.version)
            XCTAssertEqual(log.applicationBuildNumber, randomSDKContext.buildNumber)
            XCTAssertEqual(log.loggerVersion, randomSDKContext.sdkVersion)
            XCTAssertNil(log.buildId)
            XCTAssertEqual(log.userInfo.id, randomUserInfo.id)
            XCTAssertEqual(log.userInfo.name, randomUserInfo.name)
            XCTAssertEqual(log.userInfo.email, randomUserInfo.email)
            DDAssertDictionariesEqual(log.userInfo.extraInfo, randomUserInfo.extraInfo)
            XCTAssertEqual(log.networkConnectionInfo, randomNetworkInfo)
            XCTAssertEqual(log.mobileCarrierInfo, randomCarrierInfo)
            XCTAssertEqual(log.dd.device.brand, "Apple")
            XCTAssertEqual(log.dd.device.name, randomName)
            XCTAssertEqual(log.dd.device.model, randomModel)
            XCTAssertEqual(log.os.version, randomOSVersion)
            XCTAssertEqual(log.os.build, randomOSBuild)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0)
    }

    func testGivenContextWithBuildID_whenBuildingLog_itSetsBuildId() throws {
        // Given
        let buildId: String = .mockRandom()
        let randomSDKContext: DatadogContext = .mockWith(
            buildId: buildId
        )

        // When
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            networkInfoEnabled: true,
            eventMapper: nil
        )

        builder.createLogEvent(
            date: .mockRandom(),
            level: .mockAny(),
            message: .mockAny(),
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: randomSDKContext,
            threadName: .mockAny()
        ) { log in
            XCTAssertEqual(log.buildId, buildId)
        }
    }

    func testGivenSendNetworkInfoDisabled_whenBuildingLog_itDoesNotSetConnectionAndCarrierInfo() throws {
        let expectation = expectation(description: "build log event")

        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            networkInfoEnabled: false,
            eventMapper: nil
        )

        // When
        builder.createLogEvent(
            date: .mockAny(),
            level: .mockAny(),
            message: .mockAny(),
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: .mockWith(
                networkConnectionInfo: .mockAny(),
                carrierInfo: .mockAny()
            ),
            threadName: .mockAny()
        ) { log in
            // Then
            XCTAssertNil(log.networkConnectionInfo)
            XCTAssertNil(log.mobileCarrierInfo)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0)
    }

    // MARK: - Events Mapping

    func testGivenBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() throws {
        let expectation = expectation(description: "build log event")

        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            networkInfoEnabled: .mockAny(),
            eventMapper: SyncLogEventMapper { log in
                var mutableLog = log
                mutableLog.message = "modified message"
                return mutableLog
            }
        )

        // When
        builder.createLogEvent(
            date: .mockAny(),
            level: .mockAny(),
            message: "original message",
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: .mockAny(),
            threadName: .mockAny()
        ) { log in
            // Then
            XCTAssertEqual(log.message, "modified message")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0)
    }

    func testGivenBuilderWithEventMapper_whenEventIsDropped_thenCallbackIsNotCalled() throws {
        let expectation = expectation(description: "build log event")
        expectation.isInverted = true

        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            networkInfoEnabled: .mockAny(),
            eventMapper: SyncLogEventMapper { _ in
                return nil
            }
        )

        // When
        builder.createLogEvent(
            date: .mockAny(),
            level: .mockAny(),
            message: .mockAny(),
            error: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: .mockAny(),
            threadName: .mockAny()
        ) { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0)
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
