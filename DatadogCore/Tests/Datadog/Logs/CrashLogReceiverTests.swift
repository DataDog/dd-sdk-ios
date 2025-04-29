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
let expectation = expectation(description: "Send Event Bypass Consent")
        let core = PassthroughCoreMock(messageReceiver: CrashLogReceiver.mockAny())
        core.onEventWriteContext = { bypassConsent in
            if bypassConsent { expectation.fulfill() }
        }

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

    private let crashReport: DDCrashReport = .mockWith(
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

    private func crashContextWith(lastRUMViewEvent: RUMViewEvent?) -> CrashContext {
        return .mockWith(
            serverTimeOffset: .mockRandom(),
            service: .mockRandom(),
            env: .mockRandom(),
            version: .mockRandom(),
            buildNumber: .mockRandom(),
            device: .mockWith(
                osName: .mockRandom(),
                osVersion: .mockRandom(),
                osBuildNumber: .mockRandom(),
                architecture: .mockRandom()
            ),
            sdkVersion: .mockRandom(),
            userInfo: Bool.random() ? .mockRandom() : .empty,
            networkConnectionInfo: .mockRandom(),
            carrierInfo: .mockRandom(),
            lastRUMViewEvent: lastRUMViewEvent
        )
    }

    private func crashContextWith(lastLogAttributes: AnyCodable?) -> CrashContext {
        return .mockWith(
            serverTimeOffset: .mockRandom(),
            service: .mockRandom(),
            env: .mockRandom(),
            version: .mockRandom(),
            buildNumber: .mockRandom(),
            device: .mockWith(
                osName: .mockRandom(),
                osVersion: .mockRandom(),
                osBuildNumber: .mockRandom(),
                architecture: .mockRandom()
            ),
            sdkVersion: .mockRandom(),
            userInfo: Bool.random() ? .mockRandom() : .empty,
            networkConnectionInfo: .mockRandom(),
            carrierInfo: .mockRandom(),
            lastLogAttributes: lastLogAttributes
        )
    }

    func testWhenSendingCrashReport_itEncodesErrorInformation() throws {
        // Given (CR with no link to RUM view)
        let crashContext = crashContextWith(lastRUMViewEvent: nil) // no RUM view information

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
            date: crashReport.date!.addingTimeInterval(crashContext.serverTimeOffset),
            status: .emergency,
            message: crashReport.message,
            error: .init(
                kind: crashReport.type,
                message: crashReport.message,
                stack: crashReport.stack,
                sourceType: "ios"
            ),
            serviceName: crashContext.service,
            environment: crashContext.env,
            loggerName: "crash-reporter",
            loggerVersion: crashContext.sdkVersion,
            threadName: nil,
            applicationVersion: crashContext.version,
            applicationBuildNumber: crashContext.buildNumber,
            buildId: nil,
            variant: core.context.variant,
            dd: .init(
                device: .init(
                    brand: crashContext.device.brand,
                    name: crashContext.device.name,
                    model: crashContext.device.model,
                    architecture: crashContext.device.architecture
                )
            ),
            os: .init(
                name: crashContext.device.osName,
                version: crashContext.device.osVersion,
                build: crashContext.device.osBuildNumber
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

    // swiftlint:disable multiline_literal_brackets
    func testWhenSendingCrashReportWithRUMContext_itEncodesErrorInformation() throws {
        // Given (CR with the link to RUM view)
        let viewEvent: RUMViewEvent = .mockRandom()

        let crashContext = crashContextWith(lastRUMViewEvent: viewEvent)

        // When
        let core = PassthroughCoreMock(
            messageReceiver: CrashLogReceiver(dateProvider: SystemDateProvider(), logEventMapper: nil)
        )

        let sender = MessageBusSender(core: core)
        sender.send(report: crashReport, with: crashContext)

        // Then
        let log = try XCTUnwrap(core.events(ofType: LogEvent.self).first)

        XCTAssertEqual(log.attributes.internalAttributes?[LogEvent.Attributes.RUM.applicationID] as? String, viewEvent.application.id)
        XCTAssertEqual(log.attributes.internalAttributes?[LogEvent.Attributes.RUM.sessionID] as? String, viewEvent.session.id)
        XCTAssertEqual(log.attributes.internalAttributes?[LogEvent.Attributes.RUM.viewID] as? String, viewEvent.view.id)
        XCTAssertNil(log.attributes.internalAttributes?[LogEvent.Attributes.RUM.actionID])
    }
    // swiftlint:enable multiline_literal_brackets

    func testWhenSendingCrashReportWithSourceType_itEncodesSourceType() throws {
        // Given (CR with the link to RUM view)
        let crashContext = crashContextWith(lastRUMViewEvent: nil)

        // When
        let core = PassthroughCoreMock(
            context: .mockWith(nativeSourceOverride: "ios+il2cpp"),
            messageReceiver: CrashLogReceiver(dateProvider: SystemDateProvider(), logEventMapper: nil)
        )

        let sender = MessageBusSender(core: core)
        sender.send(report: crashReport, with: crashContext)

        // Then
        let log = try XCTUnwrap(core.events(ofType: LogEvent.self).first)

        XCTAssertEqual(log.error?.sourceType, "ios+il2cpp")
    }


    func testWhenSendingCrashContextWithLogAttributes_itSendsThemToLog() throws {
        // Given
        let stringAttribute: String = .mockRandom()
        let boolAttribute: Bool = .mockRandom()
        let crashContext = crashContextWith(lastLogAttributes: .init(
            [
                "mock-string-attribute": stringAttribute,
                "mock-bool-attribute": boolAttribute
            ] as [String: Any]
        ))
        let core = PassthroughCoreMock(
            messageReceiver: CrashLogReceiver(dateProvider: SystemDateProvider(), logEventMapper: nil)
        )
        let sender = MessageBusSender(core: core)

        // When
        sender.send(report: crashReport, with: crashContext)

        // Then
        let log = try XCTUnwrap(core.events(ofType: LogEvent.self).first)

        XCTAssertEqual((log.attributes.userAttributes["mock-string-attribute"] as? AnyCodable)?.value as? String, stringAttribute)
        XCTAssertEqual((log.attributes.userAttributes["mock-bool-attribute"] as? AnyCodable)?.value as? Bool, boolAttribute)
    }

    func testWhenSendingCrashWithLogMapper_itSendsModifiedCrash() throws {
        // Given
        let errorFingerprint: String = .mockRandom()
        let core = PassthroughCoreMock(
            messageReceiver: CrashLogReceiver(
                dateProvider: SystemDateProvider(),
                logEventMapper: SyncLogEventMapper({ event in
                    var event = event
                    event.error?.fingerprint = errorFingerprint
                    return event
                })
            )
        )
        let sender = MessageBusSender(core: core)

        // When
        sender.send(report: crashReport, with: .mockAny())

        // Then
        let log = try XCTUnwrap(core.events(ofType: LogEvent.self).first)

        XCTAssertEqual(log.error?.fingerprint, errorFingerprint)
    }
}
