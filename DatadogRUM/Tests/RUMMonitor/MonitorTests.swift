/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if os(iOS)
import UIKit
#endif
@_spi(Internal)
@testable import DatadogInternal
@testable import DatadogCore
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

    func testWhenInteractionRenewsSession_itPublishesActivityBeforeNotifyingCollector() throws {
        let clock = MonotonicClockMock()
        let collector = TimeseriesCollectorStub()
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100, monotonicClock: clock, timeseriesCollector: collector),
            dateProvider: DateProviderMock()
        )
        collector.activeContextReader = monitor
        monitor.notifySDKInit()
        monitor.startView(key: "first")
        let sessionID = try XCTUnwrap(monitor.applicationScope.activeSession?.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(collector.activitySessionIDs, [sessionID])

        clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration + 1)
        monitor.addAction(type: .custom, name: "new session", attributes: [:])

        let renewedID = try XCTUnwrap(monitor.applicationScope.activeSession?.sessionUUID.toRUMDataFormat)
        XCTAssertNotEqual(renewedID, sessionID)
        XCTAssertEqual(collector.activitySessionIDs, [sessionID, renewedID])
        XCTAssertEqual(collector.isPreviousSessionExpiredOnActivity, false)
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
    var activitySessionIDs: [String] = []
    var isPreviousSessionExpiredOnActivity: Bool?

    func noteActivity(sessionID: String) {
        if let previousSessionID = activitySessionIDs.last {
            isPreviousSessionExpiredOnActivity = activeContextReader?.isSessionExpired(sessionID: previousSessionID)
        }
        activitySessionIDs.append(sessionID)
    }
    func flush() {}
}

// MARK: - Convenience

private extension Monitor {
    /// Returns RUM context assuming that some view is started.
    var currentRUMContext: RUMContext { applicationScope.activeSession!.viewScopes.last!.context }
}

#if os(iOS)
extension MonitorTests {
    private var snapshotDate: Date { Date(timeIntervalSince1970: 1_600_000_000) }
    private var sceneA: RUMSceneIdentifier { .init(rawValue: "scene-a") }
    private var sceneB: RUMSceneIdentifier { .init(rawValue: "scene-b") }

