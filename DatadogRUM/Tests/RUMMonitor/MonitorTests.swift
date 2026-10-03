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
