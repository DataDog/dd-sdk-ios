/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

private class WatchdogThreadMock: AppHangsObservingThread {
    var started: Bool?
    weak var delegate: AppHangsObservingThreadDelegate?

    func start(with delegate: AppHangsObservingThreadDelegate) {
        started = true
        self.delegate = delegate
    }
    func stop() { started = false }
    func flush() {}
}

class AppHangsMonitorTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private let watchdogThread = WatchdogThreadMock()
    private let fatalErrorContext = FatalErrorContextNotifier(messageBus: NOPFeatureScope())
    private let currentProcessID = UUID()
    private let dateProvider = DateProviderMock()
    private var dd: DDMock<CoreLoggerMock>! // swiftlint:disable:this implicitly_unwrapped_optional
    private var monitor: AppHangsMonitor! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        dd = DD.mockWith(logger: CoreLoggerMock())
        monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: currentProcessID,
            dateProvider: dateProvider
        )
    }

    override func tearDown() {
        monitor = nil
        dd.reset()
    }

    func testStartAndStop() throws {
        // Given
        XCTAssertNil(watchdogThread.started)

        // When, Then
        monitor.start()
        XCTAssertEqual(watchdogThread.started, true)

        // When, Then
        monitor.stop()
        XCTAssertEqual(watchdogThread.started, false)
    }

    // MARK: - Non-Fatal App Hangs Monitoring

    func testWhenAppHangEnds_itSendsAppHangCommand() throws {
        // Given
        let subscriber = RUMCommandSubscriberMock()
        monitor.nonFatalHangsHandler.publish(to: subscriber)
        monitor.start()
        defer { monitor.stop() }

        // When
        let hang: AppHang = .mockRandom()
        let duration: TimeInterval = .mockRandom(min: 1, max: 4)
        watchdogThread.delegate?.hangEnded(hang, duration: duration)

        // Then
        let command = try XCTUnwrap(subscriber.lastReceivedCommand as? RUMAddCurrentViewAppHangCommand)
        XCTAssertEqual(command.time, hang.startDate)
        XCTAssertEqual(command.hangDuration, duration)
        XCTAssertEqual(command.message, AppHangsMonitor.Constants.appHangErrorMessage)
        XCTAssertEqual(command.type, AppHangsMonitor.Constants.appHangErrorType)
        XCTAssertEqual(command.stack, hang.backtraceResult.stack)
        DDAssertReflectionEqual(command.threads, hang.backtraceResult.threads)
        DDAssertReflectionEqual(command.binaryImages, hang.backtraceResult.binaryImages)
        XCTAssertEqual(command.isStackTraceTruncated, hang.backtraceResult.wasTruncated)
    }

    // MARK: - Fatal App Hangs Monitoring

    func testGivenFatalErrorViewContextAvailable_whenAppHangStarts_itSavesPendingAppHangToDataStore() throws {
        // Given
        monitor.start()
        defer { monitor.stop() }
        fatalErrorContext.view = .mockRandom()

        // When
        let hang: AppHang = .mockRandom()
        watchdogThread.delegate?.hangStarted(hang)

        // Then
        XCTAssertNotNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
        XCTAssertEqual(dd.logger.debugMessages, ["No pending App Hang found"])
    }

    func testGivenFatalErrorViewContextNotAvailable_whenAppHangStarts_itLogsDebug() throws {
        // Given
        monitor.start()
        defer { monitor.stop() }
        fatalErrorContext.view = nil

        // When
        let hang: AppHang = .mockRandom()
        watchdogThread.delegate?.hangStarted(hang)

        // Then
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
        XCTAssertEqual(
            dd.logger.debugMessages,
            [
                "No pending App Hang found",
                "App Hang is being detected, but won't be considered fatal as there is no active RUM view"
            ]
        )
    }

    func testWhenAppHangGetsCancelled_itDeletesPendingAppHangInDataStore() throws {
        // Given
        monitor.start()
        defer { monitor.stop() }
        fatalErrorContext.view = .mockRandom()

        // When
        let hang: AppHang = .mockRandom()
        watchdogThread.delegate?.hangStarted(hang)
        watchdogThread.delegate?.hangCancelled(hang)

        // Then
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
        XCTAssertEqual(dd.logger.debugLog?.message, "No pending App Hang found")
    }

    func testWhenAppHangEnds_itDeletesPendingAppHangInDataStore() throws {
        // Given
        monitor.start()
        defer { monitor.stop() }
        fatalErrorContext.view = .mockRandom()

        // When
        let hang: AppHang = .mockRandom()
        let duration: TimeInterval = .mockAny()
        watchdogThread.delegate?.hangStarted(hang)
        watchdogThread.delegate?.hangEnded(hang, duration: duration)

        // Then
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
        XCTAssertEqual(dd.logger.debugMessages, ["No pending App Hang found"])
    }

    // MARK: - Fatal App Hangs - Testing Conditional Uploads

    func testGivenPendingHangStartedLessThan4HoursAgo_whenStartedInAnotherProcess_itSendsBothRUMErrorAndRUMViewEvent() throws {
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let hangDate: Date = currentDate.secondsAgo(.random(in: 0...4.hours))
        let view: RUMViewEvent = .mockRandom()
        let hang: AppHang = .mockWith(startDate: hangDate)

        // Given
        featureScope.contextMock.trackingConsent = .granted
        monitor.start()
        fatalErrorContext.view = view
        watchdogThread.delegate?.hangStarted(hang)
        monitor.stop()

        // When
        featureScope.contextMock.trackingConsent = .mockRandom() // no matter of the consent in restarted session

        let monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: UUID(), // different process
            dateProvider: DateProviderMock(now: currentDate)
        )
        monitor.start()
        defer { monitor.stop() }

        // Then
        XCTAssertEqual(
            dd.logger.debugMessages,
            [
                "No pending App Hang found", // from hanged process
                "Sending fatal App hang as RUM error with issuing RUM view update", // from next process
            ]
        )

        XCTAssertEqual(featureScope.eventsWritten.count, 2, "It must send both RUM error and RUM view")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, 1)
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMViewEvent.self).count, 1)
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
    }

    func testGivenPendingHangStartedMoreThan4HoursAgo_whenStartedInAnotherProcess_itSendsOnlyRUMError() throws {
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let hangDate: Date = currentDate.secondsAgo(.random(in: 4.hours..<24.hours))
        let view: RUMViewEvent = .mockRandom()
        let hang: AppHang = .mockWith(startDate: hangDate)

        // Given
        featureScope.contextMock.trackingConsent = .granted
        monitor.start()
        fatalErrorContext.view = view
        watchdogThread.delegate?.hangStarted(hang)
        monitor.stop()

        // When
        featureScope.contextMock.trackingConsent = .mockRandom() // no matter of the consent in restarted session

        let monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: UUID(), // different process
            dateProvider: DateProviderMock(now: currentDate)
        )
        monitor.start()
        defer { monitor.stop() }

        // Then
        XCTAssertEqual(
            dd.logger.debugMessages,
            [
                "No pending App Hang found", // from hanged process
                "Sending fatal App hang as RUM error without updating RUM view", // from next process
            ]
        )

        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must send only RUM error")
        XCTAssertEqual(featureScope.eventsWritten(ofType: RUMErrorEvent.self).count, 1)
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
    }

    func testGivenPendingHangStartedWithPendingOrNotGrantedConsent_whenStartedInAnotherProcess_itSendsNoEvent() throws {
        let consent: TrackingConsent = .mockRandom(otherThan: TrackingConsent.granted)
        let view: RUMViewEvent = .mockRandom()
        let hang: AppHang = .mockRandom()

        // Given
        featureScope.contextMock.trackingConsent = consent
        monitor.start()
        fatalErrorContext.view = view
        watchdogThread.delegate?.hangStarted(hang)
        monitor.stop()

        // When
        featureScope.contextMock.trackingConsent = .mockRandom() // no matter of the consent in restarted session

        let monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: UUID(), // different process
            dateProvider: DateProviderMock()
        )
        monitor.start()
        defer { monitor.stop() }

        // Then
        XCTAssertEqual(
            dd.logger.debugMessages,
            [
                "No pending App Hang found", // from hanged process
                "Skipped sending fatal App Hang as it was recorded with \(consent) consent", // from next process
            ]
        )

        XCTAssertEqual(featureScope.eventsWritten.count, 0, "It must send no event")
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
    }

    // MARK: - Fatal App Hangs - Testing Uploaded Data

    func testWhenSendingRUMViewEvent_itIsLinkedToPreviousRUMSessionAndIncludesErrorInformation() throws {
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let hangDate: Date = currentDate.secondsAgo(.random(in: 0...4.hours))
        let serverTimeOffset: TimeInterval = .mockRandom()
        let lastView: RUMViewEvent = .mockRandom()
        let hang: AppHang = .mockWith(startDate: hangDate)

        // Given
        featureScope.contextMock.trackingConsent = .granted
        featureScope.contextMock.serverTimeOffset = serverTimeOffset
        monitor.start()
        fatalErrorContext.view = lastView
        watchdogThread.delegate?.hangStarted(hang)
        monitor.stop()

        // When
        featureScope.contextMock.trackingConsent = .mockRandom() // no matter of the consent in restarted session

        let monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: UUID(), // different process
            dateProvider: DateProviderMock(now: currentDate)
        )
        monitor.start()
        defer { monitor.stop() }

        // Then
        let viewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(viewEvent.application.id, lastView.application.id)
        XCTAssertEqual(viewEvent.session.id, lastView.session.id)
        XCTAssertEqual(viewEvent.view.id, lastView.view.id)
        XCTAssertEqual(viewEvent.dd.documentVersion, lastView.dd.documentVersion + 1, "It must increment document version")
        XCTAssertEqual(viewEvent.view.error.count, lastView.view.error.count + 1, "It must count the hang error")
        XCTAssertEqual(viewEvent.view.crash?.count, 1, "It must count crash")
        XCTAssertEqual(viewEvent.view.isActive, false, "The view must be marked as inactive.")

        XCTAssertEqual(viewEvent.service, lastView.service)
        XCTAssertEqual(viewEvent.version, lastView.version)
        XCTAssertEqual(viewEvent.buildVersion, lastView.buildVersion)
        XCTAssertEqual(viewEvent.view.name, lastView.view.name)
        XCTAssertEqual(viewEvent.view.url, lastView.view.url)
        XCTAssertEqual(viewEvent.view.resource.count, lastView.view.resource.count)
        XCTAssertEqual(viewEvent.view.action.count, lastView.view.action.count)
        XCTAssertEqual(
            viewEvent.date,
            hangDate.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds - 1,
            "It must be issued at hang date corrected by recorded offset and shifted back by 1ms"
        )
        XCTAssertEqual(viewEvent.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        DDAssertReflectionEqual(viewEvent.device, lastView.device)
        DDAssertReflectionEqual(viewEvent.os, lastView.os)
        DDAssertJSONEqual(viewEvent.connectivity, lastView.connectivity)
        DDAssertJSONEqual(viewEvent.usr, lastView.usr)
    }

    func testWhenSendingRUMErrorEvent_itIsLinkedToPreviousRUMSessionAndIncludesErrorInformation() throws {
        let currentDate: Date = .mockDecember15th2019At10AMUTC()
        let hangDate: Date = currentDate.secondsAgo(.random(in: 0...4.hours))
        let serverTimeOffset: TimeInterval = .mockRandom()
        let lastView: RUMViewEvent = .mockRandom()
        let hangBacktrace: BacktraceReport = .mockWith(
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
            wasTruncated: .random()
        )
        let hang: AppHang = .mockWith(startDate: hangDate, backtraceResult: .succeeded(hangBacktrace))

        // Given
        featureScope.contextMock.trackingConsent = .granted
        featureScope.contextMock.serverTimeOffset = serverTimeOffset
        monitor.start()
        fatalErrorContext.view = lastView
        watchdogThread.delegate?.hangStarted(hang)
        monitor.stop()

        // When
        featureScope.contextMock.trackingConsent = .mockRandom() // no matter of the consent in restarted session

        let monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: UUID(), // different process
            dateProvider: DateProviderMock(now: currentDate)
        )
        monitor.start()
        defer { monitor.stop() }

        // Then
        let errorEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(errorEvent.application.id, lastView.application.id)
        XCTAssertEqual(errorEvent.session.id, lastView.session.id)
        XCTAssertEqual(errorEvent.view.id, lastView.view.id)
        XCTAssertEqual(errorEvent.error.category, .appHang)
        XCTAssertEqual(errorEvent.error.isCrash, true, "Fatal hang must be marked as crash")
        XCTAssertEqual(errorEvent.view.name, lastView.view.name, "It must include view attributes")
        XCTAssertEqual(errorEvent.view.referrer, lastView.view.referrer, "It must include view attributes")
        XCTAssertEqual(errorEvent.view.url, lastView.view.url, "It must include view attributes")
        DDAssertJSONEqual(
            AnyEncodable(errorEvent.context?.contextInfo),
            AnyEncodable(lastView.context?.contextInfo),
            "It must include the user context from the last view"
        )
        XCTAssertEqual(
            errorEvent.date,
            hangDate.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
            "It must include error date corrected by recorded server time offset"
        )
        XCTAssertEqual(errorEvent.error.type, AppHangsMonitor.Constants.appHangErrorType)
        XCTAssertEqual(errorEvent.error.message, AppHangsMonitor.Constants.appHangErrorMessage)
        XCTAssertEqual(
            errorEvent.error.stack,
            """
            0: stack-trace line 0
            1: stack-trace line 1
            2: stack-trace line 2
            """
        )
        XCTAssertEqual(errorEvent.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        DDAssertJSONEqual(errorEvent.error.threads, hangBacktrace.threads.toRUMDataFormat)
        DDAssertJSONEqual(errorEvent.error.binaryImages, hangBacktrace.binaryImages.toRUMDataFormat)
        XCTAssertEqual(errorEvent.error.wasTruncated, hangBacktrace.wasTruncated)
    }

    func testWhenSendingRUMErrorEvent_itIncludesTimeSinceAppLaunch() throws {
        let appLaunchDate: Date = .mockDecember15th2019At10AMUTC()
        let hangTimeSinceAppStart: TimeInterval = .mockRandom(min: 1, max: 10)
        let hang: AppHang = .mockWith(startDate: appLaunchDate.addingTimeInterval(hangTimeSinceAppStart))

        // Given (track hang in previous app session)
        featureScope.contextMock.trackingConsent = .granted
        featureScope.contextMock.launchInfo = .mockWith(processLaunchDate: appLaunchDate)
        featureScope.contextMock.serverTimeOffset = 0
        monitor.start()
        fatalErrorContext.view = .mockRandom()
        watchdogThread.delegate?.hangStarted(hang)
        monitor.stop()

        // When (app is restarted)
        let appRestartDate = appLaunchDate.addingTimeInterval(.mockRandom(min: 10, max: 100))
        featureScope.contextMock.launchInfo = .mockWith(processLaunchDate: appRestartDate)
        featureScope.contextMock.serverTimeOffset = .mockRandom(min: 0, max: 100)
        let monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: UUID(), // different process
            dateProvider: DateProviderMock(now: appRestartDate)
        )
        monitor.start()
        defer { monitor.stop() }

        // Then
        let errorEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(errorEvent.error.category, .appHang)
        XCTAssertEqual(errorEvent.error.timeSinceAppStart, hangTimeSinceAppStart.dd.toInt64Milliseconds)
    }
}