    @MainActor
    func testSceneDisconnect_projectsPeerThroughHandlerAndMonitorWithoutRevivingRetainedOwner() throws {
        XCTAssertTrue(Thread.isMainThread)
        for keepPeerActive in [true, false] {
            let clock = DateProviderMock(now: snapshotDate)
            let feature = FeatureScopeMock(context: .mockWith(sdkInitDate: snapshotDate))
            let fatal = FatalErrorContextNotifierMock()
            let manager = AppStateManager(featureScope: feature, processId: UUID(), syntheticsEnvironment: false)
            let watchdog = WatchdogTerminationMonitor(
                appStateManager: manager,
                checker: WatchdogTerminationChecker(appStateManager: manager, featureScope: feature),
                storage: nil,
                feature: feature,
                reporter: WatchdogTerminationReporterMock(didSend: XCTestExpectation(description: "no watchdog termination"))
            )
            watchdog.currentState = .started
            let monitor = Monitor(
                dependencies: .mockWith(
                    featureScope: feature,
                    trackBackgroundEvents: false,
                    viewCache: ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true),
                    fatalErrorContext: fatal,
                    watchdogTermination: watchdog,
                    featureFlags: [.multiSceneTracking: true, .viewUpdates: false]
                ),
                dateProvider: clock
            )
            let center = NotificationCenter()
            let handler = RUMSceneViewsHandler(
                dateProvider: clock,
                uiKitPredicate: nil,
                swiftUIPredicate: nil,
                swiftUIViewNameExtractor: nil,
                notificationCenterProvider: .init(applicationCenter: center),
                isMultiSceneApplication: true,
                sceneIdentifierProvider: { _ in nil },
                sceneIdentifierFromNotification: { notification in
                    (notification.object as? NSString).map { RUMSceneIdentifier(rawValue: $0 as String) }
                },
                initialSceneActivityProvider: { [self.sceneA: true, self.sceneB: true] }
            )
            handler.publish(to: monitor)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            func assertSnapshot(_ expected: Data?) throws {
                var stored: RUMViewEvent?
                feature.rumDataStore.value(forKey: .watchdogRUMViewEvent) { (event: RUMViewEvent?) in stored = event }
                XCTAssertEqual(try fatal.view.map { try encoder.encode($0) }, expected)
                XCTAssertEqual(try stored.map { try encoder.encode($0) }, expected)
            }
            handler.startView(key: "peer", name: "peer", attributes: [:], sceneIdentifier: sceneA)
            let peerID = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA))?.viewID)
            let peerSnapshot = try encoder.encode(XCTUnwrap(fatal.view))
            clock.now = snapshotDate.addingTimeInterval(1)
            handler.startView(key: "owner", name: "owner", attributes: [:], sceneIdentifier: sceneB)
            let ownerID = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID)
            XCTAssertNotEqual(ownerID, peerID)
            XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, ownerID)
            XCTAssertEqual(fatal.view?.view.id, ownerID)
            try assertSnapshot(encoder.encode(XCTUnwrap(fatal.view)))
            var resource = RUMStartResourceCommand.mockWith(resourceKey: "owned-resource", time: clock.now)
            resource.target = .scene(sceneB)
            monitor.process(command: resource)
            clock.now = snapshotDate.addingTimeInterval(2)
            center.post(name: UIScene.didDisconnectNotification, object: sceneB.rawValue as NSString)
            XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID)
            XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, peerID)
            let retained = try XCTUnwrap(monitor.applicationScope.activeSession?.viewScopes.first { $0.viewUUID.toRUMDataFormat == ownerID })
            XCTAssertFalse(retained.isActiveView)
            try assertSnapshot(peerSnapshot)
            center.post(name: UIScene.willEnterForegroundNotification, object: sceneB.rawValue as NSString)
            handler.startView(key: "disconnected", name: nil, attributes: [:], sceneIdentifier: sceneB)
            XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID)
            try assertSnapshot(peerSnapshot)
            if !keepPeerActive {
                clock.now = snapshotDate.addingTimeInterval(3)
                handler.stopView(key: "peer", attributes: [:], sceneIdentifier: sceneA)
                XCTAssertNil(monitor.rumContextSnapshot(for: .processRepresentative)?.viewID)
                try assertSnapshot(nil)
            }
            var completion = RUMStopResourceCommand.mockWith(resourceKey: "owned-resource", time: snapshotDate.addingTimeInterval(4))
            completion.target = .scene(sceneB)
            monitor.process(command: completion)
            XCTAssertEqual(feature.eventsWritten(ofType: RUMResourceEvent.self).last?.view.id, ownerID)
            XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, keepPeerActive ? peerID : nil)
            try assertSnapshot(keepPeerActive ? peerSnapshot : nil)
        }
    }

    private func sceneMonitor(scope: FeatureScope, clock: DateProviderMock, enabled: Bool = true, monotonicClock: MonotonicClock? = nil) -> Monitor {
        Monitor(
            dependencies: .mockWith(
                featureScope: scope,
                trackBackgroundEvents: false,
                viewCache: ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: enabled),
                featureFlags: [.multiSceneTracking: enabled],
                monotonicClock: monotonicClock ?? DateProviderMonotonicClock(dateProvider: clock)
            ),
            dateProvider: clock
        )
    }

    private func startSnapshotView(_ monitor: Monitor, key: String, target: RUMCommandTarget) {
        monitor.process(command: RUMStartViewCommand(
            time: snapshotDate,
            identity: ViewIdentifier(key),
            name: key,
            path: key,
            globalAttributes: [:],
            attributes: [:],
            instrumentationType: .manual,
            target: target
        ))
    }

    func testSceneSnapshots_publishBothOwnersAndRepresentativeFromOneSession() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let monitor = sceneMonitor(scope: FeatureScopeMock(), clock: clock)
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))

        let a = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let b = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        let representative = try XCTUnwrap(monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertEqual(a.viewName, "a")
        XCTAssertEqual(b.viewName, "b")
        XCTAssertNotEqual(a.viewID, b.viewID)
        XCTAssertEqual(a.sessionID, b.sessionID)
        XCTAssertEqual(representative.viewID, b.viewID)
        XCTAssertEqual(monitor.activeView.id, b.viewID)
        let viewID = try XCTUnwrap(a.viewID.flatMap(UUID.init(uuidString:)))
        XCTAssertEqual(monitor.rumContextSnapshot(for: .view(.init(rawValue: viewID)))?.viewID, a.viewID)
    }

    func testSceneSnapshots_publishOnlyAfterDeferredCommandProcessing() throws {
        let scope = FeatureScopeMock(deferEventWriteContext: true)
        let monitor = sceneMonitor(scope: scope, clock: DateProviderMock(now: snapshotDate))
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        scope.flushDeferredEventWriteContexts()
        let a = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneB)))
        XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewID, a.viewID)
        scope.flushDeferredEventWriteContexts()
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewName, "b")
        XCTAssertEqual(
            monitor.rumContextSnapshot(for: .scene(sceneA))?.sessionID,
            monitor.rumContextSnapshot(for: .scene(sceneB))?.sessionID
        )
    }

    func testSceneSnapshots_unknownNoneAndStoppedOwnersAreAbsent() throws {
        let monitor = sceneMonitor(scope: FeatureScopeMock(), clock: DateProviderMock(now: snapshotDate))
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))
        let a = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let viewID = try XCTUnwrap(a.viewID.flatMap(UUID.init(uuidString:)))
        XCTAssertNil(monitor.rumContextSnapshot(for: .none))
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(.init(rawValue: "unknown"))))
        XCTAssertNil(monitor.rumContextSnapshot(for: .view(.init(rawValue: UUID()))))
        var stop = RUMStopViewCommand(time: snapshotDate, globalAttributes: [:], attributes: [:], identity: ViewIdentifier("a"))
        stop.target = .scene(sceneA)
        monitor.process(command: stop)
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertNil(monitor.rumContextSnapshot(for: .view(.init(rawValue: viewID))))
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewName, "b")
    }

    func testSceneSnapshots_expireWithoutCommandProcessing() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let elapsedClock = MonotonicClockMock()
        let monitor = sceneMonitor(scope: FeatureScopeMock(context: .mockWith(sdkInitDate: snapshotDate)), clock: clock, monotonicClock: elapsedClock)
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        let session = try XCTUnwrap(monitor.applicationScope.activeSession)
        XCTAssertEqual(session.sessionStartTime, snapshotDate)
        XCTAssertEqual(session.sessionStart, 0)
        XCTAssertEqual(session.lastInteraction, 0)
        XCTAssertNotNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        clock.now = snapshotDate.addingTimeInterval(15 * 60 + 1)
        // Event-date movement cannot expire a session while its elapsed clock is unchanged.
        XCTAssertNotNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        elapsedClock.advance(by: 15 * 60 + 1)
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertNil(monitor.rumContextSnapshot(for: .processRepresentative))

        let activeClock = DateProviderMock(now: snapshotDate)
        let active = sceneMonitor(scope: FeatureScopeMock(context: .mockWith(sdkInitDate: snapshotDate)), clock: activeClock)
        startSnapshotView(active, key: "active", target: .scene(sceneA))
        let sessionID = try XCTUnwrap(active.rumContextSnapshot(for: .scene(sceneA))?.sessionID)
        for minute in stride(from: 14, through: 238, by: 14) {
            activeClock.now = snapshotDate.addingTimeInterval(TimeInterval(minute * 60))
            active.addAction(type: .tap, name: "keep-alive", attributes: [:])
        }
        activeClock.now = snapshotDate.addingTimeInterval(239 * 60)
        active.addAction(type: .tap, name: "last-interaction", attributes: [:])
        XCTAssertEqual(active.rumContextSnapshot(for: .scene(sceneA))?.sessionID, sessionID)
        XCTAssertEqual(active.rumContextSnapshot(for: .processRepresentative)?.sessionID, sessionID)
        let activeSession = try XCTUnwrap(active.applicationScope.activeSession)
        XCTAssertEqual(activeSession.sessionStartTime, snapshotDate)
        XCTAssertEqual(activeSession.lastInteraction, activeClock.now.timeIntervalSinceReferenceDate)
        let afterMaximum = snapshotDate.addingTimeInterval(4 * 60 * 60 + 1)
        XCTAssertFalse(RUMSessionScope.hasTimedOut(lastInteraction: activeSession.lastInteraction, now: afterMaximum.timeIntervalSinceReferenceDate))
        XCTAssertTrue(RUMSessionScope.hasExpired(sessionStart: activeSession.sessionStart, now: afterMaximum.timeIntervalSinceReferenceDate))
        activeClock.now = afterMaximum
        XCTAssertNil(active.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertNil(active.rumContextSnapshot(for: .processRepresentative))
    }

    func testWebViewSessionSnapshot_remainsAvailableAfterLastViewStops() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let monitor = sceneMonitor(scope: FeatureScopeMock(), clock: clock)
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        let original = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        var stop = RUMStopViewCommand(time: snapshotDate, globalAttributes: [:], attributes: [:], identity: ViewIdentifier("a"))
        stop.target = .scene(sceneA)
        monitor.process(command: stop)
        let liveSession = try XCTUnwrap(monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertEqual(liveSession.sessionID, original.sessionID)
        XCTAssertNil(liveSession.viewID)
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
    }

    func testWebViewSessionSnapshot_defaultDateRejectsMaximumDurationWithRecentInteraction() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let monitor = sceneMonitor(scope: FeatureScopeMock(context: .mockWith(sdkInitDate: snapshotDate)), clock: clock)
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        let original = try XCTUnwrap(monitor.rumContextSnapshot(for: .processRepresentative))
        for minute in stride(from: 10, through: 230, by: 10) {
            clock.now = snapshotDate.addingTimeInterval(TimeInterval(minute * 60))
            monitor.process(command: RUMAddUserActionCommand(target: .scene(sceneA), time: clock.now, attributes: [:], instrumentation: .manual, actionType: .custom, name: "keep-session-active"))
            XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.sessionID, original.sessionID)
        }
        clock.now = snapshotDate.addingTimeInterval(4 * 60 * 60 + 1)
        let session = try XCTUnwrap(monitor.applicationScope.activeSession)
        XCTAssertFalse(RUMSessionScope.hasTimedOut(lastInteraction: session.lastInteraction, now: clock.now.timeIntervalSinceReferenceDate))
        XCTAssertTrue(RUMSessionScope.hasExpired(sessionStart: session.sessionStart, now: clock.now.timeIntervalSinceReferenceDate))
        XCTAssertNil(monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertEqual(session.sessionUUID.toRUMDataFormat, original.sessionID)
    }

    func testSceneSnapshots_sessionStopClearsAllOwners() {
        let monitor = sceneMonitor(scope: FeatureScopeMock(), clock: DateProviderMock(now: snapshotDate))
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))
        monitor.stopSession()
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneB)))
        XCTAssertNil(monitor.rumContextSnapshot(for: .processRepresentative))
    }

    func testSceneSnapshots_rolloverDoesNotExposeOldViewOrSession() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let monitor = sceneMonitor(scope: FeatureScopeMock(), clock: clock)
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        let old = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let oldViewID = try XCTUnwrap(old.viewID.flatMap(UUID.init(uuidString:)))
        clock.now = snapshotDate.addingTimeInterval(4 * 60 * 60 + 1)
        monitor.startView(key: "new", name: nil, attributes: [:])
        let new = try XCTUnwrap(monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertNotEqual(old.sessionID, new.sessionID)
        XCTAssertNil(monitor.rumContextSnapshot(for: .view(.init(rawValue: oldViewID))))
    }

    func testSceneSnapshots_processOwnedViewCanBeReadByViewID() throws {
        let monitor = sceneMonitor(scope: FeatureScopeMock(), clock: DateProviderMock(now: snapshotDate))
        monitor.startView(key: "process", name: nil, attributes: [:])
        let context = try XCTUnwrap(monitor.rumContextSnapshot(for: .processRepresentative))
        let viewID = try XCTUnwrap(context.viewID.flatMap(UUID.init(uuidString:)))
        XCTAssertEqual(monitor.rumContextSnapshot(for: .view(.init(rawValue: viewID)))?.viewName, "process")
    }

    func testResolvedOff_hasNoSceneSnapshotsOrExecutionReads() {
        let scope = MonitorOwnerScope()
        var reads = 0
        let monitor = Monitor(
            dependencies: .mockWith(featureScope: scope, featureFlags: [.multiSceneTracking: false]),
            dateProvider: DateProviderMock(now: snapshotDate),
            executionContextProvider: { _ in reads += 1; return nil }
        )
        monitor.startView(key: "legacy", name: nil, attributes: [:])
        monitor.addError(error: NSError(domain: "test", code: 1), source: .source, attributes: [:])
        monitor.addTiming(name: "timing")
        XCTAssertFalse(monitor.isMultiSceneTrackingEnabled)
        XCTAssertNil(monitor.currentExecutionContext)
        XCTAssertNil(monitor.rumContextHandoffOwner)
        XCTAssertNil(monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertEqual(scope.ownerReads, 0)
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(monitor.activeView.name, "legacy")
        XCTAssertEqual(scope.base.eventsWritten(ofType: RUMErrorEvent.self).count, 1)
    }

    func testResolvedOff_discardsExecutionProviderCapture() {
        final class Capture {}
        var capture: Capture? = Capture()
        weak var weakCapture = capture
        let monitor = Monitor(
            dependencies: .mockWith(featureFlags: [.multiSceneTracking: false]),
            dateProvider: DateProviderMock(),
            executionContextProvider: { [capture] _ in _ = capture; return nil }
        )
        capture = nil
        XCTAssertNil(weakCapture)
        XCTAssertFalse(monitor.isMultiSceneTrackingEnabled)
    }

    func testNoneTarget_completesErrorOnceWithoutPublishingContext() {
        let scope = MonitorOwnerScope()
        let monitor = sceneMonitor(scope: scope, clock: DateProviderMock(now: snapshotDate))
        var completions = 0
        var error = RUMAddCurrentViewErrorCommand(
            time: snapshotDate,
            message: "none",
            type: nil,
            stack: nil,
            source: .source,
            globalAttributes: [:],
            attributes: [:],
            completionHandler: { completions += 1 }
        )
        error.target = .none
        monitor.process(command: error)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(scope.writes, 0)
        XCTAssertEqual(scope.contextWrites, 0)
        XCTAssertTrue(monitor.applicationScope.sessionScopes.isEmpty)
    }

    func testReleasedMonitor_completesDeferredOnErrorOnce() {
        let scope = FeatureScopeMock(deferEventWriteContext: true)
        var monitor: Monitor? = sceneMonitor(scope: scope, clock: DateProviderMock(now: snapshotDate))
        var completions = 0
        monitor?.addError(
            error: NSError(domain: "test", code: 1),
            source: .source,
            attributes: [:],
            completionHandler: { completions += 1 }
        )
        weak var weakMonitor = monitor
        monitor = nil
        XCTAssertNil(weakMonitor)
        scope.flushDeferredEventWriteContexts()
        XCTAssertEqual(completions, 1)
        XCTAssertTrue(scope.eventsWritten.isEmpty)
    }

    func testExecutionProvider_receivesFeatureOwnerOncePerManualCall() {
        let scope = MonitorOwnerScope()
        var owners: [RUMContextHandoff.Owner] = []
        let monitor = Monitor(
            dependencies: .mockWith(
                featureScope: scope,
                trackBackgroundEvents: false,
                featureFlags: [.multiSceneTracking: true]
            ),
            dateProvider: DateProviderMock(now: snapshotDate),
            executionContextProvider: { owner in
                owners.append(owner)
                return .init(rumContext: nil, sceneIdentifier: "scene-a", hasPendingUserAction: false, excludedUserActionID: nil)
            }
        )
        monitor.startView(key: "owned", name: nil, attributes: [:])
        monitor.addAction(type: .tap, name: "tap", attributes: [:])
        XCTAssertEqual(scope.ownerReads, 2)
        XCTAssertEqual(owners.count, 2)
        XCTAssertIdentical(owners.first, owners.last)
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneA))?.viewName, "owned")
    }

    func testExecutionProvider_customScopeFallsBackWithoutInvokingProvider() {
        var reads = 0
        let monitor = Monitor(
            dependencies: .mockWith(
                featureScope: FeatureScopeMock(),
                trackBackgroundEvents: false,
                featureFlags: [.multiSceneTracking: true]
            ),
            dateProvider: DateProviderMock(now: snapshotDate),
            executionContextProvider: { _ in reads += 1; return nil }
        )
        monitor.startView(key: "fallback", name: nil, attributes: [:])
        XCTAssertEqual(reads, 0)
        XCTAssertNil(monitor.rumContextHandoffOwner)
        XCTAssertEqual(monitor.rumContextSnapshot(for: .processRepresentative)?.viewName, "fallback")
    }

    func testManualResource_completionKeepsCapturedStartOwnerAfterContextChanges() throws {
        let scope = MonitorOwnerScope()
        let clock = DateProviderMock(now: snapshotDate)
        var scene = "scene-a"
        let monitor = Monitor(
            dependencies: .mockWith(
                featureScope: scope,
                trackBackgroundEvents: false,
                viewCache: ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true),
                featureFlags: [.multiSceneTracking: true]
            ),
            dateProvider: clock,
            executionContextProvider: { _ in
                .init(rumContext: nil, sceneIdentifier: scene, hasPendingUserAction: false, excludedUserActionID: nil)
            }
        )
        monitor.startView(key: "a", name: nil, attributes: [:])
        let a = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        monitor.startResource(resourceKey: "request", httpMethod: .get, urlString: "https://example.com", attributes: [:])
        scene = "scene-b"
        monitor.startView(key: "b", name: nil, attributes: [:])
        let b = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        monitor.stopResource(resourceKey: "request", statusCode: 200, kind: .native, size: 1, attributes: [:])
        let resource = try XCTUnwrap(scope.base.eventsWritten(ofType: RUMResourceEvent.self).first)
        XCTAssertEqual(resource.view.id, a.viewID)
        XCTAssertNotEqual(resource.view.id, b.viewID)
        XCTAssertEqual(scope.base.eventsWritten(ofType: RUMResourceEvent.self).count, 1)
    }

    private func navigationMonitor(
        clock: DateProviderMock,
        cache: ViewCache,
        context: @escaping () -> RUMContextHandoff.CurrentValue?
    ) -> Monitor {
        Monitor(
            dependencies: .mockWith(
                featureScope: MonitorOwnerScope(),
                trackBackgroundEvents: false,
                viewCache: cache,
                featureFlags: [.multiSceneTracking: true]
            ),
            dateProvider: clock,
            executionContextProvider: { _ in context() }
        )
    }

    func testManualNavigation_retainedViewOwnsStartAndStopWithoutReplacingPeer() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let cache = ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true)
        var context: RUMContextHandoff.CurrentValue?
        var reads = 0
        let monitor = navigationMonitor(clock: clock, cache: cache) { reads += 1; return context }
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))
        let a = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let b = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        var stop = RUMStopViewCommand(time: snapshotDate, globalAttributes: [:], attributes: [:], identity: ViewIdentifier("a"))
        stop.target = .scene(sceneA)
        monitor.process(command: stop)
        context = .init(rumContext: a, sceneIdentifier: "scene-b", hasPendingUserAction: false, excludedUserActionID: nil)
        XCTAssertEqual(cache.ownership(forViewID: try XCTUnwrap(a.viewID)), .scene(sceneA))
        monitor.startView(key: "new-a", name: nil, attributes: [:])
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneA))?.viewName, "new-a")
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, b.viewID)
        monitor.stopView(key: "new-a", attributes: [:])
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, b.viewID)
        XCTAssertEqual(reads, 2)
    }

    func testManualNavigation_unknownViewDoesNotAdoptOrStopPeer() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let cache = ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true)
        let unknown = RUMCoreContext.mockWith(viewID: UUID().uuidString)
        let monitor = navigationMonitor(clock: clock, cache: cache) {
            .init(rumContext: unknown, sceneIdentifier: nil, hasPendingUserAction: false, excludedUserActionID: nil)
        }
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))
        let b = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        monitor.startView(key: "unknown", name: nil, attributes: [:])
        monitor.stopView(key: "b", attributes: [:])
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, b.viewID)
        XCTAssertEqual(monitor.applicationScope.activeSession?.viewScopes.filter(\.isActiveView).count, 1)
    }

    func testManualNavigation_expiredViewDoesNotAdoptOrStopPeer() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let cache = ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true)
        var context: RUMContextHandoff.CurrentValue?
        let monitor = navigationMonitor(clock: clock, cache: cache) { context }
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))
        let a = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let b = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        var stop = RUMStopViewCommand(time: snapshotDate, globalAttributes: [:], attributes: [:], identity: ViewIdentifier("a"))
        stop.target = .scene(sceneA)
        monitor.process(command: stop)
        clock.now = snapshotDate.addingTimeInterval(3 * 60 + 1)
        context = .init(rumContext: a, sceneIdentifier: nil, hasPendingUserAction: false, excludedUserActionID: nil)
        XCTAssertEqual(cache.ownership(forViewID: try XCTUnwrap(a.viewID)), .unknown)
        monitor.startView(key: "expired", name: nil, attributes: [:])
        monitor.stopView(key: "b", attributes: [:])
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewID, b.viewID)
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
    }

    func testManualNavigation_knownLegacyViewPreservesRepresentativeFallback() throws {
        let clock = DateProviderMock(now: snapshotDate)
        let cache = ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true)
        var context: RUMContextHandoff.CurrentValue?
        let monitor = navigationMonitor(clock: clock, cache: cache) { context }
        startSnapshotView(monitor, key: "legacy", target: .processRepresentative)
        let legacy = try XCTUnwrap(monitor.rumContextSnapshot(for: .processRepresentative))
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))
        context = .init(rumContext: legacy, sceneIdentifier: nil, hasPendingUserAction: false, excludedUserActionID: nil)
        XCTAssertEqual(cache.ownership(forViewID: try XCTUnwrap(legacy.viewID)), .legacy)
        monitor.startView(key: "replacement", name: nil, attributes: [:])
        XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(sceneB))?.viewName, "replacement")
    }

    func testManualError_explicitTargetOverridesInferredPeerWithoutDuplicating() throws {
        let scope = MonitorOwnerScope()
        let monitor = Monitor(
            dependencies: .mockWith(
                featureScope: scope,
                trackBackgroundEvents: false,
                featureFlags: [.multiSceneTracking: true]
            ),
            dateProvider: DateProviderMock(now: snapshotDate),
            executionContextProvider: { _ in
                .init(rumContext: nil, sceneIdentifier: "scene-b", hasPendingUserAction: false, excludedUserActionID: nil)
            }
        )
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        startSnapshotView(monitor, key: "b", target: .scene(sceneB))
        let a = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneA)))
        let b = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(sceneB)))
        var completions = 0
        monitor.addError(
            error: NSError(domain: "test", code: 1),
            source: .source,
            attributes: [:],
            completionHandler: { completions += 1 },
            explicitTarget: .scene(sceneA)
        )
        let error = try XCTUnwrap(scope.base.eventsWritten(ofType: RUMErrorEvent.self).first)
        XCTAssertEqual(error.view.id, a.viewID)
        XCTAssertNotEqual(error.view.id, b.viewID)
        XCTAssertEqual(scope.base.eventsWritten(ofType: RUMErrorEvent.self).count, 1)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testControllerViewCalls_fromBackgroundNeverReadUIKit() {
        for enabled in [false, true] {
            let monitor = MonitorCommandRecorder(enabled: enabled)
            let controller = MonitorControllerReadSpy()
            let completed = expectation(description: "background controller commands")
            DispatchQueue.global().async {
                monitor.startView(viewController: controller, name: "controller", attributes: [:])
                monitor.stopView(viewController: controller, attributes: [:])
                completed.fulfill()
            }
            waitForExpectations(timeout: 5)
            XCTAssertEqual(controller.viewReads, 0)
            XCTAssertEqual(monitor.commands.map(\.target), [.processRepresentative, .processRepresentative])
        }
    }

    @MainActor
    func testManualSceneHandler_isBoundOnceAndOwnsStartAndStop() {
        let monitor = MonitorCommandRecorder(enabled: true)
        let first = MonitorManualHandler()
        let second = MonitorManualHandler()
        monitor.bind(sceneTargetedManualViewHandler: first)
        monitor.bind(sceneTargetedManualViewHandler: second)
        monitor.startView(key: "manual", name: nil, attributes: [:], sceneIdentifier: sceneA)
        monitor.stopView(key: "manual", attributes: [:], sceneIdentifier: sceneA)
        XCTAssertEqual(first.calls, ["start:manual:scene-a", "stop:manual:scene-a"])
        XCTAssertTrue(second.calls.isEmpty)
        XCTAssertTrue(monitor.commands.isEmpty)
    }

    @MainActor
    func testManualSceneHandler_missingAtFirstUseFreezesProcessFallback() {
        let monitor = MonitorCommandRecorder(enabled: true)
        monitor.startView(key: "manual", name: nil, attributes: [:], sceneIdentifier: sceneA)
        let late = MonitorManualHandler()
        monitor.bind(sceneTargetedManualViewHandler: late)
        monitor.stopView(key: "manual", attributes: [:], sceneIdentifier: sceneA)
        XCTAssertEqual(monitor.commands.map(\.target), [.processRepresentative, .processRepresentative])
        XCTAssertTrue(late.calls.isEmpty)
    }

    @MainActor
    func testManualSceneHandler_releaseDoesNotChangeStartStopOwner() {
        let monitor = MonitorCommandRecorder(enabled: true)
        var handler: MonitorManualHandler? = MonitorManualHandler()
        weak var weakHandler = handler
        monitor.bind(sceneTargetedManualViewHandler: handler!)
        monitor.startView(key: "manual", name: nil, attributes: [:], sceneIdentifier: sceneA)
        XCTAssertEqual(handler?.calls.count, 1)
        handler = nil
        XCTAssertNil(weakHandler)
        monitor.stopView(key: "manual", attributes: [:], sceneIdentifier: sceneA)
        XCTAssertTrue(monitor.commands.isEmpty)
    }

    @MainActor
    func testManualSceneHandler_offPreservesProcessFallback() {
        let monitor = MonitorCommandRecorder(enabled: false)
        let handler = MonitorManualHandler()
        monitor.bind(sceneTargetedManualViewHandler: handler)
        monitor.startView(key: "manual", name: nil, attributes: [:], sceneIdentifier: sceneA)
        monitor.stopView(key: "manual", attributes: [:], sceneIdentifier: sceneA)
        XCTAssertTrue(handler.calls.isEmpty)
        XCTAssertEqual(monitor.commands.map(\.target), [.processRepresentative, .processRepresentative])
    }
}

