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

    func start() { started = true }
    func stop() { started = false }

    var onHangStarted: ((AppHang) -> Void)?
    var onHangCancelled: ((AppHang) -> Void)?
    var onHangEnded: ((AppHang, TimeInterval) -> Void)?
    var onBeforeSleep: (() -> Void)?
}

class AppHangsMonitorTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private let watchdogThread = WatchdogThreadMock()
    private let fatalErrorContext = FatalErrorContextNotifier(messageBus: NOPFeatureScope())
    private let currentProcessID = UUID()
    private var dd: DDMock<CoreLoggerMock>! // swiftlint:disable:this implicitly_unwrapped_optional
    private var monitor: AppHangsMonitor! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        dd = DD.mockWith(logger: CoreLoggerMock())
        monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: currentProcessID
        )
    }

    override func tearDown() {
        monitor = nil
        dd.reset()
    }

    func testStartAndStop() throws {
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
        watchdogThread.onHangEnded?(hang, duration)

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
        watchdogThread.onHangStarted?(hang)

        // Then
        XCTAssertNotNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
        XCTAssertTrue(dd.logger.recordedLogs.isEmpty, "It must log no issues")
    }

    func testGivenFatalErrorViewContextNotAvailable_whenAppHangStarts_itLogsDebug() throws {
        // Given
        monitor.start()
        defer { monitor.stop() }
        fatalErrorContext.view = nil

        // When
        let hang: AppHang = .mockRandom()
        watchdogThread.onHangStarted?(hang)

        // Then
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
        XCTAssertEqual(
            dd.logger.debugLog?.message,
            "App Hang is being detected, but won't be considered fatal as there is no active RUM view"
        )
    }

    func testWhenAppHangGetsCancelled_itDeletesPendingAppHangInDataStore() throws {
        // Given
        monitor.start()
        defer { monitor.stop() }
        fatalErrorContext.view = .mockRandom()

        // When
        let hang: AppHang = .mockRandom()
        watchdogThread.onHangStarted?(hang)
        watchdogThread.onHangCancelled?(hang)

        // Then
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
        XCTAssertTrue(dd.logger.recordedLogs.isEmpty)
        XCTAssertTrue(dd.logger.recordedLogs.isEmpty, "It must log no issues")
    }

    func testWhenAppHangEnds_itDeletesPendingAppHangInDataStore() throws {
        // Given
        monitor.start()
        defer { monitor.stop() }
        fatalErrorContext.view = .mockRandom()

        // When
        let hang: AppHang = .mockRandom()
        let duration: TimeInterval = .mockAny()
        watchdogThread.onHangStarted?(hang)
        watchdogThread.onHangEnded?(hang, duration)

        // Then
        XCTAssertNil(featureScope.dataStoreMock.value(forKey: RUMDataStore.Key.fatalAppHangKey.rawValue))
        XCTAssertTrue(dd.logger.recordedLogs.isEmpty, "It must log no issues")
    }

    func testGivenPendingHangSavedInOneProcess_whenStartedInDiffferentProcess_itSendsFatalHang() throws {
        let sessionState: RUMSessionState = .mockRandom()
        let view: RUMViewEvent = .mockRandom()
        let hang: AppHang = .mockRandom()

        // Given
        monitor.start()
        fatalErrorContext.sessionState = sessionState
        fatalErrorContext.view = view
        watchdogThread.onHangStarted?(hang)
        monitor.stop()

        // When
        let monitor = AppHangsMonitor(
            featureScope: featureScope,
            watchdogThread: watchdogThread,
            fatalErrorContext: fatalErrorContext,
            processID: UUID() // different process
        )
        monitor.start()
        defer { monitor.stop() }

        // Then
        XCTAssertEqual(dd.logger.debugLog?.message, "Loaded fatal App Hang")

        // TODO: RUM-3461
        // Assert on collected RUM error and RUM view update, similar to how we test it for crash reports
    }
}
