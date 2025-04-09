/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import DatadogCrashReporting
@testable import TestUtilities

class CrashReportReceiverTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testReceiveCrashEvent() throws {
        // Given
        let receiver: CrashReportReceiver = .mockWith(featureScope: featureScope)

        // When
        let message: FeatureMessage = .baggage(
            key: CrashReportReceiver.MessageKeys.crash,
            value: MessageBusSender.Crash(
                report: DDCrashReport.mockAny(),
                context: CrashContext.mockWith(lastRUMViewEvent: nil)
            )
        )
        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, 1, "It should send error event")
    }

    func testReceiveCrashAndViewEvent() throws {
        // Given
        let receiver: CrashReportReceiver = .mockWith(featureScope: featureScope)
        let lastRUMViewEvent: RUMViewEvent = .mockRandom()

        // When
        let message: FeatureMessage = .baggage(
            key: CrashReportReceiver.MessageKeys.crash,
            value: MessageBusSender.Crash(
                report: DDCrashReport.mockWith(date: Date()),
                context: CrashContext.mockWith(
                    lastRUMViewEvent: AnyCodable(lastRUMViewEvent)
                )
            )
        )
        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, 1, "It should send error event")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMViewEvent.self).count, 1, "It should send view event")
    }

    // MARK: - Testing Conditional Uploads

    func testGivenCrashDuringRUMSessionWithActiveViewCollectedLessThan4HoursAgo_whenSending_itSendsBothRUMErrorAndRUMViewEvent() throws {
        let secondsIn4Hours: TimeInterval = 4 * 60 * 60

        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 0..<secondsIn4Hours))
        let activeRUMView: RUMViewEvent = .mockRandomWith(crashCount: 0)

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(activeRUMView) // means there was a RUM session and it was sampled
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: currentDate),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom() // no matter BET
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "It must send both RUM error and RUM view")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, 1)
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMViewEvent.self).count, 1)
    }

    func testGivenCrashDuringRUMSessionWithActiveViewCollectedLessThan4HoursAgoWithPreviousCrash_whenSending_itSendsNothing() throws {
        let secondsIn4Hours: TimeInterval = 4 * 60 * 60

        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 0..<secondsIn4Hours))
        let activeRUMView: RUMViewEvent = .mockRandomWith(crashCount: 1)

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(activeRUMView) // means there was a RUM session and it was sampled
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: currentDate),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom() // no matter BET
        )

        // When
        XCTAssertFalse(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 0, "It must send no message")
    }

    func testGivenCrashDuringRUMSessionWithActiveViewCollectedMoreThan4HoursAgo_whenSending_itSendsOnlyRUMError() throws {
        let secondsIn4Hours: TimeInterval = 4 * 60 * 60

        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: secondsIn4Hours..<TimeInterval.greatestFiniteMagnitude))
        let activeRUMView: RUMViewEvent = .mockRandomWith(crashCount: 0)

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(activeRUMView) // means there was a RUM session and it was sampled
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: currentDate),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom() // no matter BET
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must send only RUM error")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, 1)
    }

    func testGivenCrashDuringBackgroundRUMSessionWithNoActiveView_whenSending_itSendsBothRUMErrorAndRUMViewEvent() throws {
        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 10..<1_000))
        let activeRUMSessionState: RUMSessionState = .mockRandom()

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no active view in this RUM session
            lastRUMSessionState: AnyCodable(activeRUMSessionState), // means there was RUM session (sampled)
            lastIsAppInForeground: false // app in background
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: currentDate),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: true // BET enabled
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "It must send both RUM error and RUM view")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, 1)
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMViewEvent.self).count, 1)
    }

    func testGivenCrashDuringApplicationLaunch_whenSending_itSendsBothRUMErrorAndRUMViewEvent() throws {
        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 10..<1_000))
        let activeRUMSessionState = Bool.random() ?
            nil : RUMSessionState.mockWith(isInitialSession: true, hasTrackedAnyView: false)

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no active view
            lastRUMSessionState: AnyCodable(activeRUMSessionState), // there was no RUM session OR it was just started w/o yet tracking first view
            lastIsAppInForeground: .mockRandom() // no matter if crashed in foreground or in background
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: currentDate),
            trackBackgroundEvents: true // BET enabled
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "It must send both RUM error and RUM view")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, 1)
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMViewEvent.self).count, 1)
    }

    func testGivenCrashDuringAppLaunchAndNoSampling_whenSending_itIsDropped() throws {
        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 10..<1_000))

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no RUM session
            lastRUMSessionState: nil, // means there was no RUM session
            lastIsAppInForeground: .mockRandom() // no matter if crashed in foreground or in background
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: currentDate),
            sessionSampler: .mockRejectAll() // no sampling (no session should be sent)
        )

        // When
        XCTAssertFalse(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 0, "Crash must not be send as it is rejected by sampler")
    }

    func testGivenCrashDuringAppLaunchInBackgroundAndBETDisabled_whenSending_itIsDropped() throws {
        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let dateCorrectionOffset: TimeInterval = .mockRandom()
        let crashContext: CrashContext = .mockWith(
            serverTimeOffset: dateCorrectionOffset,
            trackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no RUM session (it crashed during app launch)
            lastRUMSessionState: nil, // means there was no RUM session (it crashed during app launch)
            lastIsAppInForeground: false // app was in background
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: crashDate),
            trackBackgroundEvents: false // BET disabled
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 0, "Crash must not be send as it happened in background and BET is disabled")
    }

    func testGivenCrashDuringSampledRUMSession_whenSending_itIsDropped() throws {
        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 10..<1_000))
        let activeRUMSessionState = AnyCodable(
            RUMSessionState.mockWith(
                sessionUUID: .nullUUID, // there was RUM session but it was not sampled
                isInitialSession: .mockRandom(),
                hasTrackedAnyView: false // as it was not sampled, it couldn't track any view
            )
        )

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no active view
            lastRUMSessionState: activeRUMSessionState,
            lastIsAppInForeground: .mockRandom() // no matter if crashed in foreground or in background
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: currentDate),
            sessionSampler: .mockRandom(), // no matter current session sampling
            trackBackgroundEvents: .mockRandom()
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 0, "Crash must not be send as it the session was rejected by sampler")
    }

    // MARK: - Testing Uploaded Data - Crashes During RUM Session With Active View

    func testGivenCrashDuringRUMSessionWithActiveView_whenSendingRUMViewEvent_itIsLinkedToPreviousRUMSessionAndIncludesErrorInformation() throws {
        let lastRUMViewEvent: RUMViewEvent = .mockRandomWith(crashCount: 0)

        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let dateCorrectionOffset: TimeInterval = .mockRandom()
        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            serverTimeOffset: dateCorrectionOffset,
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(lastRUMViewEvent) // means there was a RUM session and it was sampled
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: crashDate),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom() // no matter BET
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        let sendRUMViewEvent = featureScope.eventsWritten(ofType: RUMViewEvent.self)[0]

        XCTAssertTrue(
            sendRUMViewEvent.application.id == lastRUMViewEvent.application.id
            && sendRUMViewEvent.session.id == lastRUMViewEvent.session.id
            && sendRUMViewEvent.view.id == lastRUMViewEvent.view.id,
            "The `RUMViewEvent` sent must be linked to the same RUM Session as the last `RUMViewEvent`."
        )
        DDAssertJSONEqual(sendRUMViewEvent.connectivity, lastRUMViewEvent.connectivity)
        DDAssertJSONEqual(sendRUMViewEvent.usr, lastRUMViewEvent.usr)
        XCTAssertEqual(
            sendRUMViewEvent.view.crash?.count, 1, "The `RUMViewEvent` must include incremented crash count."
        )
        XCTAssertEqual(
            sendRUMViewEvent.dd.documentVersion,
            lastRUMViewEvent.dd.documentVersion + 1,
            "The `RUMViewEvent` sent must contain incremented document version."
        )
        XCTAssertTrue(
            sendRUMViewEvent.view.isActive == false, "The `RUMViewEvent` must be marked as inactive."
        )

        XCTAssertEqual(sendRUMViewEvent.service, lastRUMViewEvent.service)
        XCTAssertEqual(sendRUMViewEvent.version, lastRUMViewEvent.version)
        XCTAssertEqual(sendRUMViewEvent.buildVersion, lastRUMViewEvent.buildVersion)
        XCTAssertEqual(sendRUMViewEvent.view.name, lastRUMViewEvent.view.name)
        XCTAssertEqual(sendRUMViewEvent.view.url, lastRUMViewEvent.view.url)
        XCTAssertEqual(sendRUMViewEvent.view.error.count, lastRUMViewEvent.view.error.count + 1)
        XCTAssertEqual(sendRUMViewEvent.view.resource.count, lastRUMViewEvent.view.resource.count)
        XCTAssertEqual(sendRUMViewEvent.view.action.count, lastRUMViewEvent.view.action.count)
        XCTAssertEqual(
            sendRUMViewEvent.date,
            crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds - 1,
            "The `RUMViewEvent` sent must include crash date corrected by current correction offset and shifted back by 1ms."
        )
        XCTAssertEqual(sendRUMViewEvent.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        DDAssertReflectionEqual(sendRUMViewEvent.device, lastRUMViewEvent.device)
        DDAssertReflectionEqual(sendRUMViewEvent.os, lastRUMViewEvent.os)
    }

    func testGivenCrashDuringRUMSessionWithActiveView_whenSendingRUMErrorEvent_itIsLinkedToPreviousRUMSessionAndIncludesCrashInformation() throws {
        let lastRUMViewEvent: RUMViewEvent = .mockRandomWith(crashCount: 0)

        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let crashReport: DDCrashReport = .mockWith(
            date: crashDate,
            type: "SIG_CODE (SIG_NAME)",
            message: "Signal details",
            stack: """
            0: stack-trace line 0
            1: stack-trace line 1
            2: stack-trace line 2
            """,
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
            )
        )

        let dateCorrectionOffset: TimeInterval = .mockRandom(min: 1, max: 5)
        let crashContext: CrashContext = .mockWith(
            serverTimeOffset: dateCorrectionOffset,
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(lastRUMViewEvent) // means there was a RUM session and it was sampled
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(
                using: crashDate.addingTimeInterval(
                    .mockRandom(min: 10, max: 2 * FatalErrorBuilder.Constants.viewEventAvailabilityThreshold) // simulate restarting app from 10s to 8h later
                )
            ),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom() // no matter BET
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        let sendRUMErrorEvent = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]

        XCTAssertTrue(
            sendRUMErrorEvent.application.id == lastRUMViewEvent.application.id
            && sendRUMErrorEvent.session.id == lastRUMViewEvent.session.id
            && sendRUMErrorEvent.view.id == lastRUMViewEvent.view.id,
            "The `RUMErrorEvent` sent must be linked to the same RUM Session as the last `RUMViewEvent`."
        )

        XCTAssertEqual(sendRUMErrorEvent.view.name, lastRUMViewEvent.view.name, "It must include view attributes")
        XCTAssertEqual(sendRUMErrorEvent.view.referrer, lastRUMViewEvent.view.referrer, "It must include view attributes")
        XCTAssertEqual(sendRUMErrorEvent.view.url, lastRUMViewEvent.view.url, "It must include view attributes")

        XCTAssertNotNil(sendRUMErrorEvent.context, "It must contain context details")
        XCTAssertNotNil(lastRUMViewEvent.context, "It must contain context details")

        DDAssertJSONEqual(
            AnyEncodable(sendRUMErrorEvent.context?.contextInfo),
            AnyEncodable(lastRUMViewEvent.context?.contextInfo),
            "The `RUMErrorEvent` sent must be include the context of the last `RUMViewEvent`."
        )

        XCTAssertTrue(
            sendRUMErrorEvent.error.isCrash == true, "The `RUMErrorEvent` sent must be marked as crash."
        )
        XCTAssertEqual(
            sendRUMErrorEvent.date,
            crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
            "The `RUMErrorEvent` sent must include crash date corrected by current correction offset."
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.type,
            "SIG_CODE (SIG_NAME)"
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.message,
            "Signal details"
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.stack,
            """
            0: stack-trace line 0
            1: stack-trace line 1
            2: stack-trace line 2
            """
        )
        XCTAssertEqual(sendRUMErrorEvent.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        DDAssertJSONEqual(sendRUMErrorEvent.error.threads, crashReport.threads)
        DDAssertJSONEqual(sendRUMErrorEvent.error.binaryImages, crashReport.binaryImages)
        DDAssertJSONEqual(sendRUMErrorEvent.error.meta, crashReport.meta)
        DDAssertJSONEqual(sendRUMErrorEvent.error.wasTruncated, crashReport.wasTruncated)
    }

    func testGivenCrashDuringRUMSessionWithActiveViewAndOverridenSourceType_whenSendingRUMViewEvent_itSendsOverrideSourceType() throws {
        featureScope.contextMock = .mockWith(nativeSourceOverride: "ios+il2cpp")
        let lastRUMViewEvent: RUMViewEvent = .mockRandomWith(crashCount: 0)

        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let dateCorrectionOffset: TimeInterval = .mockRandom()
        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            serverTimeOffset: dateCorrectionOffset,
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(lastRUMViewEvent) // means there was a RUM session and it was sampled
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: crashDate),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom() // no matter BET
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        let sendRUMErrorEvent = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]
        XCTAssertEqual(sendRUMErrorEvent.error.sourceType, .iosIl2cpp, "Must send overridden sourceType")
    }

    func testGivenCrashDuringRUMSessionWithActiveViewAndEventMapper_whenSendingRUMViewEvent_itSendsMappedEvents() throws {
        // Given
        let lastRUMViewEvent: RUMViewEvent = .mockRandomWith(crashCount: 0)
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let dateCorrectionOffset: TimeInterval = .mockRandom()
        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            serverTimeOffset: dateCorrectionOffset,
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(lastRUMViewEvent) // means there was a RUM session and it was sampled
        )

        let modifiedViewName = String.mockRandom()
        let errorFingerprint = String.mockRandom()
        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: crashDate),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom(), // no matter BET
            eventsMapper: .mockWith(
                viewEventMapper: { event in
                    var event = event
                    event.view.name = modifiedViewName
                    return event
                },
                errorEventMapper: { event in
                    var event = event
                    event.error.fingerprint = errorFingerprint
                    return event
                }
            )
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        let sendRUMViewEvent = featureScope.eventsWritten(ofType: RUMViewEvent.self).last
        XCTAssertEqual(sendRUMViewEvent?.view.name, modifiedViewName, "Must send event mapper modified view event")

        let sendRUMErrorEvent = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]
        XCTAssertEqual(sendRUMErrorEvent.error.fingerprint, errorFingerprint, "Must send event mapper modified error event")
    }

    func testGivenCrashDuringRUMSessionWithActiveView_whenErrorMapperReturnsNull_itSendOriginalError() throws {
        let lastRUMViewEvent: RUMViewEvent = .mockRandomWith(crashCount: 0)

        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let crashReport: DDCrashReport = .mockWith(
            date: crashDate,
            type: "SIG_CODE (SIG_NAME)",
            message: "Signal details",
            stack: """
            0: stack-trace line 0
            1: stack-trace line 1
            2: stack-trace line 2
            """,
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
            )
        )

        let dateCorrectionOffset: TimeInterval = .mockRandom(min: 1, max: 5)
        let crashContext: CrashContext = .mockWith(
            serverTimeOffset: dateCorrectionOffset,
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(lastRUMViewEvent) // means there was a RUM session and it was sampled
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(
                using: crashDate.addingTimeInterval(
                    .mockRandom(min: 10, max: 2 * FatalErrorBuilder.Constants.viewEventAvailabilityThreshold) // simulate restarting app from 10s to 8h later
                )
            ),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom(), // no matter BET
            eventsMapper: .mockWith(
                errorEventMapper: { _ in
                    return nil
                }
            )
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        let sendRUMErrorEvent = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]

        XCTAssertTrue(
            sendRUMErrorEvent.application.id == lastRUMViewEvent.application.id
            && sendRUMErrorEvent.session.id == lastRUMViewEvent.session.id
            && sendRUMErrorEvent.view.id == lastRUMViewEvent.view.id,
            "The `RUMErrorEvent` sent must be linked to the same RUM Session as the last `RUMViewEvent`."
        )

        XCTAssertEqual(sendRUMErrorEvent.view.name, lastRUMViewEvent.view.name, "It must include view attributes")
        XCTAssertEqual(sendRUMErrorEvent.view.referrer, lastRUMViewEvent.view.referrer, "It must include view attributes")
        XCTAssertEqual(sendRUMErrorEvent.view.url, lastRUMViewEvent.view.url, "It must include view attributes")

        XCTAssertNotNil(sendRUMErrorEvent.context, "It must contain context details")
        XCTAssertNotNil(lastRUMViewEvent.context, "It must contain context details")

        DDAssertJSONEqual(
            AnyEncodable(sendRUMErrorEvent.context?.contextInfo),
            AnyEncodable(lastRUMViewEvent.context?.contextInfo),
            "The `RUMErrorEvent` sent must be include the context of the last `RUMViewEvent`."
        )

        XCTAssertTrue(
            sendRUMErrorEvent.error.isCrash == true, "The `RUMErrorEvent` sent must be marked as crash."
        )
        XCTAssertEqual(
            sendRUMErrorEvent.date,
            crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
            "The `RUMErrorEvent` sent must include crash date corrected by current correction offset."
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.type,
            "SIG_CODE (SIG_NAME)"
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.message,
            "Signal details"
        )
        XCTAssertEqual(
            sendRUMErrorEvent.error.stack,
            """
            0: stack-trace line 0
            1: stack-trace line 1
            2: stack-trace line 2
            """
        )
        XCTAssertEqual(sendRUMErrorEvent.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        DDAssertJSONEqual(sendRUMErrorEvent.error.threads, crashReport.threads)
        DDAssertJSONEqual(sendRUMErrorEvent.error.binaryImages, crashReport.binaryImages)
        DDAssertJSONEqual(sendRUMErrorEvent.error.meta, crashReport.meta)
        DDAssertJSONEqual(sendRUMErrorEvent.error.wasTruncated, crashReport.wasTruncated)
    }

    func testGivenCrashDuringRUMSessionWithActiveViewAndLastRUMAttributesAvailable_itSendsEventsWithOverridingAttributes() throws {
        let lastRUMViewEvent: RUMViewEvent = .mockRandomWith(crashCount: 0)
        let lastRUMAttributes = GlobalRUMAttributes(attributes: mockRandomAttributes())

        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            trackingConsent: .granted,
            lastRUMViewEvent: AnyCodable(lastRUMViewEvent),
            lastRUMAttributes: lastRUMAttributes
        )

        let receiver: CrashReportReceiver = .mockWith(
            featureScope: featureScope,
            dateProvider: RelativeDateProvider(using: crashDate),
            sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
            trackBackgroundEvents: .mockRandom() // no matter BET
        )

        // When
        XCTAssertTrue(
            receiver.receive(message: .baggage(
                key: MessageBusSender.MessageKeys.crash,
                value: MessageBusSender.Crash(report: crashReport, context: crashContext)
            ), from: NOPDatadogCore())
        )

        // Then
        let sentRUMViewAttributes = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self)[0].context?.contextInfo)
        let sentRUMErrorAttributes = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0].context?.contextInfo)
        DDAssertJSONEqual(sentRUMViewAttributes, lastRUMAttributes.attributes)
        DDAssertJSONEqual(sentRUMErrorAttributes, lastRUMAttributes.attributes)
    }

    // MARK: - Testing Uploaded Data - Crashes During RUM Session With No Active View

    func testGivenCrashDuringRUMSessionWithNoActiveView_whenSendingRUMViewEvent_itIsLinkedToPreviousRUMSessionAndIncludesErrorInformation() throws {
        let randomRUMAppID: String = .mockRandom(among: .alphanumerics)
        let randomNetworkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        let randomCarrierInfo: CarrierInfo = .mockRandom()
        let randomUserInfo: UserInfo = .mockRandom()
        let randomCrashType: String = .mockRandom()
        let randomSource: String = .mockAnySource()
        let randomService: String = .mockRandom()
        let randomVersion: String = .mockRandom()
        let randomBuildNumber: String = .mockRandom()

        func test(
            lastRUMSessionState: RUMSessionState,
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool,
            expectViewName expectedViewName: String,
            expectViewURL expectedViewURL: String
        ) throws {
            let featureScope = FeatureScopeMock()

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: randomCrashType
            )
            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let crashContext: CrashContext = .mockWith(
                serverTimeOffset: dateCorrectionOffset,
                service: randomService,
                version: randomVersion,
                buildNumber: randomBuildNumber,
                source: randomSource,
                trackingConsent: .granted,
                userInfo: randomUserInfo,
                networkConnectionInfo: randomNetworkConnectionInfo,
                carrierInfo: randomCarrierInfo,
                lastRUMViewEvent: nil, // means there was no active RUM view
                lastRUMSessionState: AnyCodable(lastRUMSessionState), // means there was RUM session (sampled)
                lastIsAppInForeground: launchInForeground
            )

            let receiver: CrashReportReceiver = .mockWith(
                featureScope: featureScope,
                applicationID: randomRUMAppID,
                dateProvider: RelativeDateProvider(using: crashDate),
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                trackBackgroundEvents: backgroundEventsTrackingEnabled,
                uuidGenerator: DefaultRUMUUIDGenerator()
            )

            // When
            XCTAssertTrue(
                receiver.receive(message: .baggage(
                    key: MessageBusSender.MessageKeys.crash,
                    value: MessageBusSender.Crash(report: crashReport, context: crashContext)
                ), from: NOPDatadogCore())
            )

            // Then
            let sentRUMView = featureScope.eventsWritten(ofType: RUMViewEvent.self)[0]
            let sentRUMError = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]

            // Assert RUM view properties
            XCTAssertTrue(
                sentRUMView.application.id == randomRUMAppID
                && sentRUMView.session.id == RUMUUID(rawValue: lastRUMSessionState.sessionUUID).toRUMDataFormat
                && sentRUMView.view.id.matches(regex: .uuidRegex),
                "It must send `RUMViewEvent` linked to previous RUM Session"
            )
            DDAssertReflectionEqual(
                sentRUMView.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            DDAssertReflectionEqual(
                sentRUMView.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertEqual(sentRUMView.view.crash?.count, 1, "The view must include 1 crash")
            XCTAssertTrue(sentRUMView.view.isActive == false, "The view must be marked inactive")
            XCTAssertEqual(sentRUMView.view.name, expectedViewName)
            XCTAssertEqual(sentRUMView.view.url, expectedViewURL)
            XCTAssertEqual(sentRUMView.view.error.count, 1, "The view must increase number of errors by 1")
            XCTAssertEqual(sentRUMView.view.resource.count, 0)
            XCTAssertEqual(sentRUMView.view.action.count, 0)
            XCTAssertEqual(sentRUMView.source, .init(rawValue: randomSource))
            XCTAssertEqual(sentRUMView.service, randomService)
            XCTAssertEqual(sentRUMView.version, randomVersion)
            XCTAssertEqual(sentRUMView.buildVersion, randomBuildNumber)
            XCTAssertEqual(
                sentRUMView.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds - 1,
                "The view must include crash date corrected by current correction offset and shifted back by 1ms."
            )
            XCTAssertEqual(sentRUMView.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")

            // Assert RUM error properties
            XCTAssertEqual(sentRUMError.application.id, sentRUMView.application.id, "It must be linked to the same application as RUM view")
            XCTAssertEqual(sentRUMError.session.id, sentRUMView.session.id, "It must be linked to the same session as RUM view")
            XCTAssertEqual(sentRUMError.view.id, sentRUMView.view.id, "It must be linked to the RUM view")
            XCTAssertEqual(sentRUMError.source, .init(rawValue: randomSource), "Must support configured sources")
            XCTAssertEqual(sentRUMError.error.sourceType, .ios, "Must send .ios as the sourceType")
            DDAssertReflectionEqual(
                sentRUMError.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            DDAssertReflectionEqual(
                sentRUMError.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertTrue(sentRUMError.error.isCrash == true, "RUM error must be marked as crash.")
            XCTAssertEqual(
                sentRUMError.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
                "RUM error must include crash date corrected by current correction offset."
            )
            XCTAssertEqual(sentRUMError.error.type, randomCrashType)
            XCTAssertEqual(sentRUMError.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
            XCTAssertNotNil(sentRUMError.error.threads, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.binaryImages, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.meta, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.wasTruncated, "It must contain crash details")
            XCTAssertEqual(sentRUMError.error.category, .exception, "Crashes are considered exceptions")
            XCTAssertNil(sentRUMView.context, "It musn't contain context as there was no last active view")
        }

        try test(
            lastRUMSessionState: .mockWith(isInitialSession: true, hasTrackedAnyView: false), // when initial session with no views history
            launchInForeground: true, // launch in foreground
            backgroundEventsTrackingEnabled: .mockRandom(), // no matter BET
            expectViewName: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            expectViewURL: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL
        )

        try test(
            lastRUMSessionState: .mockRandom(), // any sampled session
            launchInForeground: false, // launch in background
            backgroundEventsTrackingEnabled: true, // BET enabled
            expectViewName: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
            expectViewURL: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
        )
    }

    func testGivenCrashDuringRUMSessionWithNoActiveViewAndOverriddenSourceType_whenSendingRUMViewEvent_itSendsOverridenSourceType() throws {
        func test(
            lastRUMSessionState: RUMSessionState,
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool
        ) throws {
            let mockApplicationId: String = .mockRandom(among: .alphanumerics)
            let featureScope = FeatureScopeMock()
            featureScope.contextMock = .mockWith(nativeSourceOverride: "ios+il2cpp")

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: .mockRandom()
            )
            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let crashContext: CrashContext = .mockWith(
                serverTimeOffset: dateCorrectionOffset,
                service: .mockRandom(),
                version: .mockRandom(),
                buildNumber: .mockRandom(),
                source: .mockRandom(),
                trackingConsent: .granted,
                userInfo: .mockRandom(),
                networkConnectionInfo: .mockRandom(),
                carrierInfo: .mockRandom(),
                lastRUMViewEvent: nil, // means there was no active RUM view
                lastRUMSessionState: AnyCodable(lastRUMSessionState), // means there was RUM session (sampled)
                lastIsAppInForeground: launchInForeground
            )

            let receiver: CrashReportReceiver = .mockWith(
                featureScope: featureScope,
                applicationID: mockApplicationId,
                dateProvider: RelativeDateProvider(using: crashDate),
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                trackBackgroundEvents: backgroundEventsTrackingEnabled,
                uuidGenerator: DefaultRUMUUIDGenerator()
            )

            // When
            XCTAssertTrue(
                receiver.receive(message: .baggage(
                    key: MessageBusSender.MessageKeys.crash,
                    value: MessageBusSender.Crash(report: crashReport, context: crashContext)
                ), from: NOPDatadogCore())
            )

            // Then
            let sentRUMError = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]
            XCTAssertEqual(sentRUMError.error.sourceType, .iosIl2cpp, "Must send overridden sourceType")
        }

        try test(
            lastRUMSessionState: .mockWith(isInitialSession: true, hasTrackedAnyView: false), // when initial session with no views history
            launchInForeground: true, // launch in foreground
            backgroundEventsTrackingEnabled: .mockRandom() // no matter BET
        )

        try test(
            lastRUMSessionState: .mockRandom(), // any sampled session
            launchInForeground: false, // launch in background
            backgroundEventsTrackingEnabled: true // BET enabled
        )
    }

    func testGivenCrashDuringRUMSessionWithNoActiveViewAndEventMapper_whenSendingRUMViewEvent_itSendsMappedEvents() throws {
        func test(
            lastRUMSessionState: RUMSessionState,
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool
        ) throws {
            let featureScope = FeatureScopeMock()

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: .mockRandom()
            )
            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let crashContext: CrashContext = .mockWith(
                serverTimeOffset: dateCorrectionOffset,
                service: .mockRandom(),
                version: .mockRandom(),
                buildNumber: .mockRandom(),
                source: .mockRandom(),
                trackingConsent: .granted,
                userInfo: .mockRandom(),
                networkConnectionInfo: .mockRandom(),
                carrierInfo: .mockRandom(),
                lastRUMViewEvent: nil, // means there was no active RUM view
                lastRUMSessionState: AnyCodable(lastRUMSessionState), // means there was RUM session (sampled)
                lastIsAppInForeground: launchInForeground
            )

            let mappedViewName = String.mockRandom()
            let errorFingerprint = String.mockRandom()
            let receiver: CrashReportReceiver = .mockWith(
                featureScope: featureScope,
                applicationID: .mockRandom(among: .alphanumerics),
                dateProvider: RelativeDateProvider(using: crashDate),
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                trackBackgroundEvents: backgroundEventsTrackingEnabled,
                eventsMapper: .mockWith(
                    viewEventMapper: { event in
                        var event = event
                        event.view.name = mappedViewName
                        return event
                    },
                    errorEventMapper: { event in
                        var event = event
                        event.error.fingerprint = errorFingerprint
                        return event
                    }
                )
            )

            // When
            XCTAssertTrue(
                receiver.receive(message: .baggage(
                    key: MessageBusSender.MessageKeys.crash,
                    value: MessageBusSender.Crash(report: crashReport, context: crashContext)
                ), from: NOPDatadogCore())
            )

            // Then
            let sentRUMView = featureScope.eventsWritten(ofType: RUMViewEvent.self).last
            XCTAssertEqual(sentRUMView?.view.name, mappedViewName, "Must send mapped RUMView event")

            let sentRUMError = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]
            XCTAssertEqual(sentRUMError.error.fingerprint, errorFingerprint, "Must send mapped RUMError event")
        }

        try test(
            lastRUMSessionState: .mockWith(isInitialSession: true, hasTrackedAnyView: false), // when initial session with no views history
            launchInForeground: true, // launch in foreground
            backgroundEventsTrackingEnabled: .mockRandom() // no matter BET
        )

        try test(
            lastRUMSessionState: .mockRandom(), // any sampled session
            launchInForeground: false, // launch in background
            backgroundEventsTrackingEnabled: true // BET enabled
        )
    }

    func testGivenCrashDuringRUMSessionWithNoActiveViewAndLastRUMAttributesAvailable_itSendsEventsWithOverridingAttributes() throws {
        func test(
            lastRUMSessionState: RUMSessionState,
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool
        ) throws {
            let featureScope = FeatureScopeMock()

            // Given
            let lastRUMAttributes = GlobalRUMAttributes(attributes: mockRandomAttributes())
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: .mockRandom()
            )
            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let crashContext: CrashContext = .mockWith(
                serverTimeOffset: dateCorrectionOffset,
                service: .mockRandom(),
                version: .mockRandom(),
                buildNumber: .mockRandom(),
                source: .mockRandom(),
                trackingConsent: .granted,
                userInfo: .mockRandom(),
                networkConnectionInfo: .mockRandom(),
                carrierInfo: .mockRandom(),
                lastRUMViewEvent: nil, // means there was no active RUM view
                lastRUMSessionState: AnyCodable(lastRUMSessionState), // means there was RUM session (sampled)
                lastIsAppInForeground: launchInForeground,
                lastRUMAttributes: lastRUMAttributes
            )

            let receiver: CrashReportReceiver = .mockWith(
                featureScope: featureScope,
                applicationID: .mockRandom(among: .alphanumerics),
                dateProvider: RelativeDateProvider(using: crashDate),
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                trackBackgroundEvents: backgroundEventsTrackingEnabled
            )

            // When
            XCTAssertTrue(
                receiver.receive(message: .baggage(
                    key: MessageBusSender.MessageKeys.crash,
                    value: MessageBusSender.Crash(report: crashReport, context: crashContext)
                ), from: NOPDatadogCore())
            )

            // Then
            let sentRUMViewAttributes = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self)[0].context?.contextInfo)
            let sentRUMErrorAttributes = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0].context?.contextInfo)
            DDAssertJSONEqual(sentRUMViewAttributes, lastRUMAttributes.attributes)
            DDAssertJSONEqual(sentRUMErrorAttributes, lastRUMAttributes.attributes)
        }

        try test(
            lastRUMSessionState: .mockWith(isInitialSession: true, hasTrackedAnyView: false), // when initial session with no views history
            launchInForeground: true, // launch in foreground
            backgroundEventsTrackingEnabled: .mockRandom() // no matter BET
        )

        try test(
            lastRUMSessionState: .mockRandom(), // any sampled session
            launchInForeground: false, // launch in background
            backgroundEventsTrackingEnabled: true // BET enabled
        )
    }

    // MARK: - Testing Uploaded Data - Crashes During App Launch

    func testGivenCrashDuringAppLaunch_whenSending_itIsSendAsRUMErrorInNewRUMSession() throws {
        let randomRUMAppID: String = .mockRandom(among: .alphanumerics)
        let randomNetworkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        let randomCarrierInfo: CarrierInfo = .mockRandom()
        let randomUserInfo: UserInfo = .mockRandom()
        let randomCrashType: String = .mockRandom()

        func test(
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool,
            expectViewName expectedViewName: String,
            expectViewURL expectedViewURL: String
        ) throws {
            let featureScope = FeatureScopeMock()

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: randomCrashType
            )

            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let crashContext: CrashContext = .mockWith(
                serverTimeOffset: dateCorrectionOffset,
                trackingConsent: .granted,
                userInfo: randomUserInfo,
                networkConnectionInfo: randomNetworkConnectionInfo,
                carrierInfo: randomCarrierInfo,
                lastRUMViewEvent: nil, // means there was no RUM session (it crashed during app launch)
                lastRUMSessionState: nil, // means there was no RUM session (it crashed during app launch)
                lastIsAppInForeground: launchInForeground
            )

            let receiver: CrashReportReceiver = .mockWith(
                featureScope: featureScope,
                applicationID: randomRUMAppID,
                dateProvider: RelativeDateProvider(using: crashDate),
                trackBackgroundEvents: backgroundEventsTrackingEnabled,
                uuidGenerator: DefaultRUMUUIDGenerator()
            )

            // When
            XCTAssertTrue(
                receiver.receive(message: .baggage(
                    key: MessageBusSender.MessageKeys.crash,
                    value: MessageBusSender.Crash(report: crashReport, context: crashContext)
                ), from: NOPDatadogCore())
            )

            // Then
            let sentRUMView = featureScope.eventsWritten(ofType: RUMViewEvent.self)[0]
            let sentRUMError = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]

            // Assert RUM view properties
            XCTAssertTrue(
                sentRUMView.application.id == randomRUMAppID
                && sentRUMView.session.id.matches(regex: .uuidRegex)
                && sentRUMView.view.id.matches(regex: .uuidRegex),
                "It must send `RUMViewEvent` linked to new RUM Session"
            )
            DDAssertReflectionEqual(
                sentRUMView.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            DDAssertReflectionEqual(
                sentRUMView.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertEqual(sentRUMView.view.crash?.count, 1, "The view must include 1 crash")
            XCTAssertTrue(sentRUMView.view.isActive == false, "The view must be marked inactive")
            XCTAssertEqual(sentRUMView.view.name, expectedViewName)
            XCTAssertEqual(sentRUMView.view.url, expectedViewURL)
            XCTAssertEqual(sentRUMView.view.error.count, 1, "The view must increase number of errors by 1")
            XCTAssertEqual(sentRUMView.view.resource.count, 0)
            XCTAssertEqual(sentRUMView.view.action.count, 0)
            XCTAssertEqual(
                sentRUMView.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds - 1,
                "The view must include crash date corrected by current correction offset and shifted back by 1ms."
            )
            XCTAssertEqual(sentRUMView.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")

            // Assert RUM error properties
            XCTAssertEqual(sentRUMError.application.id, sentRUMView.application.id, "It must be linked to the same application as RUM view")
            XCTAssertEqual(sentRUMError.session.id, sentRUMView.session.id, "It must be linked to the same session as RUM view")
            XCTAssertEqual(sentRUMError.view.id, sentRUMView.view.id, "It must be linked to the RUM view")
            DDAssertReflectionEqual(
                sentRUMError.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            DDAssertJSONEqual(
                sentRUMError.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertTrue(sentRUMError.error.isCrash == true, "RUM error must be marked as crash.")
            XCTAssertEqual(
                sentRUMError.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
                "RUM error must include crash date corrected by current correction offset."
            )
            XCTAssertEqual(sentRUMError.error.type, randomCrashType)
            XCTAssertEqual(sentRUMError.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
            XCTAssertNotNil(sentRUMError.error.threads, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.binaryImages, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.meta, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.wasTruncated, "It must contain crash details")
            XCTAssertEqual(sentRUMError.error.sourceType, .ios, "Must send .ios as the sourceType")
        }

        try test(
            launchInForeground: true, // launch in foreground
            backgroundEventsTrackingEnabled: .mockRandom(), // no matter BET
            expectViewName: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            expectViewURL: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL
        )

        try test(
            launchInForeground: false, // launch in background
            backgroundEventsTrackingEnabled: true, // BET enabled
            expectViewName: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
            expectViewURL: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
        )
    }

    func testGivenCrashDuringAppLaunchWithNativeSourceType_whenSending_itIsSendsWithNativeSourceType() throws {
        func test(
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool,
            expectViewName expectedViewName: String,
            expectViewURL expectedViewURL: String
        ) throws {
            let featureScope = FeatureScopeMock()
            featureScope.contextMock = .mockWith(nativeSourceOverride: "ios+il2cpp")

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: .mockRandom()
            )

            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let crashContext: CrashContext = .mockWith(
                serverTimeOffset: dateCorrectionOffset,
                trackingConsent: .granted,
                userInfo: .mockRandom(),
                networkConnectionInfo: .mockRandom(),
                carrierInfo: .mockRandom(),
                lastRUMViewEvent: nil, // means there was no RUM session (it crashed during app launch)
                lastRUMSessionState: nil, // means there was no RUM session (it crashed during app launch)
                lastIsAppInForeground: launchInForeground
            )

            let receiver: CrashReportReceiver = .mockWith(
                featureScope: featureScope,
                applicationID: .mockRandom(),
                dateProvider: RelativeDateProvider(using: crashDate),
                trackBackgroundEvents: backgroundEventsTrackingEnabled,
                uuidGenerator: DefaultRUMUUIDGenerator()
            )

            // When
            XCTAssertTrue(
                receiver.receive(message: .baggage(
                    key: MessageBusSender.MessageKeys.crash,
                    value: MessageBusSender.Crash(report: crashReport, context: crashContext)
                ), from: NOPDatadogCore())
            )

            // Then
            let sentRUMError = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]

            XCTAssertEqual(sentRUMError.error.sourceType, .iosIl2cpp, "Must send overridden sourceType")
        }

        try test(
            launchInForeground: true, // launch in foreground
            backgroundEventsTrackingEnabled: .mockRandom(), // no matter BET
            expectViewName: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            expectViewURL: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL
        )

        try test(
            launchInForeground: false, // launch in background
            backgroundEventsTrackingEnabled: true, // BET enabled
            expectViewName: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
            expectViewURL: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
        )
    }

    func testGivenCrashDuringAppLaunchWithEventMappers_whenMapperReturnsNil_itSendsOriginalEvents() throws {
        func test(
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool,
            expectViewName expectedViewName: String,
            expectViewURL expectedViewURL: String
        ) throws {
            let featureScope = FeatureScopeMock()

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: .mockRandom()
            )

            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let randomNetworkConnectionInfo = NetworkConnectionInfo.mockRandom()
            let randomCarrierInfo = CarrierInfo.mockRandom()
            let randomUserInfo = UserInfo.mockRandom()
            let crashContext: CrashContext = .mockWith(
                serverTimeOffset: dateCorrectionOffset,
                trackingConsent: .granted,
                userInfo: randomUserInfo,
                networkConnectionInfo: randomNetworkConnectionInfo,
                carrierInfo: randomCarrierInfo,
                lastRUMViewEvent: nil, // means there was no RUM session (it crashed during app launch)
                lastRUMSessionState: nil, // means there was no RUM session (it crashed during app launch)
                lastIsAppInForeground: launchInForeground
            )

            let mappedViewName = String.mockRandom()
            let receiver: CrashReportReceiver = .mockWith(
                featureScope: featureScope,
                applicationID: .mockRandom(),
                dateProvider: RelativeDateProvider(using: crashDate),
                trackBackgroundEvents: backgroundEventsTrackingEnabled,
                eventsMapper: .mockWith(
                    viewEventMapper: { event in
                        var event = event
                        event.view.name = mappedViewName
                        return event
                    },
                    errorEventMapper: { event in
                        return nil
                    }
                )
            )

            // When
            XCTAssertTrue(
                receiver.receive(message: .baggage(
                    key: MessageBusSender.MessageKeys.crash,
                    value: MessageBusSender.Crash(report: crashReport, context: crashContext)
                ), from: NOPDatadogCore())
            )

            // Then
            let sentRUMView = featureScope.eventsWritten(ofType: RUMViewEvent.self).last
            XCTAssertEqual(sentRUMView?.view.name, mappedViewName, "Must send mapped RUM view event")

            // Sent RUM Error should be unmapped
            let sentRUMError = featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0]
            XCTAssertNil(sentRUMError.error.fingerprint)
            DDAssertReflectionEqual(
                sentRUMError.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            DDAssertJSONEqual(
                sentRUMError.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertTrue(sentRUMError.error.isCrash == true, "RUM error must be marked as crash.")
            XCTAssertEqual(
                sentRUMError.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
                "RUM error must include crash date corrected by current correction offset."
            )
            XCTAssertEqual(sentRUMError.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
            XCTAssertNotNil(sentRUMError.error.threads, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.binaryImages, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.meta, "It must contain crash details")
            XCTAssertNotNil(sentRUMError.error.wasTruncated, "It must contain crash details")
            XCTAssertEqual(sentRUMError.error.sourceType, .ios, "Must send .ios as the sourceType")
        }

        try test(
            launchInForeground: true, // launch in foreground
            backgroundEventsTrackingEnabled: .mockRandom(), // no matter BET
            expectViewName: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            expectViewURL: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL
        )

        try test(
            launchInForeground: false, // launch in background
            backgroundEventsTrackingEnabled: true, // BET enabled
            expectViewName: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
            expectViewURL: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
        )
    }

    func testGivenCrashDuringAppLaunchAndLastRUMAttributesAvailable_itSendsEventsWithOverridingAttributes() throws {
        func test(
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool
        ) throws {
            let featureScope = FeatureScopeMock()
            let lastRUMAttributes = GlobalRUMAttributes(attributes: mockRandomAttributes())

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: .mockRandom()
            )

            let crashContext: CrashContext = .mockWith(
                trackingConsent: .granted,
                lastRUMViewEvent: nil, // means there was no RUM session (it crashed during app launch)
                lastRUMSessionState: nil, // means there was no RUM session (it crashed during app launch)
                lastIsAppInForeground: launchInForeground,
                lastRUMAttributes: lastRUMAttributes
            )

            let receiver: CrashReportReceiver = .mockWith(
                featureScope: featureScope,
                applicationID: .mockRandom(),
                dateProvider: RelativeDateProvider(using: crashDate),
                trackBackgroundEvents: backgroundEventsTrackingEnabled
            )

            // When
            XCTAssertTrue(
                receiver.receive(message: .baggage(
                    key: MessageBusSender.MessageKeys.crash,
                    value: MessageBusSender.Crash(report: crashReport, context: crashContext)
                ), from: NOPDatadogCore())
            )

            // Then
            let sentRUMViewAttributes = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self)[0].context?.contextInfo)
            let sentRUMErrorAttributes = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self)[0].context?.contextInfo)
            DDAssertJSONEqual(sentRUMViewAttributes, lastRUMAttributes.attributes)
            DDAssertJSONEqual(sentRUMErrorAttributes, lastRUMAttributes.attributes)
        }

        try test(
            launchInForeground: true, // launch in foreground
            backgroundEventsTrackingEnabled: .mockRandom() // no matter BET
        )

        try test(
            launchInForeground: false, // launch in background
            backgroundEventsTrackingEnabled: true // BET enabled
        )
    }
}