private final class MonitorOwnerScope: FeatureScope, RUMContextHandoffOwnerProviding, @unchecked Sendable {
    let base = FeatureScopeMock()
    private let owner = RUMContextHandoff.Owner()
    var ownerReads = 0
    var writes = 0
    var contextWrites = 0
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { ownerReads += 1; return owner }
    var dataStore: DataStore { base.dataStore }
    var telemetry: Telemetry { base.telemetry }
    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        writes += 1
        base.eventWriteContext(bypassConsent: bypassConsent, block)
    }
    func context(_ block: @escaping (DatadogContext) -> Void) { base.context(block) }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {
        contextWrites += 1
        base.set(context: context)
    }
    func set(anonymousId: String?) { base.set(anonymousId: anonymousId) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { base.send(message: message, else: fallback) }
}

private final class MonitorCommandRecorder: Monitor {
    var commands: [RUMCommand] = []
    init(enabled: Bool) {
        super.init(dependencies: .mockWith(featureFlags: [.multiSceneTracking: enabled]), dateProvider: DateProviderMock())
    }
    override func process(command: RUMCommand) { commands.append(command) }
}

private final class MonitorControllerReadSpy: UIViewController {
    var viewReads = 0
    override var viewIfLoaded: UIView? { viewReads += 1; return nil }
}

@MainActor
private final class MonitorManualHandler: RUMSceneTargetedManualViewHandling {
    var calls: [String] = []
    func startView(key: String, name: String?, attributes: [AttributeKey: AttributeValue], sceneIdentifier: RUMSceneIdentifier) {
        calls.append("start:\(key):\(sceneIdentifier.rawValue)")
    }
    func stopView(key: String, attributes: [AttributeKey: AttributeValue], sceneIdentifier: RUMSceneIdentifier) {
        calls.append("stop:\(key):\(sceneIdentifier.rawValue)")
    }
}
#endif

#if os(iOS)

@available(iOS 27.0, *)
final class AutomaticContinuousActionOwnershipTests: XCTestCase {
    func testContinuousActionOwnership_claimsGeneratedActionAndCompletesOnce() throws {
        let f = ScrollActionFixture()
        let view = try f.view("a")
        let receipt = f.receipt()
        f.start(receipt)
        let action = try XCTUnwrap(view.userActionScope)
        let claim = try XCTUnwrap(receipt.claim)
        XCTAssertEqual(claim.sessionID, f.monitor.applicationScope.activeSession?.sessionUUID)
        XCTAssertEqual(claim.viewID, view.viewUUID)
        XCTAssertEqual(claim.actionID, action.actionUUID)
        f.start(receipt)
        XCTAssertTrue(view.userActionScope === action)
        f.stop(receipt)
        f.stop(receipt)
        XCTAssertTrue(receipt.isClosed)
        XCTAssertNil(view.userActionScope)
        let event = try XCTUnwrap(f.events.first)
        XCTAssertEqual(f.events.count, 1)
        XCTAssertEqual(event.action.id, claim.actionID.toRUMDataFormat)
        XCTAssertEqual(event.view.id, claim.viewID.toRUMDataFormat)
        XCTAssertEqual(event.session.id, claim.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.action.target?.name, "scroll-stop")
        XCTAssertEqual(event.action.type, .swipe)
        XCTAssertEqual(event.context?.contextInfo["action.gesture.direction"] as? String, "down")
    }

    func testContinuousActionOwnership_ignoredStartDoesNotFinishManualAction() throws {
        let f = ScrollActionFixture()
        let view = try f.view("a")
        f.manualStart()
        let manual = try XCTUnwrap(view.userActionScope)
        let receipt = f.receipt()
        f.start(receipt)
        XCTAssertNil(receipt.claim)
        f.stop(receipt)
        XCTAssertTrue(view.userActionScope === manual)
        XCTAssertEqual(manual.name, "manual")
        XCTAssertEqual(manual.actionType, .custom)
        XCTAssertTrue(f.events.isEmpty)
    }

    func testContinuousActionOwnership_staleStopDoesNotFinishReplacementInSameView() throws {
        let f = ScrollActionFixture()
        let view = try f.view("a")
        let receipt = f.receipt()
        f.start(receipt)
        let admitted = try XCTUnwrap(receipt.claim)
        var direct = RUMStopUserActionCommand.mockWith(time: f.clock.now)
        direct.target = .view(view.viewUUID)
        f.monitor.process(command: direct)
        f.manualStart()
        let replacement = try XCTUnwrap(view.userActionScope)
        XCTAssertNotEqual(replacement.actionUUID, admitted.actionID)
        f.stop(receipt)
        XCTAssertTrue(view.userActionScope === replacement)
        XCTAssertEqual(replacement.name, "manual")
        XCTAssertEqual(f.events.count, 1)
    }

    func testContinuousActionOwnership_navigationCannotStopNewViewAction() throws {
        let f = ScrollActionFixture()
        let first = try f.view("a")
        let receipt = f.receipt()
        f.start(receipt)
        let next = try f.view("next-a")
        f.manualStart()
        let nextAction = try XCTUnwrap(next.userActionScope)
        f.stop(receipt)
        XCTAssertTrue(next.userActionScope === nextAction)
        XCTAssertEqual(f.events.count, 1)
        XCTAssertEqual(f.events.first?.view.id, first.viewUUID.toRUMDataFormat)
        XCTAssertNotEqual(receipt.claim?.viewID, next.viewUUID)
    }

    func testContinuousActionOwnership_missingViewStartCannotAdoptLaterView() throws {
        let f = ScrollActionFixture()
        _ = try f.view("b", scene: "b")
        let receipt = f.receipt()
        f.start(receipt)
        XCTAssertNil(receipt.claim)
        let later = try f.view("a")
        let sessionID = f.monitor.applicationScope.activeSession?.sessionUUID
        f.start(receipt)
        XCTAssertNil(later.userActionScope)
        XCTAssertEqual(f.monitor.applicationScope.activeSession?.sessionUUID, sessionID)
        f.stop(receipt)
        XCTAssertTrue(receipt.isClosed)
        XCTAssertTrue(f.events.isEmpty)
    }

    func testContinuousActionOwnership_terminalBeforeStartCannotCreateSession() {
        let f = ScrollActionFixture()
        let receipt = f.receipt()
        f.stop(receipt)
        XCTAssertTrue(receipt.isClosed)
        XCTAssertTrue(f.monitor.applicationScope.sessionScopes.isEmpty)
        f.start(receipt)
        XCTAssertNil(receipt.claim)
        XCTAssertTrue(f.monitor.applicationScope.sessionScopes.isEmpty)
    }

    func testContinuousActionOwnership_expiredSessionStopCannotRefreshOrAdopt() throws {
        for maximumDuration in [false, true] {
            let f = ScrollActionFixture()
            let view = try f.view("a")
            let receipt = f.receipt()
            f.start(receipt)
            var resource = RUMStartResourceCommand.mockWith(resourceKey: "held", time: f.clock.now)
            resource.target = .scene(.init(rawValue: "a"))
            f.monitor.process(command: resource)
            let action = try XCTUnwrap(view.userActionScope)
            let session = try XCTUnwrap(f.monitor.applicationScope.activeSession)
            if maximumDuration {
                for minute in Array(stride(from: 14, through: 238, by: 14)) + [239] {
                    f.clock.now = session.sessionStartTime.addingTimeInterval(TimeInterval(minute * 60))
                    var interaction = RUMAddUserActionCommand.mockWith(time: f.clock.now, actionType: .custom, name: "activity")
                    interaction.target = .scene(.init(rawValue: "a"))
                    f.monitor.process(command: interaction)
                    XCTAssertTrue(f.monitor.applicationScope.activeSession === session)
                    XCTAssertEqual(session.lastInteraction, f.clock.now.timeIntervalSinceReferenceDate)
                    XCTAssertNil(session.endReason)
                }
                f.clock.now = session.sessionStartTime.addingTimeInterval(4 * 60 * 60 + 1)
                XCTAssertFalse(RUMSessionScope.hasTimedOut(lastInteraction: session.lastInteraction, now: f.clock.now.timeIntervalSinceReferenceDate))
                XCTAssertTrue(RUMSessionScope.hasExpired(sessionStart: session.sessionStart, now: f.clock.now.timeIntervalSinceReferenceDate))
            } else {
                f.clock.now = Date(timeIntervalSinceReferenceDate: session.lastInteraction + 15 * 60)
                XCTAssertTrue(RUMSessionScope.hasTimedOut(lastInteraction: session.lastInteraction, now: f.clock.now.timeIntervalSinceReferenceDate))
                XCTAssertFalse(RUMSessionScope.hasExpired(sessionStart: session.sessionStart, now: f.clock.now.timeIntervalSinceReferenceDate))
            }
            f.stop(receipt)
            XCTAssertTrue(receipt.isClosed)
            XCTAssertTrue(f.monitor.applicationScope.activeSession === session)
            XCTAssertTrue(view.userActionScope === action)
            XCTAssertEqual(action.name, "scroll-start")
            XCTAssertNil(session.endReason)
        }
    }

