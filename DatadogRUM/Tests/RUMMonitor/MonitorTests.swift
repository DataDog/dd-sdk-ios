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
            dependencies: .mockWith(featureScope: featureScope, timeseriesCollector: TimeseriesCollectorStub()),
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

    private func sceneMonitor(scope: FeatureScope, clock: DateProviderMock, enabled: Bool = true) -> Monitor {
        Monitor(
            dependencies: .mockWith(
                featureScope: scope,
                trackBackgroundEvents: false,
                viewCache: ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: enabled),
                featureFlags: [.multiSceneTracking: enabled]
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
        let monitor = sceneMonitor(scope: FeatureScopeMock(context: .mockWith(sdkInitDate: snapshotDate)), clock: clock)
        startSnapshotView(monitor, key: "a", target: .scene(sceneA))
        let session = try XCTUnwrap(monitor.applicationScope.activeSession)
        XCTAssertEqual(session.sessionStartTime, snapshotDate)
        XCTAssertEqual(session.lastInteractionTime, snapshotDate)
        XCTAssertNotNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        clock.now = snapshotDate.addingTimeInterval(15 * 60 + 1)
        XCTAssertNil(monitor.rumContextSnapshot(for: .scene(sceneA)))
        XCTAssertNil(monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertNotNil(monitor.rumContextSnapshot(for: .scene(sceneA), at: snapshotDate))

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
        XCTAssertEqual(activeSession.lastInteractionTime, activeClock.now)
        let afterMaximum = snapshotDate.addingTimeInterval(4 * 60 * 60 + 1)
        XCTAssertFalse(RUMSessionScope.hasTimedOut(lastInteractionTime: activeSession.lastInteractionTime, currentTime: afterMaximum))
        XCTAssertTrue(RUMSessionScope.hasExpired(sessionStartTime: activeSession.sessionStartTime, currentTime: afterMaximum))
        XCTAssertNil(active.rumContextSnapshot(for: .scene(sceneA), at: afterMaximum))
        XCTAssertNil(active.rumContextSnapshot(for: .processRepresentative, at: afterMaximum))
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
                    XCTAssertEqual(session.lastInteractionTime, f.clock.now)
                    XCTAssertNil(session.endReason)
                }
                f.clock.now = session.sessionStartTime.addingTimeInterval(4 * 60 * 60 + 1)
                XCTAssertFalse(RUMSessionScope.hasTimedOut(lastInteractionTime: session.lastInteractionTime, currentTime: f.clock.now))
                XCTAssertTrue(RUMSessionScope.hasExpired(sessionStartTime: session.sessionStartTime, currentTime: f.clock.now))
            } else {
                f.clock.now = session.lastInteractionTime.addingTimeInterval(15 * 60)
                XCTAssertTrue(RUMSessionScope.hasTimedOut(lastInteractionTime: session.lastInteractionTime, currentTime: f.clock.now))
                XCTAssertFalse(RUMSessionScope.hasExpired(sessionStartTime: session.sessionStartTime, currentTime: f.clock.now))
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
            if earlierTerminal { f.stop(receipt) }
            else { f.enqueueView("b", scene: "b"); f.start(receipt) }
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
        monitor = Monitor(dependencies: .mockWith(featureScope: self.scope, trackBackgroundEvents: background, viewCache: ViewCache(dateProvider: self.clock, isMultiSceneTrackingEnabled: true), featureFlags: [.multiSceneTracking: true]), dateProvider: self.clock)
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

#endif
