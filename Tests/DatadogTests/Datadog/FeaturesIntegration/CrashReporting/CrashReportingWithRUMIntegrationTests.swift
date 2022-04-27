/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CrashReportingWithRUMIntegrationTests: XCTestCase {
    private let rumEventOutput = RUMEventOutputMock()

    // MARK: - Testing Conditional Uploads

    func testGivenCrashDuringRUMSessionWithActiveViewCollectedLessThan4HoursAgo_whenSending_itSendsBothRUMErrorAndRUMViewEvent() throws {
        let secondsIn4Hours: TimeInterval = 4 * 60 * 60

        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 0..<secondsIn4Hours))
        let activeRUMView: RUMViewEvent = .mockRandom()

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: activeRUMView // means there was a RUM session and it was sampled
        )

        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: currentDate),
            dateCorrector: DateCorrectorMock(correctionOffset: 0),
            rumConfiguration: .mockWith(
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                backgroundEventTrackingEnabled: .mockRandom() // no matter BET
            )
        )

        // When
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 2, "It must send both RUM error and RUM view")
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMCrashEvent.self).count, 1)
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMViewEvent.self).count, 1)
    }

    func testGivenCrashDuringRUMSessionWithActiveViewCollectedMoreThan4HoursAgo_whenSending_itSendsOnlyRUMError() throws {
        let secondsIn4Hours: TimeInterval = 4 * 60 * 60

        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: secondsIn4Hours..<TimeInterval.greatestFiniteMagnitude))
        let activeRUMView: RUMViewEvent = .mockRandom()

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: activeRUMView // means there was a RUM session and it was sampled
        )

        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: currentDate),
            dateCorrector: DateCorrectorMock(correctionOffset: 0),
            rumConfiguration: .mockWith(
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                backgroundEventTrackingEnabled: .mockRandom() // no matter BET
            )
        )

        // When
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 1, "It must send only RUM error")
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMCrashEvent.self).count, 1)
    }

    func testGivenCrashDuringBackgroundRUMSessionWithNoActiveView_whenSending_itSendsBothRUMErrorAndRUMViewEvent() throws {
        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 10..<1_000))

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no active view in this RUM session
            lastRUMSessionState: .mockRandom(), // means there was RUM session (sampled)
            lastIsAppInForeground: false // app in background
        )

        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: currentDate),
            dateCorrector: DateCorrectorMock(correctionOffset: 0),
            rumConfiguration: .mockWith(
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                backgroundEventTrackingEnabled: true // BET enabled
            )
        )

        // When
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 2, "It must send both RUM error and RUM view")
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMCrashEvent.self).count, 1)
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMViewEvent.self).count, 1)
    }

    func testGivenCrashDuringApplicationLaunch_whenSending_itSendsBothRUMErrorAndRUMViewEvent() throws {
        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 10..<1_000))

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no active view
            lastRUMSessionState: Bool.random() ? nil : .mockWith(isInitialSession: true, hasTrackedAnyView: false), // there was no RUM session OR it was just started w/o yet tracking first view
            lastIsAppInForeground: .mockRandom() // no matter if crashed in foreground or in background
        )

        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: currentDate),
            dateCorrector: DateCorrectorMock(correctionOffset: 0),
            rumConfiguration: .mockWith(
                sessionSampler: .mockKeepAll(),
                backgroundEventTrackingEnabled: true
            )
        )

        // When
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 2, "It must send both RUM error and RUM view")
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMCrashEvent.self).count, 1)
        XCTAssertEqual(try rumEventOutput.recordedEvents(ofType: RUMViewEvent.self).count, 1)
    }

    func testGivenAnyCrashWithUnauthorizedTrackingConsent_whenSending_itIsDropped() throws {
        // Given
        let crashReport: DDCrashReport = .mockWith(date: .mockDecember15th2019At10AMUTC())
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: [.pending, .notGranted].randomElement()!,
            lastRUMViewEvent: Bool.random() ? .mockRandom() : nil // no matter if in RUM session or not
        )

        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: .mockDecember15th2019At10AMUTC()),
            dateCorrector: DateCorrectorMock(),
            rumConfiguration: .mockWith(
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling
                backgroundEventTrackingEnabled: .mockRandom() // no matter BET
            )
        )

        // When
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 0, "Crash must not be send as it doesn't have `.granted` consent")
    }

    func testGivenCrashDuringAppLaunchAndNoSampling_whenSending_itIsDropped() throws {
        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 10..<1_000))

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no RUM session
            lastRUMSessionState: nil, // means there was no RUM session
            lastIsAppInForeground: .mockRandom() // no matter if crashed in foreground or in background
        )

        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: currentDate),
            dateCorrector: DateCorrectorMock(correctionOffset: 0),
            rumConfiguration: .mockWith(
                sessionSampler: .mockRejectAll(), // no sampling (no session should be sent)
                backgroundEventTrackingEnabled: true
            )
        )

        // When
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 0, "Crash must not be send as it is rejected by sampler")
    }

    func testGivenCrashDuringAppLaunchInBackgroundAndBETDisabled_whenSending_itIsDropped() throws {
        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no RUM session (it crashed during app launch)
            lastRUMSessionState: nil, // means there was no RUM session (it crashed during app launch)
            lastIsAppInForeground: false // app was in background
        )

        let dateCorrectionOffset: TimeInterval = .mockRandom()
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: crashDate),
            dateCorrector: DateCorrectorMock(correctionOffset: dateCorrectionOffset),
            rumConfiguration: .mockWith(
                sessionSampler: .mockKeepAll(),
                backgroundEventTrackingEnabled: false // BET disabled
            )
        )

        // When
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 0, "Crash must not be send as it happened in background and BET is disabled")
    }

    func testGivenCrashDuringSampledRUMSession_whenSending_itIsDropped() throws {
        // Given
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let crashDate: Date = currentDate.secondsAgo(.random(in: 10..<1_000))

        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: nil, // means there was no active view
            lastRUMSessionState: .mockWith(
                sessionUUID: .nullUUID, // there was RUM session but it was not sampled
                isInitialSession: .mockRandom(),
                hasTrackedAnyView: false // as it was not sampled, it couldn't track any view
            ),
            lastIsAppInForeground: .mockRandom() // no matter if crashed in foreground or in background
        )

        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: currentDate),
            dateCorrector: DateCorrectorMock(correctionOffset: 0),
            rumConfiguration: .mockWith(
                sessionSampler: .mockRandom(), // no matter current session sampling
                backgroundEventTrackingEnabled: .mockRandom()
            )
        )

        // When
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        XCTAssertEqual(rumEventOutput.recordedEvents.count, 0, "Crash must not be send as it the session was rejected by sampler")
    }

    // MARK: - Testing Uploaded Data - Crashes During RUM Session With Active View

    func testGivenCrashDuringRUMSessionWithActiveView_whenSendingRUMViewEvent_itIsLinkedToPreviousRUMSessionAndIncludesErrorInformation() throws {
        let lastRUMViewEvent: RUMViewEvent = .mockRandom()

        // Given
        let crashDate: Date = .mockDecember15th2019At10AMUTC()
        let crashReport: DDCrashReport = .mockWith(date: crashDate)
        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: lastRUMViewEvent // means there was a RUM session and it was sampled
        )

        // When
        let dateCorrectionOffset: TimeInterval = .mockRandom()
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(using: crashDate),
            dateCorrector: DateCorrectorMock(correctionOffset: dateCorrectionOffset),
            rumConfiguration: .mockWith(
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                backgroundEventTrackingEnabled: .mockRandom() // no matter BET
            )
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        let sendRUMViewEvent = try rumEventOutput.recordedEvents(ofType: RUMViewEvent.self)[0]

        XCTAssertTrue(
            sendRUMViewEvent.application.id == lastRUMViewEvent.application.id
            && sendRUMViewEvent.session.id == lastRUMViewEvent.session.id
            && sendRUMViewEvent.view.id == lastRUMViewEvent.view.id,
            "The `RUMViewEvent` sent must be linked to the same RUM Session as the last `RUMViewEvent`."
        )
        XCTAssertEqual(sendRUMViewEvent.connectivity, lastRUMViewEvent.connectivity)
        XCTAssertEqual(sendRUMViewEvent.usr, lastRUMViewEvent.usr)
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
        XCTAssertEqual(sendRUMViewEvent.view.name, lastRUMViewEvent.view.name)
        XCTAssertEqual(sendRUMViewEvent.view.url, lastRUMViewEvent.view.url)
        XCTAssertEqual(sendRUMViewEvent.view.error.count, lastRUMViewEvent.view.error.count)
        XCTAssertEqual(sendRUMViewEvent.view.resource.count, lastRUMViewEvent.view.resource.count)
        XCTAssertEqual(sendRUMViewEvent.view.action.count, lastRUMViewEvent.view.action.count)
        XCTAssertEqual(
            sendRUMViewEvent.date,
            crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds - 1,
            "The `RUMViewEvent` sent must include crash date corrected by current correction offset and shifted back by 1ms."
        )
        XCTAssertEqual(sendRUMViewEvent.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
    }

    func testGivenCrashDuringRUMSessionWithActiveView_whenSendingRUMErrorEvent_itIsLinkedToPreviousRUMSessionAndIncludesCrashInformation() throws {
        let lastRUMViewEvent: RUMViewEvent = .mockRandom()

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
                processName: "process-name",
                parentProcess: "parent-process",
                path: "process/path",
                codeType: "arch",
                exceptionType: "EXCEPTION_TYPE",
                exceptionCodes: "EXCEPTION_CODES"
            )
        )

        let crashContext: CrashContext = .mockWith(
            lastTrackingConsent: .granted,
            lastRUMViewEvent: lastRUMViewEvent // means there was a RUM session and it was sampled
        )

        // When
        let dateCorrectionOffset: TimeInterval = .mockRandom(min: 1, max: 5)
        let integration = CrashReportingWithRUMIntegration(
            rumEventOutput: rumEventOutput,
            dateProvider: RelativeDateProvider(
                using: crashDate.addingTimeInterval(
                    .mockRandom(min: 10, max: 2 * CrashReportingWithRUMIntegration.Constants.viewEventAvailabilityThreshold) // simulate restarting app from 10s to 8h later
                )
            ),
            dateCorrector: DateCorrectorMock(correctionOffset: dateCorrectionOffset),
            rumConfiguration: .mockWith(
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled)
                backgroundEventTrackingEnabled: .mockRandom() // no matter BET
            )
        )
        integration.send(crashReport: crashReport, with: crashContext)

        // Then
        let sendRUMErrorEvent = try rumEventOutput.recordedEvents(ofType: RUMCrashEvent.self)[0]

        XCTAssertTrue(
            sendRUMErrorEvent.model.application.id == lastRUMViewEvent.application.id
            && sendRUMErrorEvent.model.session.id == lastRUMViewEvent.session.id
            && sendRUMErrorEvent.model.view.id == lastRUMViewEvent.view.id,
            "The `RUMErrorEvent` sent must be linked to the same RUM Session as the last `RUMViewEvent`."
        )
        XCTAssertTrue(
            sendRUMErrorEvent.model.error.isCrash == true, "The `RUMErrorEvent` sent must be marked as crash."
        )
        XCTAssertEqual(
            sendRUMErrorEvent.model.date,
            crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
            "The `RUMErrorEvent` sent must include crash date corrected by current correction offset."
        )
        XCTAssertEqual(
            sendRUMErrorEvent.model.error.type,
            "SIG_CODE (SIG_NAME)"
        )
        XCTAssertEqual(
            sendRUMErrorEvent.model.error.message,
            "Signal details"
        )
        XCTAssertEqual(
            sendRUMErrorEvent.model.error.stack,
            """
            0: stack-trace line 0
            1: stack-trace line 1
            2: stack-trace line 2
            """
        )
        XCTAssertEqual(sendRUMErrorEvent.model.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(sendRUMErrorEvent.additionalAttributes?[DDError.threads] as? [DDCrashReport.Thread], crashReport.threads)
        XCTAssertEqual(sendRUMErrorEvent.additionalAttributes?[DDError.binaryImages] as? [DDCrashReport.BinaryImage], crashReport.binaryImages)
        XCTAssertEqual(sendRUMErrorEvent.additionalAttributes?[DDError.meta] as? DDCrashReport.Meta, crashReport.meta)
        XCTAssertEqual(sendRUMErrorEvent.additionalAttributes?[DDError.wasTruncated] as? Bool, crashReport.wasTruncated)
    }

    // MARK: - Testing Uploaded Data - Crashes During RUM Session With No Active View

    func testGivenCrashDuringRUMSessionWithNoActiveView_whenSendingRUMViewEvent_itIsLinkedToPreviousRUMSessionAndIncludesErrorInformation() throws {
        let randomRUMAppID: String = .mockRandom(among: .alphanumerics)
        let randomNetworkConnectionInfo: NetworkConnectionInfo = .mockRandom()
        let randomCarrierInfo: CarrierInfo = .mockRandom()
        let randomUserInfo: UserInfo = .mockRandom()
        let randomCrashType: String = .mockRandom()
        let randomSource: String = .mockAnySource()

        func test(
            lastRUMSessionState: RUMSessionState,
            launchInForeground: Bool,
            backgroundEventsTrackingEnabled: Bool,
            expectViewName expectedViewName: String,
            expectViewURL expectedViewURL: String
        ) throws {
            let rumEventOutput = RUMEventOutputMock()

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: randomCrashType
            )
            let crashContext: CrashContext = .mockWith(
                lastTrackingConsent: .granted,
                lastUserInfo: randomUserInfo,
                lastRUMViewEvent: nil, // means there was no active RUM view
                lastNetworkConnectionInfo: randomNetworkConnectionInfo,
                lastCarrierInfo: randomCarrierInfo,
                lastRUMSessionState: lastRUMSessionState, // means there was RUM session (sampled)
                lastIsAppInForeground: launchInForeground
            )

            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let integration = CrashReportingWithRUMIntegration(
                rumEventOutput: rumEventOutput,
                dateProvider: RelativeDateProvider(using: crashDate),
                dateCorrector: DateCorrectorMock(correctionOffset: dateCorrectionOffset),
                rumConfiguration: .mockWith(
                    common: .mockWith(
                        source: randomSource
                    ),
                    applicationID: randomRUMAppID,
                    sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter sampling (as previous session was sampled),
                    backgroundEventTrackingEnabled: backgroundEventsTrackingEnabled
                )
            )

            // When
            integration.send(crashReport: crashReport, with: crashContext)

            // Then
            let sentRUMView = try rumEventOutput.recordedEvents(ofType: RUMViewEvent.self)[0]
            let sentRUMError = try rumEventOutput.recordedEvents(ofType: RUMCrashEvent.self)[0]

            // Assert RUM view properties
            XCTAssertTrue(
                sentRUMView.application.id == randomRUMAppID
                && sentRUMView.session.id == RUMUUID(rawValue: lastRUMSessionState.sessionUUID).toRUMDataFormat
                && sentRUMView.view.id.matches(regex: .uuidRegex),
                "It must send `RUMViewEvent` linked to previous RUM Session"
            )
            XCTAssertEqual(
                sentRUMView.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            XCTAssertEqual(
                sentRUMView.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertEqual(sentRUMView.view.crash?.count, 1, "The view must include 1 crash")
            XCTAssertTrue(sentRUMView.view.isActive == false, "The view must be marked inactive")
            XCTAssertEqual(sentRUMView.view.name, expectedViewName)
            XCTAssertEqual(sentRUMView.view.url, expectedViewURL)
            XCTAssertEqual(sentRUMView.view.error.count, 0)
            XCTAssertEqual(sentRUMView.view.resource.count, 0)
            XCTAssertEqual(sentRUMView.view.action.count, 0)
            XCTAssertEqual(sentRUMView.source, RUMViewEvent.Source(rawValue: randomSource))
            XCTAssertEqual(
                sentRUMView.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds - 1,
                "The view must include crash date corrected by current correction offset and shifted back by 1ms."
            )
            XCTAssertEqual(sentRUMView.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")

            // Assert RUM error properties
            XCTAssertEqual(sentRUMError.model.application.id, sentRUMView.application.id, "It must be linked to the same application as RUM view")
            XCTAssertEqual(sentRUMError.model.session.id, sentRUMView.session.id, "It must be linked to the same session as RUM view")
            XCTAssertEqual(sentRUMError.model.view.id, sentRUMView.view.id, "It must be linked to the RUM view")
            XCTAssertEqual(sentRUMError.model.source, RUMErrorEvent.Source(rawValue: randomSource), "Must support configured sources")
            XCTAssertEqual(sentRUMError.model.error.sourceType, .ios, "Must send .ios as the sourceType")
            XCTAssertEqual(
                sentRUMError.model.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            XCTAssertEqual(
                sentRUMError.model.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertTrue(sentRUMError.model.error.isCrash == true, "RUM error must be marked as crash.")
            XCTAssertEqual(
                sentRUMError.model.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
                "RUM error must include crash date corrected by current correction offset."
            )
            XCTAssertEqual(sentRUMError.model.error.type, randomCrashType)
            XCTAssertEqual(sentRUMError.model.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
            XCTAssertNotNil(sentRUMError.additionalAttributes?[DDError.threads], "It must contain crash details")
            XCTAssertNotNil(sentRUMError.additionalAttributes?[DDError.binaryImages], "It must contain crash details")
            XCTAssertNotNil(sentRUMError.additionalAttributes?[DDError.meta], "It must contain crash details")
            XCTAssertNotNil(sentRUMError.additionalAttributes?[DDError.wasTruncated], "It must contain crash details")
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
            let rumEventOutput = RUMEventOutputMock()

            // Given
            let crashDate: Date = .mockDecember15th2019At10AMUTC()
            let crashReport: DDCrashReport = .mockWith(
                date: crashDate,
                type: randomCrashType
            )
            let crashContext: CrashContext = .mockWith(
                lastTrackingConsent: .granted,
                lastUserInfo: randomUserInfo,
                lastRUMViewEvent: nil, // means there was no RUM session (it crashed during app launch)
                lastNetworkConnectionInfo: randomNetworkConnectionInfo,
                lastCarrierInfo: randomCarrierInfo,
                lastRUMSessionState: nil, // means there was no RUM session (it crashed during app launch)
                lastIsAppInForeground: launchInForeground
            )

            let dateCorrectionOffset: TimeInterval = .mockRandom()
            let integration = CrashReportingWithRUMIntegration(
                rumEventOutput: rumEventOutput,
                dateProvider: RelativeDateProvider(using: crashDate),
                dateCorrector: DateCorrectorMock(correctionOffset: dateCorrectionOffset),
                rumConfiguration: .mockWith(
                    applicationID: randomRUMAppID,
                    sessionSampler: .mockKeepAll(),
                    backgroundEventTrackingEnabled: backgroundEventsTrackingEnabled
                )
            )

            // When
            integration.send(crashReport: crashReport, with: crashContext)

            // Then
            let sentRUMView = try rumEventOutput.recordedEvents(ofType: RUMViewEvent.self)[0]
            let sentRUMError = try rumEventOutput.recordedEvents(ofType: RUMCrashEvent.self)[0]

            // Assert RUM view properties
            XCTAssertTrue(
                sentRUMView.application.id == randomRUMAppID
                && sentRUMView.session.id.matches(regex: .uuidRegex)
                && sentRUMView.view.id.matches(regex: .uuidRegex),
                "It must send `RUMViewEvent` linked to new RUM Session"
            )
            XCTAssertEqual(
                sentRUMView.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            XCTAssertEqual(
                sentRUMView.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertEqual(sentRUMView.view.crash?.count, 1, "The view must include 1 crash")
            XCTAssertTrue(sentRUMView.view.isActive == false, "The view must be marked inactive")
            XCTAssertEqual(sentRUMView.view.name, expectedViewName)
            XCTAssertEqual(sentRUMView.view.url, expectedViewURL)
            XCTAssertEqual(sentRUMView.view.error.count, 0)
            XCTAssertEqual(sentRUMView.view.resource.count, 0)
            XCTAssertEqual(sentRUMView.view.action.count, 0)
            XCTAssertEqual(
                sentRUMView.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds - 1,
                "The view must include crash date corrected by current correction offset and shifted back by 1ms."
            )
            XCTAssertEqual(sentRUMView.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")

            // Assert RUM error properties
            XCTAssertEqual(sentRUMError.model.application.id, sentRUMView.application.id, "It must be linked to the same application as RUM view")
            XCTAssertEqual(sentRUMError.model.session.id, sentRUMView.session.id, "It must be linked to the same session as RUM view")
            XCTAssertEqual(sentRUMError.model.view.id, sentRUMView.view.id, "It must be linked to the RUM view")
            XCTAssertEqual(
                sentRUMError.model.connectivity,
                RUMConnectivity(networkInfo: randomNetworkConnectionInfo, carrierInfo: randomCarrierInfo),
                "It must contain connectity info from the moment of crash"
            )
            XCTAssertEqual(
                sentRUMError.usr,
                RUMUser(userInfo: randomUserInfo),
                "It must contain user info from the moment of crash"
            )
            XCTAssertTrue(sentRUMError.model.error.isCrash == true, "RUM error must be marked as crash.")
            XCTAssertEqual(
                sentRUMError.model.date,
                crashDate.addingTimeInterval(dateCorrectionOffset).timeIntervalSince1970.toInt64Milliseconds,
                "RUM error must include crash date corrected by current correction offset."
            )
            XCTAssertEqual(sentRUMError.model.error.type, randomCrashType)
            XCTAssertEqual(sentRUMError.model.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
            XCTAssertNotNil(sentRUMError.additionalAttributes?[DDError.threads], "It must contain crash details")
            XCTAssertNotNil(sentRUMError.additionalAttributes?[DDError.binaryImages], "It must contain crash details")
            XCTAssertNotNil(sentRUMError.additionalAttributes?[DDError.meta], "It must contain crash details")
            XCTAssertNotNil(sentRUMError.additionalAttributes?[DDError.wasTruncated], "It must contain crash details")
            XCTAssertEqual(sentRUMError.model.error.sourceType, .ios, "Must send .ios as the sourceType")
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
}