    func testContinuousActionOwnership_expiredActionCannotAdoptLaterAction() throws {
        let f = ScrollActionFixture()
        let view = try f.view("a")
        let receipt = f.receipt()
        f.start(receipt)
        let claim = try XCTUnwrap(receipt.claim)
        let sessionID = f.monitor.applicationScope.activeSession?.sessionUUID
        f.clock.now = f.clock.now.addingTimeInterval(11)
        f.stop(receipt)
        XCTAssertNil(view.userActionScope)
        XCTAssertEqual(f.monitor.applicationScope.activeSession?.sessionUUID, sessionID)
        XCTAssertEqual(f.events.first?.action.id, claim.actionID.toRUMDataFormat)
        XCTAssertEqual(f.events.first?.action.target?.name, "scroll-start")
        f.manualStart()
        let replacement = view.userActionScope
        f.stop(receipt)
        XCTAssertTrue(view.userActionScope === replacement)
        XCTAssertEqual(f.events.count, 1)
    }

    func testContinuousActionOwnership_foreignAndInvalidatedLifetimesCannotAdopt() throws {
        let a = ScrollActionFixture()
        let b = ScrollActionFixture()
        let view = try b.view("a")
        let foreign = a.receipt()
        b.start(foreign)
        XCTAssertTrue(foreign.isClosed)
        XCTAssertNil(view.userActionScope)
        let invalid = b.receipt()
        b.owner.invalidate()
        b.start(invalid)
        b.stop(invalid)
        XCTAssertTrue(invalid.isClosed)
        XCTAssertNil(view.userActionScope)
        XCTAssertTrue(b.events.isEmpty)
    }

    func testContinuousActionOwnership_nonActionAndSnapshotCannotBorrowRecipient() throws {
        let f = ScrollActionFixture()
        let view = try f.view("a")
        let receipt = f.receipt()
        XCTAssertNil(f.monitor.rumContextSnapshot(for: .continuousAction(receipt)))
        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: f.clock.now)
        error.target = .continuousAction(receipt)
        f.monitor.process(command: error)
        let nav = RUMStartViewCommand(time: f.clock.now, identity: ViewIdentifier("foreign"), name: "foreign", path: "foreign", globalAttributes: [:], attributes: [:], instrumentationType: .manual, target: .continuousAction(receipt))
        f.monitor.process(command: nav)
        if case .unresolved? = RUMSessionScope.resolveNavigationDestination(on: nav, representative: .init(rawValue: "a"), cache: f.monitor.applicationScope.dependencies.viewCache) {} else { XCTFail("Receipt navigation must stay unresolved") }
        XCTAssertTrue(view.isActiveView)
        XCTAssertNil(receipt.claim)
        XCTAssertTrue(f.mockScope.eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testContinuousActionOwnership_actualQueueClaimsAfterNilSnapshotWithoutBorrowingNavigation() throws {
        let clock = DateProviderMock(now: ScrollActionFixture.startDate)
        let context = ScrollActionFixture.context(at: clock.now)
        let core = DatadogCoreProxy(context: context)
        defer { try? core.flushAndTearDown() }
        try core.register(feature: DatadogRemoteFeatureMock())
        let scope = ScrollActionScope(base: core.scope(for: DatadogRemoteFeatureMock.self))
        let f = ScrollActionFixture(scope: scope, clock: clock)
        let blocked = expectation(description: "actual context queue blocked")
        let released = DispatchSemaphore(value: 0)
        scope.context { _ in
            blocked.fulfill()
            XCTAssertEqual(released.wait(timeout: .now() + 5), .success)
        }
        defer { released.signal() }
        wait(for: [blocked], timeout: 2)
        f.enqueueView("a")
        XCTAssertNil(f.monitor.rumContextSnapshot(for: .scene(.init(rawValue: "a"))))
        let receipt = f.receipt()
        f.start(receipt)
        f.enqueueView("next-a")
        f.manualStart()
        f.stop(receipt)
        let finished = expectation(description: "actual ordered receipt application")
        scope.context { _ in
            let claim = receipt.claim
            XCTAssertNotNil(claim)
            let next = f.monitor.applicationScope.activeSession?.viewScopes.last(where: { $0.isActiveView })
            XCTAssertNotEqual(claim?.viewID, next?.viewUUID)
            XCTAssertEqual(next?.userActionScope?.name, "manual")
            XCTAssertNotEqual(claim?.actionID, next?.userActionScope?.actionUUID)
            XCTAssertTrue(receipt.isClosed)
            finished.fulfill()
        }
        released.signal()
        wait(for: [finished], timeout: 5)
        let events = core.waitAndReturnEvents(ofFeature: DatadogRemoteFeatureMock.name, ofType: RUMActionEvent.self, timeout: .now() + 2)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.action.target?.name, "scroll-start")
    }

    func testContinuousActionOwnership_launchDeferralClosesOnlyWhenActuallyApplied() throws {
        for terminalFirst in [false, true] {
            var context = ScrollActionFixture.context(at: ScrollActionFixture.startDate)
            context.launchInfo.launchReason = .uncertain
            context.applicationStateHistory = .mockWith(initialState: .background, date: ScrollActionFixture.startDate)
            let scope = ScrollActionScope(base: FeatureScopeMock(context: context))
            let f = ScrollActionFixture(scope: scope)
            let receipt = f.receipt()
            if terminalFirst { f.stop(receipt) }
            f.enqueueView("a")
            f.start(receipt)
            if !terminalFirst { f.stop(receipt) }
            XCTAssertFalse(receipt.isClosed)
            XCTAssertNil(receipt.claim)
            XCTAssertTrue(f.monitor.applicationScope.sessionScopes.isEmpty)
            f.monitor.process(command: RUMHandleAppLifecycleEventCommand(time: f.clock.now, globalAttributes: [:], attributes: [:], event: .willEnterForeground))
            XCTAssertTrue(receipt.isClosed)
            XCTAssertEqual(receipt.claim == nil, terminalFirst)
            XCTAssertEqual(f.events.count, terminalFirst ? 0 : 1)
        }
    }

    func testContinuousActionOwnership_stoppedSessionCannotRefreshOnLateTerminal() throws {
        let f = ScrollActionFixture()
        let view = try f.view("a")
        let receipt = f.receipt()
        f.start(receipt)
        var resource = RUMStartResourceCommand.mockWith(resourceKey: "held", time: f.clock.now)
        resource.target = .scene(.init(rawValue: "a"))
        f.monitor.process(command: resource)
        let stopped = try XCTUnwrap(f.monitor.applicationScope.activeSession)
        f.monitor.process(command: RUMStopSessionCommand(time: f.clock.now))
        XCTAssertNil(f.monitor.applicationScope.activeSession)
        let sessions = f.monitor.applicationScope.sessionScopes.map(\.sessionUUID)
        let action = view.userActionScope
        f.stop(receipt)
        XCTAssertNil(f.monitor.applicationScope.activeSession)
        XCTAssertEqual(f.monitor.applicationScope.sessionScopes.map(\.sessionUUID), sessions)
        XCTAssertTrue(view.userActionScope === action)
        XCTAssertFalse(stopped.isActive)
        XCTAssertTrue(receipt.isClosed)
    }

    func testContinuousActionOwnership_retainedInactiveOrRemovedViewCannotAdoptNewAction() throws {
        for retainResource in [false, true] {
            let f = ScrollActionFixture()
            let first = try f.view("a")
            let receipt = f.receipt()
            f.start(receipt)
            if retainResource {
                var resource = RUMStartResourceCommand.mockWith(resourceKey: "held", time: f.clock.now)
                resource.target = .scene(.init(rawValue: "a"))
                f.monitor.process(command: resource)
            }
            let next = try f.view("next-a")
            XCTAssertFalse(first.isActiveView)
            XCTAssertEqual(f.monitor.applicationScope.activeSession?.viewScopes.contains(where: { $0 === first }), retainResource)
            XCTAssertNil(first.userActionScope)
            f.manualStart()
            let replacement = try XCTUnwrap(next.userActionScope)
            f.stop(receipt)
            XCTAssertTrue(next.userActionScope === replacement)
            XCTAssertEqual(f.events.count, 1)
            XCTAssertTrue(receipt.isClosed)
        }
    }

    func testContinuousActionOwnership_actualQueueConsumesMissingViewAndEarlierTerminal() throws {
        for earlierTerminal in [false, true] {
            let clock = DateProviderMock(now: ScrollActionFixture.startDate)
            let core = DatadogCoreProxy(context: ScrollActionFixture.context(at: clock.now))
            defer { try? core.flushAndTearDown() }
            try core.register(feature: DatadogRemoteFeatureMock())
            let scope = ScrollActionScope(base: core.scope(for: DatadogRemoteFeatureMock.self))
            let f = ScrollActionFixture(scope: scope, clock: clock)
            let entered = expectation(description: "actual context queue entered")
            let release = DispatchSemaphore(value: 0)
            scope.context { _ in entered.fulfill(); XCTAssertEqual(release.wait(timeout: .now() + 5), .success) }
            defer { release.signal() }
            wait(for: [entered], timeout: 2)
            let receipt = f.receipt()
            XCTAssertNil(f.monitor.rumContextSnapshot(for: .scene(.init(rawValue: "a"))))
            if earlierTerminal { f.stop(receipt) } else { f.enqueueView("b", scene: "b"); f.start(receipt) }
            let firstApplied = expectation(description: "first receipt boundary applied")
            scope.context { _ in
                if earlierTerminal {
                    XCTAssertTrue(receipt.isClosed)
                    XCTAssertTrue(f.monitor.applicationScope.sessionScopes.isEmpty)
                } else {
                    XCTAssertNil(receipt.claim)
                    XCTAssertFalse(receipt.isClosed)
                }
                firstApplied.fulfill()
            }
            f.enqueueView("a")
            f.start(receipt)
            f.stop(receipt)
            let finished = expectation(description: "late view cannot be adopted")
            scope.context { _ in
                XCTAssertNil(receipt.claim)
                XCTAssertTrue(receipt.isClosed)
                XCTAssertNil(f.monitor.applicationScope.activeSession?.viewScopes.last(where: { $0.viewName == "a" })?.userActionScope)
                finished.fulfill()
            }
            release.signal()
            wait(for: [firstApplied, finished], timeout: 5)
            XCTAssertTrue(core.waitAndReturnEvents(ofFeature: DatadogRemoteFeatureMock.name, ofType: RUMActionEvent.self, timeout: .now() + 0.1).isEmpty)
        }
    }

    func testContinuousActionOwnership_actualQueueRejectsOwnerInvalidatedAfterEnqueue() throws {
        let clock = DateProviderMock(now: ScrollActionFixture.startDate)
        let core = DatadogCoreProxy(context: ScrollActionFixture.context(at: clock.now))
        defer { try? core.flushAndTearDown() }
        try core.register(feature: DatadogRemoteFeatureMock())
        let scope = ScrollActionScope(base: core.scope(for: DatadogRemoteFeatureMock.self))
        let f = ScrollActionFixture(scope: scope, clock: clock)
        let entered = expectation(description: "actual context queue entered")
        let release = DispatchSemaphore(value: 0)
        scope.context { _ in entered.fulfill(); XCTAssertEqual(release.wait(timeout: .now() + 5), .success) }
        defer { release.signal() }
        wait(for: [entered], timeout: 2)
        f.enqueueView("a")
        let receipt = f.receipt()
        f.start(receipt)
        f.owner.invalidate()
        let finished = expectation(description: "stale lifetime rejected on queue")
        scope.context { _ in
            XCTAssertNil(receipt.claim)
            XCTAssertTrue(receipt.isClosed)
            XCTAssertNil(f.monitor.applicationScope.activeSession?.viewScopes.last?.userActionScope)
            finished.fulfill()
        }
        release.signal()
        wait(for: [finished], timeout: 5)
    }

    func testContinuousActionOwnership_sourceLessStartPreservesBackgroundEligibility() throws {
        var context = ScrollActionFixture.context(at: ScrollActionFixture.startDate)
        context.launchInfo.launchReason = .backgroundLaunch
        context.applicationStateHistory = .mockWith(initialState: .background, date: ScrollActionFixture.startDate)
        let f = ScrollActionFixture(scope: ScrollActionScope(base: FeatureScopeMock(context: context)), background: true)
        let receipt = f.receipt(scene: nil)
        f.start(receipt)
        let claim = try XCTUnwrap(receipt.claim)
        let view = try XCTUnwrap(f.monitor.applicationScope.activeSession?.viewScopes.first(where: { $0.viewUUID == claim.viewID }))
        XCTAssertEqual(view.viewPath, RUMOffViewEventsHandlingRule.Constants.backgroundViewURL)
        f.stop(receipt)
        XCTAssertEqual(f.events.first?.view.id, claim.viewID.toRUMDataFormat)
    }
}

@available(iOS 27.0, *)
private final class ScrollActionFixture {
    static let startDate = Date(timeIntervalSince1970: 1_600_000_000)
    let clock: DateProviderMock
    let scope: ScrollActionScope
    let monitor: Monitor
    var owner: RUMContextHandoff.Owner { scope.owner }
    var mockScope: FeatureScopeMock { scope.base as! FeatureScopeMock }
    var events: [RUMActionEvent] { mockScope.eventsWritten(ofType: RUMActionEvent.self) }

