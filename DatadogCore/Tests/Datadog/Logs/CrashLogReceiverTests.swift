/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs
@testable import DatadogCore
@testable import DatadogCrashReporting

class CrashLogReceiverTests: XCTestCase {
    func testReceiveCrashLog() throws {
        // Given
        let core = PassthroughCoreMock(
            bypassConsentExpectation: expectation(description: "Send Event Bypass Consent"),
            messageReceiver: CrashLogReceiver.mockAny()
        )

        // When
        core.send(
            message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(
                    report: DDCrashReport.mockAny(),
                    context: CrashContext.mockWith(lastRUMViewEvent: nil)
                )
            )
        )

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertEqual(core.events(ofType: LogEvent.self).count, 1, "It should send log event")
    }

    // MARK: - Testing Conditional Uploads

    func testWhenCrashReportHasUnauthorizedTrackingConsent_itIsNotSent() {
        // Given
        let crashReport: DDCrashReport = .mockWith(date: .mockDecember15th2019At10AMUTC())
        let crashContext: CrashContext = .mockWith(
            trackingConsent: [.pending, .notGranted].randomElement()!
        )

        // When
        let core = PassthroughCoreMock(
            messageReceiver: CrashLogReceiver.mockWith(
                dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
            )
        )
        let sender = MessageBusSender(core: core)
        sender.send(report: crashReport, with: crashContext)

        // Then
        XCTAssertTrue(core.events(ofType: LogEvent.self).isEmpty)
    }

    // MARK: - Testing Uploaded Data

    func testWhenSendingCrashReport_itIncludesAllErrorInformation() throws {
        let dateCorrectionOffset: TimeInterval = .mockRandom()

        // Given
        let crashReport: DDCrashReport = .mockWith(
            date: .mockDecember15th2019At10AMUTC(),
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom(),
            threads: [
                .init(name: "Thread 0", stack: "thread 0 stack", crashed: true, state: nil),
                .init(name: "Thread 1", stack: "thread 1 stack", crashed: false, state: nil),
                .init(name: "Thread 2", stack: "thread 2 stack", crashed: false, state: nil),
            ],
            binaryImages: [
                .init(libraryName: "library1", uuid: "uuid1", architecture: "arch", isSystemLibrary: true, loadAddress: "0xLoad1", maxAddress: "0xMax1"),
                .init(libraryName: "library2", uuid: "uuid2", architecture: "arch", isSystemLibrary: true, loadAddress: "0xLoad2", maxAddress: "0xMax2"),
                .init(libraryName: "library3", uuid: "uuid3", architecture: "arch", isSystemLibrary: false, loadAddress: "0xLoad3", maxAddress: "0xMax3"),
            ],
            meta: .init(
                incidentIdentifier: "incident-identifier",
                process: "process [1]",
                parentProcess: "parent-process [0]",
                path: "process/path",
                codeType: "arch",
                exceptionType: "EXCEPTION_TYPE",
                exceptionCodes: "EXCEPTION_CODES"
            ),
            wasTruncated: false
        )

        let mockArchitecture = String.mockRandom()
        let mockOSName: String = .mockRandom()
        let mockOSVersion: String = .mockRandom()
        let mockOSBuild: String = .mockRandom()

        let crashContext: CrashContext = .mockWith(
            serverTimeOffset: dateCorrectionOffset,
            service: .mockRandom(),
            env: .mockRandom(),
            version: .mockRandom(),
            device: .mockWith(
                name: mockOSName,
                osVersion: mockOSVersion,
                osBuildNumber: mockOSBuild,
                architecture: mockArchitecture
            ),
            sdkVersion: .mockRandom(),
            userInfo: Bool.random() ? .mockRandom() : .empty,
            networkConnectionInfo: .mockRandom(),
            carrierInfo: .mockRandom(),
            lastRUMViewEvent: AnyCodable(mockRandomAttributes())
        )

        // When
        let core = PassthroughCoreMock(
            messageReceiver: CrashLogReceiver.mockWith(
                dateProvider: RelativeDateProvider(using: .mockRandomInThePast())
            )
        )

        let sender = MessageBusSender(core: core)
        sender.send(report: crashReport, with: crashContext)

        // Then
        let log = try XCTUnwrap(core.events(ofType: LogEvent.self).first)
        let user = try XCTUnwrap(crashContext.userInfo)

        let expectedLog = LogEvent(
            date: crashReport.date!.addingTimeInterval(dateCorrectionOffset),
            status: .emergency,
            message: crashReport.message,
            error: .init(
                kind: crashReport.type,
                message: crashReport.message,
                stack: crashReport.stack
            ),
            serviceName: crashContext.service,
            environment: crashContext.env,
            loggerName: "crash-reporter",
            loggerVersion: crashContext.sdkVersion,
            threadName: nil,
            applicationVersion: crashContext.version,
            dd: .init(device: .init(architecture: mockArchitecture)),
            os: .init(
                name: mockOSName,
                version: mockOSVersion,
                build: mockOSBuild
            ),
            userInfo: .init(
                id: user.id,
                name: user.name,
                email: user.email,
                extraInfo: user.extraInfo
            ),
            networkConnectionInfo: crashContext.networkConnectionInfo,
            mobileCarrierInfo: crashContext.carrierInfo,
            attributes: .init(
                userAttributes: [:],
                internalAttributes: [
                    DDError.threads: crashReport.threads,
                    DDError.binaryImages: crashReport.binaryImages,
                    DDError.meta: crashReport.meta,
                    DDError.wasTruncated: false
                ]
            ),
            tags: nil
        )

        DDAssertJSONEqual(expectedLog, log)
    }
}
