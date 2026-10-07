/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class MonitorTests: XCTestCase {
    private var featureScope: FeatureScope! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        featureScope = FeatureScopeMock(
            context: .mockWith(
                launchInfo: .mockWith(
                    launchReason: .userLaunch,
                    processLaunchDate: Date()
                )
            )
        )
    }

    func testWhenSessionIsSampled_itSetsRUMContextInCore() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            dateProvider: DateProviderMock()
        )

        // When
        monitor.startView(key: "foo")

        // Then
        let expectedContext = monitor.currentRUMContext
        var datadogContext: DatadogContext?
        featureScope.context { datadogContext = $0 }
        let rumContext = try XCTUnwrap(datadogContext?.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertEqual(rumContext.applicationID, expectedContext.rumApplicationID)
        XCTAssertEqual(rumContext.sessionID, expectedContext.sessionID.toRUMDataFormat)
        XCTAssertEqual(rumContext.viewID, expectedContext.activeViewID?.toRUMDataFormat)
    }

    func testWhenSessionIsNotSampled_RUMCoreSampler_returnsFalse() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 0),
            dateProvider: DateProviderMock()
        )

        // When
        monitor.startView(key: "foo")

        // Then
        var context: DatadogContext?
        featureScope.context { context = $0 }
        let rumContext = try XCTUnwrap(context?.additionalContext(ofType: RUMCoreContext.self))
        XCTAssertFalse(rumContext.sessionSampler.isSampled)
    }

    #if !os(watchOS)
    func testStartView_withViewController_itUsesClassNameAsViewName() throws {
        // Given
        let vc = createMockView(viewControllerClassName: "SomeViewController")

        // When
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: DateProviderMock()
        )
        monitor.startView(viewController: vc)

        // Then
        XCTAssertEqual(monitor.applicationScope.sessionScopes.first?.viewScopes.first?.viewName, "SomeViewController")
        XCTAssertEqual(monitor.applicationScope.sessionScopes.first?.viewScopes.first?.viewPath, "SomeViewController")
    }

    func testStartView_withViewController_itUsesClassNameAsViewPath() throws {
        // Given
        let vc = createMockView(viewControllerClassName: "SomeViewController")

        // When
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: DateProviderMock()
        )
        monitor.startView(viewController: vc, name: "Some View")

        // Then
        XCTAssertEqual(monitor.applicationScope.sessionScopes.first?.viewScopes.first?.viewName, "Some View")
        XCTAssertEqual(monitor.applicationScope.sessionScopes.first?.viewScopes.first?.viewPath, "SomeViewController")
    }
    #endif

    // MARK: - App launch

    func testReportTTIDAndTTFD_thenTheyAreWrittenAsVitalEvents() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.process(command: RUMTimeToInitialDisplayCommand(time: Date()))
        monitor.reportAppFullyDisplayed()

        // Then
        let vitalEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMVitalAppLaunchEvent.self)

        XCTAssertEqual(vitalEvents?.count, 2)
        XCTAssertEqual(vitalEvents?.first?.vital.appLaunchMetric, .ttid)
        XCTAssertEqual(vitalEvents?.last?.vital.appLaunchMetric, .ttfd)
    }

    func testReportTTFDWithoutTTID_thenTheyAreNotWritten() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.reportAppFullyDisplayed()

        // Then
        let vitalEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMVitalAppLaunchEvent.self)

        XCTAssertEqual(vitalEvents?.count, 0)
    }

    func testReportTTIDWithoutTTFD_thenTTIDIsWrittenAsVitalEvent() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.process(command: RUMTimeToInitialDisplayCommand(time: Date()))

        // Then
        let vitalEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMVitalAppLaunchEvent.self)

        XCTAssertEqual(vitalEvents?.count, 1)
        XCTAssertEqual(vitalEvents?.first?.vital.appLaunchMetric, .ttid)
    }

    // MARK: - View Loading Time

    func testAddViewLoadingTimeToActiveView_thenLoadingTimeUpdated() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, featureFlags: [.viewUpdates: false]),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()
        monitor.startView(key: "ActiveView")

        // When
        monitor.addViewLoadingTime(overwrite: false)

        // Then
        let viewEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let lastView = try XCTUnwrap(viewEvents?.last)

        XCTAssertNotNil(lastView.view.loadingTime)
        XCTAssertTrue(lastView.view.loadingTime! > 0)
    }

    func testAddViewLoadingTimeNoActiveView_thenNoEvent() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()
        monitor.startView(key: "InactiveView")
        monitor.stopView(key: "InactiveView")

        // When
        monitor.addViewLoadingTime(overwrite: false)

        // Then
        let viewEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "InactiveView" }
        XCTAssertNil(viewEvents?.last?.view.loadingTime)
    }

    func testAddViewLoadingTimeMultipleTimes_thenLoadingTimeOverwritten() throws {
        // Given
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, featureFlags: [.viewUpdates: false]),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()
        monitor.startView(key: "ActiveView")

        // When
        monitor.addViewLoadingTime(overwrite: false)

        // Then
        let viewEvents = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let lastView = try XCTUnwrap(viewEvents?.last)

        XCTAssertNotNil(lastView.view.loadingTime)
        XCTAssertTrue(lastView.view.loadingTime! > 0)

        let old = lastView.view.loadingTime!

        // When
        monitor.addViewLoadingTime(overwrite: false)

        // Then
        let viewEvents2 = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let lastView2 = try XCTUnwrap(viewEvents2?.last)

        XCTAssertNotNil(lastView2.view.loadingTime)
        XCTAssertTrue(lastView2.view.loadingTime! > 0)

        XCTAssertEqual(lastView2.view.loadingTime!, old)

        // When
        monitor.addViewLoadingTime(overwrite: true)

        // Then
        let viewEvents3 = (featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let lastView3 = try XCTUnwrap(viewEvents3?.last)

        XCTAssertNotNil(lastView3.view.loadingTime)
        XCTAssertTrue(lastView3.view.loadingTime! > 0)

        XCTAssertTrue(lastView3.view.loadingTime! > old)
    }

    func testStartingAnotherViewWithoutStoppingPreviousView_reportsSlowFramesRate() throws {
        let hitch = Hitch(start: 0, duration: 0.16.dd.toInt64Nanoseconds)
        let dateProvider = DateProviderMock()
        let monitor = Monitor(
            dependencies: .mockWith(
                featureScope: featureScope,
                viewHitchesReaderFactory: { ViewHitchesMock(hitchesDataModel: ([hitch], 0.16)) },
                featureFlags: [.viewUpdates: false]
            ),
            dateProvider: dateProvider
        )

        monitor.startView(key: "ScreenA")
        dateProvider.now.addTimeInterval(10)
        monitor.startView(key: "ScreenB")
        dateProvider.now.addTimeInterval(10)
        monitor.stopView(key: "ScreenB")

        let viewEvents = try XCTUnwrap((featureScope as? FeatureScopeMock)?.eventsWritten(ofType: RUMViewEvent.self))
        XCTAssertEqual(viewEvents.last { $0.view.name == "ScreenA" }?.view.slowFramesRate, 16)
        XCTAssertEqual(viewEvents.last { $0.view.name == "ScreenB" }?.view.slowFramesRate, 16)
    }

    // MARK: - Session lifetime

    func testWhenCrossPlatformClockLagsDeviceClock_itKeepsTheSameSession() throws {
        try assertSessionSurvivesCrossPlatformClockSkew(-2 * RUMSessionScope.Constants.sessionMaxDuration)
    }

    func testWhenCrossPlatformClockLeadsDeviceClock_itKeepsTheSameSession() throws {
        try assertSessionSurvivesCrossPlatformClockSkew(2 * RUMSessionScope.Constants.sessionMaxDuration)
    }

    private func assertSessionSurvivesCrossPlatformClockSkew(_ offset: TimeInterval) throws {
        let dateProvider = DateProviderMock()
        let clock = MonotonicClockMock(elapsedTime: 123)
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100, monotonicClock: clock),
            dateProvider: dateProvider
        )
        monitor.notifySDKInit()
        monitor.startView(key: "view")
        let sessionID = try XCTUnwrap(monitor.applicationScope.activeSession?.sessionUUID)

        // Each clock is consistent on its own; alternating between them must not split sessions.
        for _ in 0..<4 {
            clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration / 2)
            dateProvider.now.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration / 2)
            let timestamp = dateProvider.now.addingTimeInterval(offset).timeIntervalSince1970.dd.toInt64Milliseconds
            monitor.addAction(type: .tap, name: "cross-platform", attributes: [CrossPlatformAttributes.timestampInMilliseconds: timestamp])
            XCTAssertEqual(monitor.applicationScope.activeSession?.sessionUUID, sessionID)

            clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration / 2)
            dateProvider.now.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration / 2)
            monitor.addAction(type: .tap, name: "native", attributes: [:])
            XCTAssertEqual(monitor.applicationScope.activeSession?.sessionUUID, sessionID)
        }
    }

    func testWhenDeviceDateChanges_itKeepsTheSameSession() throws {
        for offset in [-2 * RUMSessionScope.Constants.sessionMaxDuration, 2 * RUMSessionScope.Constants.sessionMaxDuration] {
            let dateProvider = DateProviderMock()
            let clock = MonotonicClockMock(elapsedTime: 123)
            let monitor = Monitor(
                dependencies: .mockWith(featureScope: featureScope, samplingRate: 100, monotonicClock: clock),
                dateProvider: dateProvider
            )
            monitor.notifySDKInit()
            monitor.startView(key: "view")
            let sessionID = try XCTUnwrap(monitor.applicationScope.activeSession?.sessionUUID)

            dateProvider.now.addTimeInterval(offset)
            clock.advance(by: 1)
            XCTAssertFalse(monitor.isSessionExpired(sessionID: sessionID.toRUMDataFormat))
            monitor.addAction(type: .tap, name: "after date change", attributes: [:])
            XCTAssertEqual(monitor.applicationScope.activeSession?.sessionUUID, sessionID)
        }
    }

    func testWhenInternalActionCarriesForeignDateWithoutTimestampAttribute_itKeepsTheSameSession() throws {
        let dateProvider = DateProviderMock()
        let clock = MonotonicClockMock(elapsedTime: 123)
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100, monotonicClock: clock),
            dateProvider: dateProvider
        )
        monitor.notifySDKInit()
        monitor.startView(key: "view")
        let sessionID = try XCTUnwrap(monitor.applicationScope.activeSession?.sessionUUID)
        let internalMonitor = try XCTUnwrap(monitor._internal)

        for offset in [-2 * RUMSessionScope.Constants.sessionMaxDuration, 2 * RUMSessionScope.Constants.sessionMaxDuration] {
            clock.advance(by: 1)
            internalMonitor.addAction(
                at: dateProvider.now.addingTimeInterval(offset),
                type: .tap,
                name: "cross-platform heatmap tap",
                heatmapAttributes: nil
            )
            XCTAssertEqual(monitor.applicationScope.activeSession?.sessionUUID, sessionID)
            clock.advance(by: 1)
            monitor.addAction(type: .tap, name: "native", attributes: [:])
            XCTAssertEqual(monitor.applicationScope.activeSession?.sessionUUID, sessionID)
        }
    }

    func testSessionExpiryReader_usesElapsedTimeAndRefreshesOnInteraction() throws {
        let clock = MonotonicClockMock(elapsedTime: 123)
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100, monotonicClock: clock),
            dateProvider: DateProviderMock()
        )
        XCTAssertFalse(monitor.isSessionExpired(sessionID: "no session"))
        monitor.notifySDKInit()
        monitor.startView(key: "view")
        let sessionID = try XCTUnwrap(monitor.applicationScope.activeSession?.sessionUUID.toRUMDataFormat)

        clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration - 1)
        XCTAssertFalse(monitor.isSessionExpired(sessionID: sessionID))
        monitor.addAction(type: .tap, name: "interaction", attributes: [:])
        clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration - 1)
        XCTAssertFalse(monitor.isSessionExpired(sessionID: sessionID))
        clock.advance(by: 1)
        XCTAssertTrue(monitor.isSessionExpired(sessionID: sessionID))
        XCTAssertFalse(monitor.isSessionExpired(sessionID: "another session"))

        monitor.addAction(type: .tap, name: "new session", attributes: [:])
        XCTAssertNotEqual(monitor.applicationScope.activeSession?.sessionUUID.toRUMDataFormat, sessionID)
        XCTAssertFalse(monitor.isSessionExpired(sessionID: sessionID))
    }

    func testSessionExpiryReader_expiresAtMaximumDurationDespiteContinuedInteraction() throws {
        let clock = MonotonicClockMock(elapsedTime: 123)
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100, monotonicClock: clock),
            dateProvider: DateProviderMock()
        )
        monitor.notifySDKInit()
        monitor.startView(key: "view")
        let sessionID = try XCTUnwrap(monitor.applicationScope.activeSession?.sessionUUID.toRUMDataFormat)
        let sessionEnd = clock.elapsedTime + RUMSessionScope.Constants.sessionMaxDuration

        while clock.elapsedTime + RUMSessionScope.Constants.sessionTimeoutDuration - 1 < sessionEnd {
            clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration - 1)
            monitor.addAction(type: .tap, name: "interaction", attributes: [:])
            XCTAssertFalse(monitor.isSessionExpired(sessionID: sessionID))
            XCTAssertEqual(monitor.applicationScope.activeSession?.sessionUUID.toRUMDataFormat, sessionID)
        }
        clock.advance(by: sessionEnd - clock.elapsedTime - 1)
        XCTAssertFalse(monitor.isSessionExpired(sessionID: sessionID))
        clock.advance(by: 1)
        XCTAssertTrue(monitor.isSessionExpired(sessionID: sessionID))
    }

    // MARK: - hasReplay snapshot

    func testHasReplaySnapshot_isGatedByTimeseriesCollectorAndResetOnNewSession() throws {
        let dateProvider = DateProviderMock()
        featureScope = FeatureScopeMock(
            context: .mockWith(additionalContext: [SessionReplayCoreContext.HasReplay(value: true)])
        )

        // Given — no timeseries collector configured
        let monitorWithoutCollector = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: dateProvider
        )

        // When
        monitorWithoutCollector.startView(key: "foo")

        // Then — the snapshot is never updated
        XCTAssertNil((monitorWithoutCollector as RUMActiveContextReader).hasReplay)

        // Given — a timeseries collector configured
        let monitor = Monitor(
            dependencies: .mockWith(
                featureScope: featureScope,
                monotonicClock: DateProviderMonotonicClock(dateProvider: dateProvider),
                timeseriesCollector: TimeseriesCollectorStub()
            ),
            dateProvider: dateProvider
        )
        let activeContextReader: RUMActiveContextReader = monitor

        monitor.startView(key: "foo")
        XCTAssertEqual(activeContextReader.hasReplay, true)

        // When — the session expires (starting a new one within a single `process(command:)` call) while
        // the context still carries the previous session's (now stale) `hasReplay` value
        dateProvider.now = dateProvider.now.addingTimeInterval(4 * 60 * 60 + 1) // exceeds session max duration
        monitor.startView(key: "bar")

        // Then — the stale value is not carried over into the new session
        XCTAssertNil(activeContextReader.hasReplay)
    }
}

private class TimeseriesCollectorStub: TimeseriesCollecting {
    weak var activeContextReader: RUMActiveContextReader?
    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType) {}
    func pause(sessionID: String) {}
    func resume(sessionID: String) {}
    func stop(sessionID: String) {}
    func noteActivity(sessionID: String, at time: Date) {}
    func flush() {}
}

// MARK: - Convenience

private extension Monitor {
    /// Returns RUM context assuming that some view is started.
    var currentRUMContext: RUMContext { applicationScope.activeSession!.viewScopes.last!.context }
}