    static func context(at date: Date) -> DatadogContext {
        .mockWith(sdkInitDate: date, launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: date), applicationStateHistory: .mockWith(initialState: .active, date: date))
    }

    init(scope: ScrollActionScope? = nil, clock: DateProviderMock? = nil, background: Bool = false) {
        self.clock = clock ?? DateProviderMock(now: Self.startDate)
        self.scope = scope ?? ScrollActionScope(base: FeatureScopeMock(context: Self.context(at: self.clock.now)))
        monitor = Monitor(dependencies: .mockWith(featureScope: self.scope, trackBackgroundEvents: background, viewCache: ViewCache(dateProvider: self.clock, isMultiSceneTrackingEnabled: true), featureFlags: [.multiSceneTracking: true], monotonicClock: DateProviderMonotonicClock(dateProvider: self.clock)), dateProvider: self.clock)
    }

    func receipt(scene: String? = "a") -> RUMContinuousActionOwnership {
        .init(sceneIdentifier: scene.map { .init(rawValue: $0) }, owner: owner)
    }

    func enqueueView(_ key: String, scene: String = "a") {
        monitor.process(command: RUMStartViewCommand(time: clock.now, identity: ViewIdentifier(key), name: key, path: key, globalAttributes: [:], attributes: [:], instrumentationType: .manual, target: .scene(.init(rawValue: scene))))
    }

    func view(_ key: String, scene: String = "a") throws -> RUMViewScope {
        enqueueView(key, scene: scene)
        return try XCTUnwrap(monitor.applicationScope.activeSession?.viewScopes.last(where: { $0.isActiveView && $0.viewName == key }))
    }

    func start(_ receipt: RUMContinuousActionOwnership) {
        var command = RUMStartUserActionCommand.mockWith(time: clock.now, instrumentation: .uikit, actionType: .scroll, name: "scroll-start")
        command.target = .continuousAction(receipt)
        monitor.process(command: command)
    }

    func stop(_ receipt: RUMContinuousActionOwnership) {
        var command = RUMStopUserActionCommand.mockWith(time: clock.now, actionType: .swipe, name: "scroll-stop")
        command.attributes = ["action.gesture.direction": "down"]
        command.target = .continuousAction(receipt)
        monitor.process(command: command)
    }

    func manualStart() {
        var command = RUMStartUserActionCommand.mockWith(time: clock.now, actionType: .custom, name: "manual")
        command.target = .scene(.init(rawValue: "a"))
        monitor.process(command: command)
    }
}

private final class ScrollActionScope: FeatureScope, RUMContextHandoffOwnerProviding, @unchecked Sendable {
    let base: FeatureScope
    let owner = RUMContextHandoff.Owner()
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { owner }
    var dataStore: DataStore { base.dataStore }
    var telemetry: Telemetry { base.telemetry }
    init(base: FeatureScope) { self.base = base }
    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) { base.eventWriteContext(bypassConsent: bypassConsent, block) }
    func context(_ block: @escaping (DatadogContext) -> Void) { base.context(block) }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { base.set(context: context) }
    func set(anonymousId: String?) { base.set(anonymousId: anonymousId) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { base.send(message: message, else: fallback) }
}

@available(iOS 27.0, *)
final class CapturedLogErrorOwnershipTests: XCTestCase {
    private func capture(
        _ f: ScrollActionFixture,
        view: RUMViewScope,
        receipt: RUMContextHandoff.ActionReceipt? = nil
    ) throws -> RUMContextHandoff.Capture {
        let session = try XCTUnwrap(f.monitor.applicationScope.activeSession)
        let context = RUMCoreContext(
            applicationID: view.context.rumApplicationID,
            sessionID: session.sessionUUID.toRUMDataFormat,
            sessionSampler: session.sampler,
            viewID: view.viewUUID.toRUMDataFormat,
            userActionID: view.userActionScope?.actionUUID.toRUMDataFormat,
            viewServerTimeOffset: view.serverTimeOffset,
            viewPath: view.viewPath,
            viewName: view.viewName
        )
        return .init(owner: f.owner, value: .init(
            rumContext: context,
            sceneIdentifier: "a",
            hasPendingUserAction: receipt != nil,
            excludedUserActionID: nil,
            actionReceipt: receipt
        ))
    }

    private func mirror(_ capture: RUMContextHandoff.Capture, in f: ScrollActionFixture) {
        let error = RUMErrorMessage(
            time: f.clock.now,
            message: "captured log",
            source: "logger",
            type: nil,
            stack: nil,
            attributes: ["capture": "original"],
            binaryImages: nil
        )
        let receiver = ErrorMessageReceiver(featureScope: f.scope, monitor: f.monitor)
        XCTAssertTrue(receiver.receive(message: .payload(RUMCapturedErrorMessage(error: error, capture: capture)), from: NOPDatadogCore()))
    }

