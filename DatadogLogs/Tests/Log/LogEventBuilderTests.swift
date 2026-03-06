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
    func testItBuildsLogEventWithLogInformation() async throws {
        let randomDate: Date = .mockRandomInThePast()
        let randomLevel: LogLevel = .mockRandom()
        let randomMessage: String = .mockRandom()
        let randomError: DDError = .mockRandom()
        let randomErrorFingerprint: String? = .mockRandom()
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
        let randomProcessorCount: Double = .mockRandom()
        let randomTotalRam: Double = .mockRandom()

        // Given
        let builder = LogEventBuilder(
            service: randomService,
            loggerName: randomLoggerName,
            networkInfoEnabled: .mockAny(),
            eventMapper: nil
        )

        // When
        let log = await builder.createLogEvent(
            date: randomDate,
            level: randomLevel,
            message: randomMessage,
            error: randomError,
            errorFingerprint: randomErrorFingerprint,
            binaryImages: .mockAny(),
            attributes: randomAttributes,
            tags: randomTags,
            context: .mockWith(
                serverTimeOffset: 0,
                device: .mockWith(
                    name: randomName,
                    model: randomModel,
                    architecture: randomArchitecture,
                    logicalCpuCount: randomProcessorCount,
                    totalRam: randomTotalRam
                ),
                os: .mockWith(
                    name: randomOsName,
                    version: randomOsVersion,
                    build: randomOsBuildNumber
                )
            ),
            threadName: randomThreadName
        ) as! LogEvent

        // Then
        XCTAssertEqual(log.date, randomDate)
        XCTAssertEqual(log.status, expectedLogStatus(for: randomLevel))
        XCTAssertEqual(log.message, randomMessage)
        XCTAssertEqual(log.error?.kind, randomError.type)
        XCTAssertEqual(log.error?.message, randomError.message)
        XCTAssertEqual(log.error?.stack, randomError.stack)
        XCTAssertEqual(log.error?.sourceType, "ios")
        XCTAssertEqual(log.error?.fingerprint, randomErrorFingerprint)
        XCTAssertEqual(log.attributes, randomAttributes)
        XCTAssertEqual(log.tags.map { Set($0) }, randomTags)
        XCTAssertEqual(log.serviceName, randomService)
        XCTAssertEqual(log.loggerName, randomLoggerName)
        XCTAssertEqual(log.threadName, randomThreadName)
        XCTAssertEqual(log.device.brand, "Apple")
        XCTAssertEqual(log.device.name, randomName)
        XCTAssertEqual(log.device.model, randomModel)
        XCTAssertEqual(log.device.architecture, randomArchitecture)
        XCTAssertEqual(log.device.logicalCpuCount, randomProcessorCount)
        XCTAssertEqual(log.device.totalRam, randomTotalRam)
        XCTAssertEqual(log.os.name, randomOsName)
        XCTAssertEqual(log.os.version, randomOsVersion)
        XCTAssertEqual(log.os.build, randomOsBuildNumber)
    }

    func testItBuildsLogEventWithSDKContextInformation() async throws {
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
        let randomProcessorCount: Double = .mockRandom()
        let randomTotalRam: Double = .mockRandom()

        let randomSDKContext: DatadogContext = .mockWith(
            env: randomEnvironment,
            version: randomApplicationVersion,
            buildNumber: randomApplicationBuildNumber,
            sdkVersion: randomSDKVersion,
            serverTimeOffset: randomServerOffset,
            device: .mockWith(
                name: randomName,
                model: randomModel,
                logicalCpuCount: randomProcessorCount,
                totalRam: randomTotalRam
            ),
            os: .mockWith(
                version: randomOSVersion,
                build: randomOSBuild
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
        let log = await builder.createLogEvent(
                date: randomDate,
                level: .mockAny(),
                message: .mockAny(),
                error: .mockAny(),
                errorFingerprint: .mockAny(),
                binaryImages: .mockAny(),
                attributes: .mockAny(),
                tags: .mockAny(),
                context: randomSDKContext,
                threadName: .mockAny()
            ) as! LogEvent

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
        XCTAssertEqual(log.device.brand, "Apple")
        XCTAssertEqual(log.device.name, randomName)
        XCTAssertEqual(log.device.model, randomModel)
        XCTAssertEqual(log.device.logicalCpuCount, randomProcessorCount)
        XCTAssertEqual(log.device.totalRam, randomTotalRam)
        XCTAssertEqual(log.os.version, randomOSVersion)
        XCTAssertEqual(log.os.build, randomOSBuild)
    }

    func testGivenContextWithBuildID_whenBuildingLog_itSetsBuildId() async throws {
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

        let log = await builder.createLogEvent(
                date: .mockRandom(),
                level: .mockAny(),
                message: .mockAny(),
                error: .mockAny(),
                errorFingerprint: .mockAny(),
                binaryImages: .mockAny(),
                attributes: .mockAny(),
                tags: .mockAny(),
                context: randomSDKContext,
                threadName: .mockAny()
            ) as! LogEvent

        // Then
        XCTAssertEqual(log.buildId, buildId)
    }

    func testGivenSendNetworkInfoDisabled_whenBuildingLog_itDoesNotSetConnectionAndCarrierInfo() async throws {
        // Given
        let builder = LogEventBuilder(
            service: .mockAny(),
            loggerName: .mockAny(),
            networkInfoEnabled: false,
            eventMapper: nil
        )

        // When
        let log = try await builder.createLogEvent(
                date: .mockAny(),
                level: .mockAny(),
                message: .mockAny(),
                error: .mockAny(),
                errorFingerprint: .mockAny(),
                binaryImages: .mockAny(),
                attributes: .mockAny(),
                tags: .mockAny(),
                context: .mockWith(
                    networkConnectionInfo: .mockAny(),
                    carrierInfo: .mockAny()
                ),
                threadName: .mockAny()
            ) as! LogEvent

        // Then
        XCTAssertNil(log.networkConnectionInfo)
        XCTAssertNil(log.mobileCarrierInfo)
    }

    // MARK: - Events Mapping

    func testGivenBuilderWithEventMapper_whenEventIsModified_itBuildsModifiedEvent() async throws {
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
        let log = try await builder.createLogEvent(
                date: .mockAny(),
                level: .mockAny(),
                message: "original message",
                error: .mockAny(),
                errorFingerprint: .mockAny(),
                binaryImages: .mockAny(),
                attributes: .mockAny(),
                tags: .mockAny(),
                context: .mockAny(),
                threadName: .mockAny()
            ) as! LogEvent

        // Then
        XCTAssertEqual(log.message, "modified message")
    }

    func testGivenBuilderWithEventMapper_whenEventIsDropped_itReturnsNil() async throws {
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
        let log = await builder.createLogEvent(
            date: .mockAny(),
            level: .mockAny(),
            message: .mockAny(),
            error: .mockAny(),
            errorFingerprint: .mockAny(),
            binaryImages: .mockAny(),
            attributes: .mockAny(),
            tags: .mockAny(),
            context: .mockAny(),
            threadName: .mockAny()
        )

        // Then
        XCTAssertNil(log)
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