    func testCapturedMirrorKeepsOriginalViewAndAcceptedActionWhenAnotherSceneIsRepresentative() throws {
        let f = ScrollActionFixture()
        let a = try f.view("a")
        let original = try capture(f, view: a)
        let receipt = RUMContextHandoff.ActionReceipt(owner: f.owner, context: original.value.rumContext)
        let bound = try capture(f, view: a, receipt: receipt)
        var action = RUMStartUserActionCommand.mockWith(time: f.clock.now, instrumentation: .swiftuiAutomatic, actionType: .scroll, name: "original")
        action.target = .scene(.init(rawValue: "a"))
        action.actionReceipt = receipt
        f.monitor.process(command: action)
        let actionID = try XCTUnwrap(a.userActionScope).actionUUID.toRUMDataFormat
        var stop = RUMStopUserActionCommand.mockWith(time: f.clock.now, actionType: .scroll)
        stop.target = .scene(.init(rawValue: "a"))
        f.monitor.process(command: stop)
        f.manualStart()
        let replacement = try XCTUnwrap(a.userActionScope)
        let b = try f.view("b", scene: "b")
        mirror(bound, in: f)
        let error = try XCTUnwrap(f.mockScope.eventsWritten(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.session.id, bound.value.rumContext?.sessionID)
        XCTAssertEqual(error.view.id, a.viewUUID.toRUMDataFormat)
        XCTAssertEqual(error.action?.id, .string(value: actionID))
        XCTAssertNotEqual(error.view.id, b.viewUUID.toRUMDataFormat)
        XCTAssertTrue(a.userActionScope === replacement)
        var finish = RUMStopUserActionCommand.mockWith(time: f.clock.now, actionType: .custom)
        finish.target = .scene(.init(rawValue: "a"))
        f.monitor.process(command: finish)
        let later = try XCTUnwrap(f.events.last { $0.action.target?.name == "manual" })
        XCTAssertEqual(later.action.error?.count, 0)
    }

    func testCapturedMirrorCannotUseRemovedOrRetainedInactiveViewFallback() throws {
        for retainResource in [false, true] {
            let f = ScrollActionFixture()
            let originalView = try f.view("a")
            let bound = try capture(f, view: originalView)
            if retainResource {
                var resource = RUMStartResourceCommand.mockWith(resourceKey: "held", time: f.clock.now)
                resource.target = .scene(.init(rawValue: "a"))
                f.monitor.process(command: resource)
            }
            let replacement = try f.view("replacement")
            _ = try f.view("b", scene: "b")
            XCTAssertFalse(originalView.isActiveView)
            XCTAssertEqual(f.monitor.applicationScope.activeSession?.viewScopes.contains { $0 === originalView }, retainResource)
            let before = f.mockScope.eventsWritten.count
            mirror(bound, in: f)
            XCTAssertEqual(f.mockScope.eventsWritten.count, before)
            XCTAssertTrue(f.mockScope.eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
            XCTAssertTrue(replacement.isActiveView)
        }
    }

    func testCapturedMirrorCannotStartOrRefreshStoppedExpiredOrMaximumDurationSession() throws {
        for boundary in ["stopped", "timeout", "maximum"] {
            let f = ScrollActionFixture()
            let a = try f.view("a")
            let bound = try capture(f, view: a)
            if boundary == "stopped" {
                f.monitor.stopSession()
            } else {
                f.clock.now.addTimeInterval(boundary == "timeout" ? RUMSessionScope.Constants.sessionTimeoutDuration + 1 : RUMSessionScope.Constants.sessionMaxDuration + 1)
            }
            let sessions = f.monitor.applicationScope.sessionScopes.map(\.sessionUUID)
            let before = f.mockScope.eventsWritten.count
            mirror(bound, in: f)
            XCTAssertEqual(f.monitor.applicationScope.sessionScopes.map(\.sessionUUID), sessions)
            XCTAssertEqual(f.mockScope.eventsWritten.count, before)
            XCTAssertTrue(f.mockScope.eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
            if boundary != "stopped" {
                XCTAssertEqual(f.monitor.applicationScope.activeSession?.sessionUUID.toRUMDataFormat, bound.value.rumContext?.sessionID)
            }
            _ = try f.view("successor")
            let successor = try XCTUnwrap(f.monitor.applicationScope.activeSession)
            let afterNavigation = f.mockScope.eventsWritten.count
            mirror(bound, in: f)
            XCTAssertTrue(f.monitor.applicationScope.activeSession === successor)
            XCTAssertEqual(f.mockScope.eventsWritten.count, afterNavigation)
        }
    }

    func testCapturedMirrorPendingRejectedAndNilActionCannotBorrowLaterAction() throws {
        for mode in ["pending", "rejected", "nil"] {
            let f = ScrollActionFixture()
            let a = try f.view("a")
            let original = try capture(f, view: a)
            let receipt = RUMContextHandoff.ActionReceipt(owner: f.owner, context: original.value.rumContext)
            if mode == "rejected" { receipt.reject() }
            let bound = try capture(f, view: a, receipt: mode == "nil" ? nil : receipt)
            f.manualStart()
            let later = try XCTUnwrap(a.userActionScope)
            mirror(bound, in: f)
            let error = try XCTUnwrap(f.mockScope.eventsWritten(ofType: RUMErrorEvent.self).last)
            XCTAssertEqual(error.view.id, a.viewUUID.toRUMDataFormat)
            XCTAssertNil(error.action)
            XCTAssertTrue(a.userActionScope === later)
            var finish = RUMStopUserActionCommand.mockWith(time: f.clock.now, actionType: .custom)
            finish.target = .scene(.init(rawValue: "a"))
            f.monitor.process(command: finish)
            XCTAssertEqual(f.events.last?.action.error?.count, 0)
        }
    }

    func testCapturedMirrorValidNilAndForeignOwnerDoNotBorrowRepresentativeView() throws {
        let f = ScrollActionFixture()
        let a = try f.view("a")
        let original = try capture(f, view: a)
        _ = try f.view("b", scene: "b")
        let foreign = RUMContextHandoff.Capture(owner: .init(), value: original.value)
        let nilContext = RUMContextHandoff.Capture(owner: f.owner, value: .init(rumContext: nil, sceneIdentifier: "a", hasPendingUserAction: false, excludedUserActionID: nil))
        let before = f.mockScope.eventsWritten.count
        mirror(foreign, in: f)
        mirror(nilContext, in: f)
        XCTAssertEqual(f.mockScope.eventsWritten.count, before)
        XCTAssertTrue(f.mockScope.eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
    }

    func testCapturedMirrorOwnerInvalidatedAfterActualQueueSubmissionHasNoEffect() throws {
        let clock = DateProviderMock(now: ScrollActionFixture.startDate)
        let core = DatadogCoreProxy(context: ScrollActionFixture.context(at: clock.now))
        defer { try? core.flushAndTearDown() }
        try core.register(feature: DatadogRemoteFeatureMock())
        let scope = ScrollActionScope(base: core.scope(for: DatadogRemoteFeatureMock.self))
        let f = ScrollActionFixture(scope: scope, clock: clock)
        f.enqueueView("a")
        let viewReady = expectation(description: "original view applied on actual queue")
        scope.context { _ in viewReady.fulfill() }
        wait(for: [viewReady], timeout: 5)
        let a = try XCTUnwrap(f.monitor.applicationScope.activeSession?.viewScopes.first { $0.viewName == "a" })
        let bound = try capture(f, view: a)
        let before = core.waitAndReturnEvents(ofFeature: DatadogRemoteFeatureMock.name, ofType: RUMErrorEvent.self).count
        let entered = expectation(description: "actual queue held")
        let release = DispatchSemaphore(value: 0)
        scope.context { _ in entered.fulfill(); XCTAssertEqual(release.wait(timeout: .now() + 5), .success) }
        defer { release.signal() }
        wait(for: [entered], timeout: 2)
        mirror(bound, in: f)
        f.owner.invalidate()
        let finished = expectation(description: "stale mirror consumed")
        scope.context { _ in finished.fulfill() }
        release.signal()
        wait(for: [finished], timeout: 5)
        let errors = core.waitAndReturnEvents(ofFeature: DatadogRemoteFeatureMock.name, ofType: RUMErrorEvent.self)
        XCTAssertEqual(errors.count, before)
        XCTAssertTrue(a.isActiveView)
        XCTAssertEqual(f.monitor.applicationScope.activeSession?.viewScopes.count, 1)
    }

    func testCapturedMirrorOwnerInvalidatedDuringLaunchDeferralDoesNotApply() throws {
        let f = ScrollActionFixture()
        let a = try f.view("a")
        let bound = try capture(f, view: a)
        var uncertain = f.mockScope.contextMock
        uncertain.launchInfo.launchReason = .uncertain
        uncertain.applicationStateHistory = .mockWith(initialState: .background, date: f.clock.now)
        f.mockScope.contextMock = uncertain
        mirror(bound, in: f)
        XCTAssertTrue(f.mockScope.eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
        f.owner.invalidate()
        f.monitor.process(command: RUMHandleAppLifecycleEventCommand(time: f.clock.now, globalAttributes: [:], attributes: [:], event: .willEnterForeground))
        XCTAssertTrue(f.mockScope.eventsWritten(ofType: RUMErrorEvent.self).isEmpty)
        XCTAssertEqual(f.monitor.applicationScope.activeSession?.viewScopes.first { $0.viewName == "a" }?.viewUUID, a.viewUUID)
    }
}

@available(iOS 27.0, *)
final class CapturedFlagEvaluationOwnershipTests: XCTestCase {
    private func viewsWritten(in scope: FeatureScopeMock) throws -> [RUMViewEvent] {
        var viewsBySession: [String: [String: RUMViewEvent]] = [:]
        var views: [RUMViewEvent] = []

        for event in scope.eventsWritten {
            if let view = event as? RUMViewEvent {
                viewsBySession[view.session.id, default: [:]][view.view.id] = view
                views.append(view)
            } else if let update = event as? RUMViewUpdateEvent {
                let baseline = try XCTUnwrap(
                    viewsBySession[update.session.id]?[update.view.id],
                    "A view update must have a matching session and view baseline"
                )
                let view = baseline.apply(update: update)
                viewsBySession[view.session.id, default: [:]][view.view.id] = view
                views.append(view)
            }
        }

        return views
    }

    private func capture(_ fixture: ScrollActionFixture, view: RUMViewScope) throws -> RUMContextHandoff.Capture {
        let session = try XCTUnwrap(fixture.monitor.applicationScope.activeSession)
        let context = RUMCoreContext(
            applicationID: view.context.rumApplicationID,
            sessionID: session.sessionUUID.toRUMDataFormat,
            sessionSampler: session.sampler,
            viewID: view.viewUUID.toRUMDataFormat,
            userActionID: nil,
            viewServerTimeOffset: view.serverTimeOffset,
            viewPath: view.viewPath,
            viewName: view.viewName
        )
        return .init(owner: fixture.owner, value: .init(
            rumContext: context, sceneIdentifier: "a", hasPendingUserAction: false, excludedUserActionID: nil
        ))
    }

    private func receive(_ capture: RUMContextHandoff.Capture?, in fixture: ScrollActionFixture, value: Bool = true) {
        let message = RUMCapturedFlagEvaluationMessage(
            evaluation: .init(flagKey: "captured-flag", value: value), capture: capture
        )
        XCTAssertTrue(FlagEvaluationReceiver(monitor: fixture.monitor).receive(message: .payload(message), from: NOPDatadogCore()))
    }

    private func stop(_ key: String, scene: String, in fixture: ScrollActionFixture) {
        var command = RUMStopViewCommand(time: fixture.clock.now, attributes: [:], identity: ViewIdentifier(key))
        command.target = .scene(.init(rawValue: scene))
        fixture.monitor.process(command: command)
    }

    func testCapturedFlagUpdatesOriginalViewAndSerializedOwnerWhenPeerIsRepresentative() throws {
        let fixture = ScrollActionFixture()
        let original = try fixture.view("original")
        let bound = try capture(fixture, view: original)
        let peer = try fixture.view("peer", scene: "b")
        receive(bound, in: fixture)
        XCTAssertEqual(original.featureFlags["captured-flag"] as? Bool, true)
        XCTAssertNil(peer.featureFlags["captured-flag"])
        stop("original", scene: "a", in: fixture)
        stop("peer", scene: "b", in: fixture)
        let views = try viewsWritten(in: fixture.mockScope)
        let recorded = try XCTUnwrap(views.last { $0.view.id == original.viewUUID.toRUMDataFormat })
        XCTAssertEqual(recorded.session.id, bound.value.rumContext?.sessionID)
        XCTAssertEqual(recorded.view.id, bound.value.rumContext?.viewID)
        XCTAssertEqual(recorded.featureFlags?.featureFlagsInfo["captured-flag"] as? Bool, true)
        XCTAssertFalse(views.filter { $0.view.id == peer.viewUUID.toRUMDataFormat }.contains {
            $0.featureFlags?.featureFlagsInfo["captured-flag"] != nil
        })
    }

    func testCapturedFlagCannotUseRemovedOrResourceRetainedInactiveView() throws {
        for retainResource in [false, true] {
            let fixture = ScrollActionFixture()
            let original = try fixture.view("original")
            let bound = try capture(fixture, view: original)
            if retainResource {
                var command = RUMStartResourceCommand.mockWith(resourceKey: "retained", time: fixture.clock.now)
                command.target = .scene(.init(rawValue: "a"))
                fixture.monitor.process(command: command)
            }
            let replacement = try fixture.view("replacement")
            let peer = try fixture.view("peer", scene: "b")
            XCTAssertFalse(original.isActiveView)
            XCTAssertEqual(fixture.monitor.applicationScope.activeSession?.viewScopes.contains { $0 === original }, retainResource)
            let before = fixture.mockScope.eventsWritten.count
            receive(bound, in: fixture)
            XCTAssertEqual(fixture.mockScope.eventsWritten.count, before)
            XCTAssertNil(original.featureFlags["captured-flag"])
            XCTAssertNil(replacement.featureFlags["captured-flag"])
            XCTAssertNil(peer.featureFlags["captured-flag"])
        }
    }

    func testCapturedFlagCannotRestartStoppedTimedOutOrMaximumDurationSession() throws {
        for boundary in ["stopped", "timeout", "maximum"] {
            let fixture = ScrollActionFixture()
            let original = try fixture.view("original")
            let bound = try capture(fixture, view: original)
            if boundary == "stopped" {
                fixture.monitor.stopSession()
            } else if boundary == "timeout" {
                fixture.clock.now.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration + 1)
            } else {
                let session = try XCTUnwrap(fixture.monitor.applicationScope.activeSession)
                let beforeMaximum = session.sessionStartTime.addingTimeInterval(RUMSessionScope.Constants.sessionMaxDuration - 1)
                let interval = RUMSessionScope.Constants.sessionTimeoutDuration / 2
                while fixture.clock.now < beforeMaximum {
                    fixture.clock.now = min(fixture.clock.now.addingTimeInterval(interval), beforeMaximum)
                    var interaction = RUMAddUserActionCommand.mockWith(time: fixture.clock.now, actionType: .custom, name: "keep-session-active")
                    interaction.target = .scene(.init(rawValue: "a"))
                    fixture.monitor.process(command: interaction)
                    XCTAssertTrue(fixture.monitor.applicationScope.activeSession === session)
                }
                fixture.clock.now = session.sessionStartTime.addingTimeInterval(RUMSessionScope.Constants.sessionMaxDuration + 1)
                XCTAssertTrue(RUMSessionScope.hasExpired(sessionStart: session.sessionStart, now: fixture.clock.now.timeIntervalSinceReferenceDate))
                XCTAssertFalse(RUMSessionScope.hasTimedOut(lastInteraction: session.lastInteraction, now: fixture.clock.now.timeIntervalSinceReferenceDate))
            }
            let sessions = fixture.monitor.applicationScope.sessionScopes.map(\.sessionUUID)
            let before = fixture.mockScope.eventsWritten.count
            receive(bound, in: fixture)
            XCTAssertEqual(fixture.monitor.applicationScope.sessionScopes.map(\.sessionUUID), sessions)
            XCTAssertEqual(fixture.mockScope.eventsWritten.count, before)
            XCTAssertNil(original.featureFlags["captured-flag"])
            let successor = try fixture.view("successor")
            let current = try XCTUnwrap(fixture.monitor.applicationScope.activeSession)
            let afterNavigation = fixture.mockScope.eventsWritten.count
            receive(bound, in: fixture)
            XCTAssertTrue(fixture.monitor.applicationScope.activeSession === current)
            XCTAssertEqual(fixture.mockScope.eventsWritten.count, afterNavigation)
            XCTAssertNil(successor.featureFlags["captured-flag"])
        }
    }

    func testCapturedFlagUnavailableNilForeignAndMalformedOwnersAreHandledWithoutFallback() throws {
        let fixture = ScrollActionFixture()
        let original = try fixture.view("original")
        let bound = try capture(fixture, view: original)
        let peer = try fixture.view("peer", scene: "b")
        let nilContext = RUMContextHandoff.Capture(owner: fixture.owner, value: .init(
            rumContext: nil, sceneIdentifier: "a", hasPendingUserAction: false, excludedUserActionID: nil
        ))
        let foreign = RUMContextHandoff.Capture(owner: .init(), value: bound.value)
        let context = try XCTUnwrap(bound.value.rumContext)
        let viewID = try XCTUnwrap(context.viewID)
        let before = fixture.mockScope.eventsWritten.count
        for candidate in [nil, nilContext, foreign] {
            receive(candidate, in: fixture)
        }
        // Each malformed identifier has a valid peer identifier, so either guard can fail independently.
        for (sessionID, candidateViewID) in [("invalid-session", viewID), (context.sessionID, "invalid-view")] {
            let malformed = RUMCoreContext(
                applicationID: context.applicationID,
                sessionID: sessionID,
                sessionSampler: context.sessionSampler,
                viewID: candidateViewID,
                userActionID: nil,
                viewServerTimeOffset: context.viewServerTimeOffset,
                viewPath: context.viewPath,
                viewName: context.viewName
            )
            receive(.init(owner: fixture.owner, value: .init(
                rumContext: malformed, sceneIdentifier: "a", hasPendingUserAction: false, excludedUserActionID: nil
            )), in: fixture)
        }
        XCTAssertEqual(fixture.mockScope.eventsWritten.count, before)
        XCTAssertNil(original.featureFlags["captured-flag"])
        XCTAssertNil(peer.featureFlags["captured-flag"])
    }

    func testCapturedFlagInvalidatedAfterActualQueueSubmissionDoesNotApply() throws {
        let clock = DateProviderMock(now: ScrollActionFixture.startDate)
        let core = DatadogCoreProxy(context: ScrollActionFixture.context(at: clock.now))
        defer { try? core.flushAndTearDown() }
        try core.register(feature: DatadogRemoteFeatureMock())
        let scope = ScrollActionScope(base: core.scope(for: DatadogRemoteFeatureMock.self))
        let fixture = ScrollActionFixture(scope: scope, clock: clock)
        fixture.enqueueView("original")
        let ready = expectation(description: "original view applied")
        scope.context { _ in ready.fulfill() }
        wait(for: [ready], timeout: 5)
        let original = try XCTUnwrap(fixture.monitor.applicationScope.activeSession?.viewScopes.first { $0.viewName == "original" })
        let bound = try capture(fixture, view: original)
        let entered = expectation(description: "actual RUM command queue held")
        let release = DispatchSemaphore(value: 0)
        scope.context { _ in
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }
        defer { release.signal() }
        wait(for: [entered], timeout: 2)
        receive(bound, in: fixture)
        fixture.owner.invalidate()
        let consumed = expectation(description: "captured flag consumed after invalidation")
        scope.context { _ in consumed.fulfill() }
        release.signal()
        wait(for: [consumed], timeout: 5)
        XCTAssertNil(original.featureFlags["captured-flag"])
        XCTAssertTrue(original.isActiveView)
        XCTAssertEqual(fixture.monitor.applicationScope.activeSession?.viewScopes.count, 1)
        let views = core.waitAndReturnEvents(ofFeature: DatadogRemoteFeatureMock.name, ofType: RUMViewEvent.self)
        XCTAssertFalse(views.contains { $0.featureFlags?.featureFlagsInfo["captured-flag"] != nil })
    }

    func testCapturedFlagInvalidatedDuringUncertainLaunchDeferralDoesNotApply() throws {
        let fixture = ScrollActionFixture()
        let original = try fixture.view("original")
        let bound = try capture(fixture, view: original)
        var uncertain = fixture.mockScope.contextMock
        uncertain.launchInfo.launchReason = .uncertain
        uncertain.applicationStateHistory = .mockWith(initialState: .background, date: fixture.clock.now)
        fixture.mockScope.contextMock = uncertain
        receive(bound, in: fixture)
        XCTAssertNil(original.featureFlags["captured-flag"])
        fixture.owner.invalidate()
        fixture.monitor.process(command: RUMHandleAppLifecycleEventCommand(
            time: fixture.clock.now, globalAttributes: [:], attributes: [:], event: .willEnterForeground
        ))
        XCTAssertNil(original.featureFlags["captured-flag"])
        XCTAssertFalse(fixture.mockScope.eventsWritten(ofType: RUMViewEvent.self).contains {
            $0.featureFlags?.featureFlagsInfo["captured-flag"] != nil
        })
    }

    func testManualAndLegacyFlagEvaluationKeepTheirExistingTargetsAndOverwrite() throws {
        let fixture = ScrollActionFixture()
        let first = try fixture.view("first")
        let peer = try fixture.view("peer", scene: "b")
        fixture.monitor.addFeatureFlagEvaluation(name: "manual", value: "first", target: .scene(.init(rawValue: "a")))
        fixture.monitor.addFeatureFlagEvaluation(name: "manual", value: "replacement", target: .scene(.init(rawValue: "a")))
        let receiver = FlagEvaluationReceiver(monitor: fixture.monitor)
        XCTAssertTrue(receiver.receive(message: .payload(RUMFlagEvaluationMessage(flagKey: "legacy", value: true)), from: NOPDatadogCore()))
        XCTAssertEqual(first.featureFlags["manual"] as? String, "replacement")
        XCTAssertNil(first.featureFlags["legacy"])
        XCTAssertNil(peer.featureFlags["manual"])
        XCTAssertEqual(peer.featureFlags["legacy"] as? Bool, true)
    }

    func testExplicitFlagTargetsPreferActiveRecipientAndRetainInferredFallback() throws {
        let fixture = ScrollActionFixture()
        let original = try fixture.view("original", scene: "a")
        let peer = try fixture.view("peer", scene: "b")
        let targets: [(String, RUMCommandTarget)] = [
            ("explicit-scene", .scene(.init(rawValue: "a"))),
            ("explicit-view", .view(original.viewUUID))
        ]
        for (name, target) in targets {
            fixture.monitor.addFeatureFlagEvaluation(
                name: name, value: "original", target: .scene(.init(rawValue: "b")), explicitTarget: target
            )
            XCTAssertEqual(original.featureFlags[name] as? String, "original")
            XCTAssertNil(peer.featureFlags[name])
        }
        fixture.monitor.addFeatureFlagEvaluation(
            name: "missing-explicit",
            value: true,
            target: .scene(.init(rawValue: "b")),
            explicitTarget: .scene(.init(rawValue: "missing-scene"))
        )
        XCTAssertNil(original.featureFlags["missing-explicit"])
        XCTAssertEqual(peer.featureFlags["missing-explicit"] as? Bool, true)
        let sessionID = try XCTUnwrap(fixture.monitor.applicationScope.activeSession).sessionUUID.toRUMDataFormat
        stop("original", scene: "a", in: fixture)
        stop("peer", scene: "b", in: fixture)
        let views = try viewsWritten(in: fixture.mockScope)
        let finalOriginal = try XCTUnwrap(views.last { $0.view.id == original.viewUUID.toRUMDataFormat })
        XCTAssertEqual(finalOriginal.session.id, sessionID)
        for (name, _) in targets {
            XCTAssertEqual(finalOriginal.featureFlags?.featureFlagsInfo[name] as? String, "original")
            XCTAssertFalse(views.filter { $0.view.id == peer.viewUUID.toRUMDataFormat }.contains {
                $0.featureFlags?.featureFlagsInfo[name] != nil
            })
        }
        XCTAssertFalse(views.filter { $0.view.id == original.viewUUID.toRUMDataFormat }.contains {
            $0.featureFlags?.featureFlagsInfo["missing-explicit"] != nil
        })
        let finalPeer = try XCTUnwrap(views.last { $0.view.id == peer.viewUUID.toRUMDataFormat })
        XCTAssertEqual(finalPeer.session.id, sessionID)
        XCTAssertEqual(finalPeer.featureFlags?.featureFlagsInfo["missing-explicit"] as? Bool, true)
    }

    func testOffFlagEvaluationIgnoresInferredAndExplicitTargetsAndKeepsLegacyView() throws {
        let clock = DateProviderMock(now: ScrollActionFixture.startDate)
        let scope = FeatureScopeMock(context: ScrollActionFixture.context(at: clock.now))
        let monitor = Monitor(dependencies: .mockWith(
            featureScope: scope,
            viewCache: ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: false),
            featureFlags: [.multiSceneTracking: false]
        ), dateProvider: clock)
        XCTAssertFalse(monitor.isMultiSceneTrackingEnabled)
        monitor.process(command: RUMStartViewCommand(
            time: clock.now,
            identity: ViewIdentifier("legacy"),
            name: "legacy",
            path: "legacy",
            globalAttributes: [:],
            attributes: [:],
            instrumentationType: .manual
        ))
        let session = try XCTUnwrap(monitor.applicationScope.activeSession)
        let view = try XCTUnwrap(session.viewScopes.last { $0.isActiveView })
        monitor.addFeatureFlagEvaluation(
            name: "off-flag",
            value: "legacy",
            target: .none,
            explicitTarget: .scene(.init(rawValue: "missing-scene"))
        )
        XCTAssertTrue(monitor.applicationScope.activeSession === session)
        XCTAssertEqual(session.viewScopes.filter { $0.isActiveView }.map(\.viewUUID), [view.viewUUID])
        XCTAssertEqual(view.featureFlags["off-flag"] as? String, "legacy")
        monitor.process(command: RUMStopViewCommand(time: clock.now, attributes: [:], identity: ViewIdentifier("legacy")))
        let finalView = try XCTUnwrap(viewsWritten(in: scope).last)
        XCTAssertEqual(finalView.session.id, session.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(finalView.view.id, view.viewUUID.toRUMDataFormat)
        XCTAssertEqual(finalView.featureFlags?.featureFlagsInfo["off-flag"] as? String, "legacy")
    }
}

#endif

extension MonitorTests {
    private func withPreparedResourceCore(
        _ body: (DatadogCore, FeatureScope, RUMContextHandoff.Owner, DatadogContextProvider) throws -> Void
    ) throws {
        try temporaryCoreDirectory.create()
        let provider = DatadogContextProvider(context: .mockWith(launchInfo: .mockWith(launchReason: .userLaunch)))
        let core = DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: .notGranted,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: provider,
            applicationVersion: "test",
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        )
        defer {
            core.flush()
            core.stop()
            provider.flush()
            XCTAssertNoThrow(try temporaryCoreDirectory.delete())
        }
        let owner = try core.activateRUMContextHandoff()
        try core.registerRUMContextHandoff(feature: PreparedResourceFeature(), owner: owner)
        let scope = core.scope(for: PreparedResourceFeature.self)
        provider.flush()
        try body(core, scope, owner, provider)
    }

    func testPreparedResourceCompletion_refreshesSceneAndCoreActionContext() throws {
        try withPreparedResourceCore { _, scope, owner, provider in
            let time = Date(timeIntervalSince1970: 1_600_000_000)
            let dependencies = RUMScopeDependencies.mockWith(
                featureScope: scope,
                trackBackgroundEvents: false,
                featureFlags: [.multiSceneTracking: true, .viewUpdates: false]
            )
            guard dependencies.isMultiSceneTrackingEnabled else { throw XCTSkip("Requires enabled scene tracking") }
            let monitor = Monitor(dependencies: dependencies, dateProvider: DateProviderMock(now: time))
            let scene = RUMSceneIdentifier(rawValue: "original")
            var startView = RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("original"), name: "original")
            startView.target = .scene(scene)
            monitor.process(command: startView)
            provider.flush()
            let initial = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(scene)))
            let capture = RUMURLSessionContext(owner: owner, value: .init(rumContext: initial, sceneIdentifier: scene.rawValue, hasPendingUserAction: false, excludedUserActionID: nil))
            let receipt = try XCTUnwrap(monitor.prepareResource(capturing: capture))
            monitor.processResource(command: RUMStartResourceCommand.mockWith(resourceKey: receipt.identity.resourceKey, time: time), preparation: receipt.identity)
            provider.flush()
            provider.flush() // accepted controls enqueue one conditional publication from their callback

            // This Action starts after the Resource, so its original resource count stays zero.
            var tap = RUMAddUserActionCommand.mockWith(time: time.addingTimeInterval(1), actionType: .tap, name: "later tap")
            tap.target = .scene(scene)
            monitor.process(command: tap)
            provider.flush()
            let before = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(scene)))
            XCTAssertNotNil(before.userActionID)
            XCTAssertEqual(provider.read().additionalContext(ofType: RUMCoreContext.self)?.userActionID, before.userActionID)
            let unused = try XCTUnwrap(monitor.prepareResource(capturing: capture))
            provider.flush()
            var abandonmentDeliveries = 0
            provider.publish { _ in abandonmentDeliveries += 1 }
            provider.flush()
            monitor.abandonResourcePreparation(unused.identity)
            provider.flush()
            provider.flush()
            XCTAssertEqual(abandonmentDeliveries, 0, "Uncommitted active-view abandonment must not publish context")
            XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(scene))?.userActionID, before.userActionID)

            var terminal = RUMStopResourceCommand.mockWith(resourceKey: receipt.identity.resourceKey, time: time.addingTimeInterval(2))
            terminal.isAutomatic = true
            monitor.processResource(command: terminal, preparation: receipt.identity)
            provider.flush()
            provider.flush()
            let after = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(scene)))
            XCTAssertEqual(after.viewID, initial.viewID)
            XCTAssertNil(after.userActionID, "The valid owning-view terminal expires the later Action")
            let coreContext = try XCTUnwrap(provider.read().additionalContext(ofType: RUMCoreContext.self))
            XCTAssertEqual(coreContext.viewID, initial.viewID)
            XCTAssertNil(coreContext.userActionID, "Core must not retain the completed Action")
            withExtendedLifetime(receipt) {}
        }
        try assertQueuedModifierNavigationPreservesResource()
    }

    func testCapturedResourceControl_rejectionHasNoLifecycleOrPeerEffects() throws {
        for fault in ["foreign owner", "removed view", "expired session", "refreshed session"] {
            try withPreparedResourceCore { _, scope, owner, provider in
                let clock = MonotonicClockMock()
                let time = Date(timeIntervalSince1970: 1_600_000_000)
                let dependencies = RUMScopeDependencies.mockWith(
                    featureScope: scope,
                    trackBackgroundEvents: false,
                    featureFlags: [.multiSceneTracking: true, .viewUpdates: false],
                    monotonicClock: clock
                )
                guard dependencies.isMultiSceneTrackingEnabled else { throw XCTSkip("Requires enabled scene tracking") }
                let monitor = Monitor(dependencies: dependencies, dateProvider: DateProviderMock(now: time))
                let peerScene = RUMSceneIdentifier(rawValue: "live-peer")
                func startPeer() {
                    var peer = RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("live-peer"), name: "live-peer")
                    peer.target = .scene(peerScene)
                    monitor.process(command: peer)
                    var tap = RUMAddUserActionCommand.mockWith(time: time, actionType: .tap, name: "peer Action")
                    tap.target = .scene(peerScene)
                    monitor.process(command: tap)
                    var resource = RUMStartResourceCommand.mockWith(resourceKey: "peer-resource", time: time)
                    resource.target = .scene(peerScene)
                    monitor.process(command: resource)
                    provider.flush()
                }
                var start = RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("original"), name: "original")
                let scene = RUMSceneIdentifier(rawValue: "original")
                start.target = .scene(scene)
                monitor.process(command: start)
                provider.flush()
                let original = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(scene)))
                let capture = RUMURLSessionContext(owner: owner, value: .init(rumContext: original, sceneIdentifier: scene.rawValue, hasPendingUserAction: false, excludedUserActionID: nil))
                let receipt = try XCTUnwrap(monitor.prepareResource(capturing: capture))
                provider.flush()
                startPeer()
                var identity = receipt.identity
                if fault == "foreign owner" {
                    identity = .init(owner: RUMContextHandoff.Owner(), resourceID: identity.resourceID, sessionID: identity.sessionID, viewID: identity.viewID)
                } else if fault == "removed view" {
                    identity = .init(owner: identity.owner, resourceID: identity.resourceID, sessionID: identity.sessionID, viewID: .init(rawValue: UUID()))
                } else {
                    clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration + 1)
                    if fault == "refreshed session" {
                        var next = RUMStartViewCommand.mockWith(time: time.addingTimeInterval(2), identity: ViewIdentifier("replacement"), name: "replacement")
                        next.target = .scene(scene)
                        monitor.process(command: next)
                        provider.flush()
                        startPeer()
                    }
                }
                let peerBefore = monitor.rumContextSnapshot(for: .scene(peerScene))
                let expectsLivePeer = fault != "expired session"
                XCTAssertEqual(peerBefore != nil, expectsLivePeer, fault)
                if expectsLivePeer {
                    XCTAssertNotNil(peerBefore?.userActionID, fault)
                }
                let treeBefore = try preparedResourceTreeSnapshot(monitor, pendingKey: receipt.identity.resourceKey)
                let before = provider.read().additionalContext(ofType: RUMCoreContext.self)
                var deliveries = 0
                provider.publish { _ in deliveries += 1 }
                provider.flush()
                let command = RUMStartResourceCommand.mockWith(resourceKey: identity.resourceKey, time: time.addingTimeInterval(10))
                monitor.processResource(command: command, preparation: identity)
                provider.flush()
                provider.flush()
                let after = provider.read().additionalContext(ofType: RUMCoreContext.self)
                XCTAssertEqual(after?.sessionID, before?.sessionID, fault)
                XCTAssertEqual(after?.viewID, before?.viewID, fault)
                XCTAssertEqual(after?.userActionID, before?.userActionID, fault)
                XCTAssertEqual(deliveries, 0, "Rejected control cannot publish context: " + fault)
                XCTAssertEqual(try preparedResourceTreeSnapshot(monitor, pendingKey: receipt.identity.resourceKey), treeBefore, fault)
                let peerAfter = monitor.rumContextSnapshot(for: .scene(peerScene))
                XCTAssertEqual(peerAfter != nil, expectsLivePeer, fault)
                XCTAssertEqual(peerAfter?.sessionID, peerBefore?.sessionID, fault)
                XCTAssertEqual(peerAfter?.viewID, peerBefore?.viewID, fault)
                XCTAssertEqual(peerAfter?.userActionID, peerBefore?.userActionID, fault)
                monitor.abandonResourcePreparation(receipt.identity)
                provider.flush()
                provider.flush()
            }
        }
    }

    private func assertQueuedModifierNavigationPreservesResource() throws {
        try withPreparedResourceCore { core, scope, owner, provider in
            let time = Date()
            let resources = ReadWriteLock(wrappedValue: [RUMResourceEvent]())
            let views = ReadWriteLock(wrappedValue: [RUMViewEvent]())
            let dependencies = RUMScopeDependencies.mockWith(
                featureScope: scope,
                trackBackgroundEvents: false,
                firstPartyHosts: .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]]),
                eventBuilder: .init(eventsMapper: .mockWith(
                    viewEventMapper: { event in views.mutate { $0.append(event) }; return event },
                    resourceEventMapper: { event in resources.mutate { $0.append(event) }; return event }
                )),
                featureFlags: [.multiSceneTracking: true, .viewUpdates: false]
            )
            guard dependencies.isMultiSceneTrackingEnabled else { throw XCTSkip("Requires enabled scene tracking") }
            let monitor = Monitor(dependencies: dependencies, dateProvider: DateProviderMock(now: time))
            let scene = RUMSceneIdentifier(rawValue: "queued-original")
            let peerScene = RUMSceneIdentifier(rawValue: "queued-peer")
            var originalStart = RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("queued-original"), name: "queued-original")
            originalStart.target = .scene(scene)
            monitor.process(command: originalStart)
            provider.flush()
            let initial = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(scene)))
            let value = RUMContextHandoff.CurrentValue(rumContext: initial, sceneIdentifier: scene.rawValue, hasPendingUserAction: false, excludedUserActionID: nil)
            let tracing = DistributedTracing(
                samplingRate: .maxSampleRate,
                firstPartyHosts: .init(hostsWithTracingHeaderTypes: ["example.com": [.datadog]]),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 0, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 200, advancingByCount: 0),
                traceContextInjection: .all,
                sessionSampling: SessionSamplerMock.keepAll(sessionID: initial.sessionID)
            )
            let handler = URLSessionRUMResourcesHandler(
                dateProvider: DateProviderMock(now: time),
                rumAttributesProvider: nil,
                distributedTracing: tracing,
                headerProcessor: nil,
                disallowList: nil,
                telemetry: NOPTelemetry()
            )
            handler.publish(to: monitor)
            let modifier = PreparedResourceNavigationModifier()
            let finalURL = try XCTUnwrap(URL(string: "https://example.com/final-queued-resource"))
            let response = try XCTUnwrap(HTTPURLResponse(url: finalURL, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            let starts = ReadWriteLock(wrappedValue: (count: 0, key: Optional<String>.none, url: Optional<String>.none, method: Optional<String>.none, viewID: Optional<String>.none))
            let modifies = ReadWriteLock(wrappedValue: 0)
            modifier.onModify = { request in
                modifies.mutate { $0 += 1 }
                var stop = RUMStopViewCommand.mockWith(time: time, identity: ViewIdentifier("queued-original"))
                stop.target = .scene(scene)
                monitor.process(command: stop)
                var next = RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("queued-peer"), name: "queued-peer")
                next.target = .scene(peerScene)
                monitor.process(command: next)
                // Deliberately no Core/Monitor queue flush before deferred interception start.
                var final = request
                final.url = finalURL
                final.httpMethod = "POST"
                return final
            }
            modifier.onStart = { interception in
                starts.mutate {
                    $0.count += 1
                    $0.key = interception.identifier.uuidString
                    $0.url = interception.request.url?.absoluteString
                    $0.method = interception.request.httpMethod
                    $0.viewID = (interception as? RUMURLSessionTaskInterception)?.rumContext.rumContext?.viewID
                }
                // Transport stub only: exercise the actual automatic completed-state callback below.
                interception.register(response: response, error: nil)
            }
            try core.register(urlSessionHandler: handler)
            try core.register(urlSessionHandler: modifier)
            let network = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
            let session = URLSession(configuration: .ephemeral)
            let task = session.dataTask(with: try XCTUnwrap(URL(string: "https://example.com/original-request")))
            let forwards = ReadWriteLock(wrappedValue: 0)
            let transportHold = URLSessionTaskSwizzler()
            try transportHold.swizzle { [weak task] candidate, continuation in
                guard candidate === task else {
                    continuation()
                    return
                }
                forwards.mutate { $0 += 1 }
            }
            defer {
                modifier.onModify = nil
                modifier.onStart = nil
                network.flush()
                transportHold.unswizzle()
                session.invalidateAndCancel()
            }
            try URLSessionInstrumentation.enableOrThrow(with: nil, in: core)
            RUMContextHandoff.withValue(value, for: owner) { task.resume() }
            network.flush()
            provider.flush()
            provider.flush()
            XCTAssertEqual(modifies.wrappedValue, 1)
            XCTAssertEqual(forwards.wrappedValue, 1, "The controlled request never reaches native transport")
            let observation = starts.wrappedValue
            XCTAssertEqual(observation.count, 1)
            XCTAssertEqual(observation.url, finalURL.absoluteString)
            XCTAssertEqual(observation.method, "POST")
            XCTAssertEqual(observation.viewID, initial.viewID)
            let key = try XCTUnwrap(observation.key)
            let original = try XCTUnwrap(monitor.applicationScope.sessionScopes.first { $0.sessionUUID.toRUMDataFormat == initial.sessionID })
            let originalView = try XCTUnwrap(original.viewScopes.first { $0.viewUUID.toRUMDataFormat == initial.viewID })
            XCTAssertFalse(originalView.isActiveView)
            XCTAssertFalse(originalView.hasPendingResourcePreparations)
            XCTAssertEqual(originalView.resourceScopes.count, 1)
            XCTAssertNotNil(originalView.resourceScopes[key])
            let peerBefore = try XCTUnwrap(monitor.rumContextSnapshot(for: .scene(peerScene)))
            let peerView = try XCTUnwrap(original.viewScopes.first { $0.viewUUID.toRUMDataFormat == peerBefore.viewID })
            XCTAssertTrue(peerView.isActiveView)
            XCTAssertTrue(peerView.resourceScopes.isEmpty)

            network.task(task, didChangeToState: URLSessionTask.State.completed.rawValue)
            network.flush()
            provider.flush()
            provider.flush()
            let event = try XCTUnwrap(resources.wrappedValue.last)
            XCTAssertEqual(resources.wrappedValue.count, 1)
            XCTAssertEqual(event.session.id, initial.sessionID)
            XCTAssertEqual(event.view.id, initial.viewID)
            XCTAssertEqual(event.resource.url, finalURL.absoluteString)
            XCTAssertEqual(event.resource.method, .post)
            XCTAssertEqual(event.dd.traceId, "64")
            XCTAssertEqual(event.dd.spanId, "200")
            XCTAssertTrue(originalView.resourceScopes.isEmpty)
            XCTAssertFalse(original.viewScopes.contains { $0 === originalView })
            XCTAssertEqual(views.wrappedValue.last { $0.view.id == initial.viewID }?.view.isActive, false)
            XCTAssertEqual(monitor.rumContextSnapshot(for: .scene(peerScene))?.viewID, peerBefore.viewID)
            XCTAssertTrue(peerView.resourceScopes.isEmpty)
            XCTAssertEqual(starts.wrappedValue.count, 1)
        }
    }

    private func preparedResourceTreeSnapshot(_ monitor: Monitor, pendingKey: String) throws -> [String: String] {
        // Queue barriers precede each call. Observe the tree rather than only cached Core IDs.
        var result: [String: String] = ["application.active": String(monitor.applicationScope.applicationActive)]
        let sessions = monitor.applicationScope.sessionScopes
        result["application.sessions"] = sessions.map { String(describing: ObjectIdentifier($0)) }.joined(separator: ",")
        func counters(_ object: AnyObject, names: [String], prefix: String) throws {
            var fields: [String: Any] = [:]
            var cursor: Mirror? = Mirror(reflecting: object)
            while let mirror = cursor {
                for child in mirror.children {
                    if let label = child.label { fields[label] = child.value }
                }
                cursor = mirror.superclassMirror
            }
            for name in names {
                result[prefix + "." + name] = String(reflecting: try XCTUnwrap(fields[name], "Missing source-bound scope counter: " + name))
            }
        }
        for (index, session) in sessions.enumerated() {
            let prefix = "session\(index)"
            result[prefix + ".id"] = session.sessionUUID.toRUMDataFormat
            result[prefix + ".active"] = String(session.isActive)
            result[prefix + ".reason"] = session.endReason?.rawValue ?? "nil"
            result[prefix + ".start"] = String(session.sessionStart)
            result[prefix + ".interaction"] = String(session.lastInteraction)
            result[prefix + ".views"] = session.viewScopes.map { String(describing: ObjectIdentifier($0)) }.joined(separator: ",")
            for (index, view) in session.viewScopes.enumerated() {
                let prefix = prefix + ".view\(index)"
                result[prefix + ".id"] = view.viewUUID.toRUMDataFormat
                result[prefix + ".active"] = String(view.isActiveView)
                result[prefix + ".pending"] = String(view.hasPendingResourcePreparations)
                result[prefix + ".originalPending"] = String(view.containsResourcePreparation(pendingKey))
                result[prefix + ".resources"] = view.resourceScopes
                    .sorted { $0.key < $1.key }
                    .map { entry in
                        entry.key + ":" + String(describing: ObjectIdentifier(entry.value))
                    }
                    .joined(separator: ",")
                result[prefix + ".action"] = view.userActionScope.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
                try counters(view, names: ["actionsCount", "resourcesCount", "errorsCount", "version"], prefix: prefix)
                if let action = view.userActionScope {
                    try counters(action, names: ["resourcesCount", "errorsCount", "activeResourcesCount", "lastActivityTime"], prefix: prefix + ".action")
                }
            }
        }
        return result
    }

    func testPreparedResourceContextPublication_rejectsRetiredOwnerWithoutDelivery() throws {
        for clears in [false, true] {
            try withPreparedResourceCore { core, scope, owner, provider in
                let publisher = try XCTUnwrap(scope as? RUMContextHandoffContextUpdating)
                scope.set { RUMCoreContext.mockWith(viewID: "replacement") }
                provider.flush()
                var deliveries = 0
                provider.publish { _ in deliveries += 1 }
                provider.flush()
                var replacement: RUMContextHandoff.Owner?
                var activationError: Error?
                publisher.setRUMContext(for: owner) {
                    core.deactivateRUMContextHandoff(owner: owner)
                    do { replacement = try core.activateRUMContextHandoff() } catch { activationError = error }
                    return .set(clears ? nil : .mockWith(viewID: "stale"))
                }
                provider.flush()
                XCTAssertNil(activationError)
                XCTAssertNotNil(replacement)
                XCTAssertFalse(owner.isValid)
                XCTAssertEqual(provider.read().additionalContext(ofType: RUMCoreContext.self)?.viewID, "replacement")
                XCTAssertEqual(deliveries, 0, "Retirement between supplier and mutation must skip even a nil update")
                var lateSupplierCalls = 0
                publisher.setRUMContext(for: owner) { lateSupplierCalls += 1; return .set(nil) }
                provider.flush()
                XCTAssertEqual(lateSupplierCalls, 0)
                XCTAssertEqual(deliveries, 0)
            }
        }
    }

    func testPreparedResourceContextPublication_callbacksRunOutsideRegistryLock() throws {
        try withPreparedResourceCore { core, scope, owner, provider in
            let publisher = try XCTUnwrap(scope as? RUMContextHandoffContextUpdating)
            var deliveries = 0
            provider.publish { [weak core] _ in
                XCTAssertTrue(core?.rumContextHandoffOwner === owner)
                deliveries += 1
            }
            provider.flush()
            var suppliers = 0
            publisher.setRUMContext(for: owner) {
                XCTAssertTrue(core.rumContextHandoffOwner === owner)
                suppliers += 1
                return .skip
            }
            provider.flush()
            XCTAssertEqual(deliveries, 0)
            publisher.setRUMContext(for: owner) {
                XCTAssertTrue(core.rumContextHandoffOwner === owner)
                suppliers += 1
                return .set(.mockWith(viewID: "accepted"))
            }
            provider.flush()
            XCTAssertEqual(provider.read().additionalContext(ofType: RUMCoreContext.self)?.viewID, "accepted")
            XCTAssertEqual(deliveries, 1)
            publisher.setRUMContext(for: owner) { .set(nil) }
            provider.flush()
            XCTAssertNil(provider.read().additionalContext(ofType: RUMCoreContext.self))
            XCTAssertEqual(deliveries, 2, "Valid nil is an accepted publication, not skip")
            XCTAssertEqual(suppliers, 2)
            scope.set { RUMCoreContext.mockWith(viewID: "ordinary") }
            provider.flush()
            XCTAssertEqual(provider.read().additionalContext(ofType: RUMCoreContext.self)?.viewID, "ordinary")
            XCTAssertEqual(deliveries, 3, "Ordinary publication remains unchanged")
        }
    }
}

private struct PreparedResourceFeature: DatadogRemoteFeature {
    let performanceOverride: PerformancePresetOverride? = nil
    static let name = RUMFeature.name
    let requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    let messageReceiver: FeatureMessageReceiver = FeatureMessageReceiverMock()
}

private final class PreparedResourceNavigationModifier: DatadogURLSessionHandler {
    let firstPartyHosts = FirstPartyHosts()
    var onModify: ((URLRequest) -> URLRequest)?
    var onStart: ((URLSessionTaskInterception) -> Void)?
    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest, TraceContext?, URLSessionHandlerCapturedState?) {
        (onModify?(request) ?? request, nil, nil)
    }
    func interceptionDidStart(interception: URLSessionTaskInterception, capturedStates: [any URLSessionHandlerCapturedState]) { onStart?(interception) }
    func interceptionDidComplete(interception: URLSessionTaskInterception) {}
}
