/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

class RUMApplicationScopeTests: XCTestCase {
    let writer = FileWriterMock()
    private let recorder = ActiveSessionUpdateRecorder()

    class ActiveSessionUpdateRecorder {
        var calls = [DeterministicSampler?]()

        func record(_ sampler: DeterministicSampler?) {
            calls.append(sampler)
        }

        /// Asserts if the recorded calls match the expected ones.
        ///
        /// The idea of this function is not comparing the samplers, but if we recorded a sampler (for an active
        /// session) or `nil` for no active session (aka, when all sessions are stopped). So it receives an
        /// array of booleans, `true` meaning `.some(_)`, `false` meaning `.none` in the recorded calls
        /// array.
        ///
        /// - parameters:
        ///   - expected: An array of booleans as explained above.
        func assertActiveSessions(_ expected: [Bool]) {
            guard expected.count == calls.count else {
                XCTFail("Different number of recorded calls, expected \(expected.count), got \(calls.count)")
                return
            }

            let callsAsBooleans = calls.map { $0 != nil }
            XCTAssertEqual(expected, callsAsBooleans)
        }

        func assertSamplingDecisions(_ expected: [Bool?]) {
            guard expected.count == calls.count else {
                XCTFail("Different number of recorded calls, expected \(expected.count), got \(calls.count)")
                return
            }

            let callsAsBooleans: [Bool?] = calls.map {
                switch $0 {
                case .some(let sampler): sampler.sample()
                case .none: nil
                }
            }
            XCTAssertEqual(expected, callsAsBooleans)
        }
    }

    /// Creates `RUMApplicationScope` instance and configures it with the effects applied when RUM gets enabled.
    /// TODO: RUM-1649 Move this configuration to `RUMApplicationScope.init()`, so we can remove this setup in tests.
    private func createRUMApplicationScope(
        dependencies: RUMScopeDependencies,
        sdkContext: DatadogContext = .mockWith(sdkInitDate: Date())
    ) -> RUMApplicationScope {
        let modifiedDependencies = dependencies.replacing(
            onSessionUpdate: { [recorder] sessionScope in
                recorder.record(sessionScope?.sampler)
                if let sessionScope {
                    dependencies.onSessionUpdate(sessionScope)
                }
            }
        )
        let scope = RUMApplicationScope(dependencies: modifiedDependencies)
        // Always receive `RUMSDKInitCommand` as the very first command (see: `Monitor.notifySDKInit()`)
        let initCommand = RUMSDKInitCommand(time: sdkContext.sdkInitDate, globalAttributes: [:])
        _ = scope.process(command: initCommand, context: sdkContext, writer: writer)
        return scope
    }

    func testRootContext() {
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "abc-123")
        )

        XCTAssertEqual(scope.context.rumApplicationID, "abc-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenInitialized_itStartsNewSession() throws {
        recorder.assertSamplingDecisions([])

        // When
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 0
            )
        )

        // Then
        let session = try XCTUnwrap(scope.activeSession)
        XCTAssertTrue(session.isInitialSession, "Starting the very first view in application must create initial session")
        recorder.assertSamplingDecisions([false])
    }

    #if !os(watchOS)
    func testWhenSessionExpires_itStartsANewOneAndTransfersActiveViews() throws {
        recorder.assertSamplingDecisions([])

        // Given
        var currentTime = Date()
        let scope = createRUMApplicationScope(dependencies: .mockAny())
        recorder.assertActiveSessions([true])

        let view = createMockViewInWindow()

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: ViewIdentifier(view)),
            context: .mockAny(),
            writer: writer
        )

        let initialSession = try XCTUnwrap(scope.activeSession)
        recorder.assertActiveSessions([true])

        // When
        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: currentTime),
            context: .mockAny(),
            writer: writer
        )

        // Then
        recorder.assertActiveSessions([true, true])

        let nextSession = try XCTUnwrap(scope.activeSession)
        XCTAssertNotEqual(initialSession.sessionUUID, nextSession.sessionUUID, "New session must have different id")
        XCTAssertEqual(initialSession.viewScopes.count, nextSession.viewScopes.count, "All view scopes must be transferred to the new session")

        let initialViewScope = try XCTUnwrap(initialSession.viewScopes.first)
        let transferredViewScope = try XCTUnwrap(nextSession.viewScopes.first)
        XCTAssertNotEqual(initialViewScope.viewUUID, transferredViewScope.viewUUID, "Transferred view scope must have different view id")
        XCTAssertTrue(transferredViewScope.identity == ViewIdentifier(view), "Transferred view scope must track the same view")
        XCTAssertFalse(nextSession.isInitialSession, "Any next session in the application must be marked as 'not initial'")
    }

    func testGivenConcurrentScenes_whenSessionExpires_itTransfersEveryActiveSceneView() throws {
        let startTime = Date()
        let viewCache = ViewCache(dateProvider: DateProviderMock(now: startTime))
        let sdkContext: DatadogContext = .mockWith(
            sdkInitDate: startTime,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: startTime),
            applicationStateHistory: .mockAppInForeground(since: startTime)
        )
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 100,
                viewCache: viewCache,
                featureFlags: [.viewUpdates: false]
            ),
            sdkContext: sdkContext
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: ViewIdentifier("view-A"),
                name: "View A",
                target: .scene(sceneA)
            ),
            context: sdkContext,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: ViewIdentifier("view-B"),
                name: "View B",
                target: .scene(sceneB)
            ),
            context: sdkContext,
            writer: writer
        )

        let initialSession = try XCTUnwrap(scope.activeSession)
        let initialViewPairs = try initialSession.viewScopes.map {
            (try XCTUnwrap($0.sceneIdentifier), $0.viewUUID)
        }
        let initialViewsByScene = Dictionary(uniqueKeysWithValues: initialViewPairs)
        XCTAssertEqual(initialViewsByScene.count, 2)

        let actionTime = startTime.addingTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                time: actionTime,
                actionType: .custom,
                name: "Action in A",
                target: .scene(sceneA)
            ),
            context: sdkContext,
            writer: writer
        )

        let refreshedSession = try XCTUnwrap(scope.activeSession)
        XCTAssertNotEqual(initialSession.sessionUUID, refreshedSession.sessionUUID)
        XCTAssertEqual(refreshedSession.viewScopes.filter(\.isActiveView).count, 2)
        XCTAssertEqual(Set(refreshedSession.viewScopes.compactMap(\.sceneIdentifier)), Set([sceneA, sceneB]))
        for view in refreshedSession.viewScopes {
            XCTAssertNotEqual(view.viewUUID, initialViewsByScene[try XCTUnwrap(view.sceneIdentifier)])
        }
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        let refreshedA = try XCTUnwrap(refreshedSession.viewScopes.first(where: { $0.sceneIdentifier == sceneA }))
        let refreshedB = try XCTUnwrap(refreshedSession.viewScopes.first(where: { $0.sceneIdentifier == sceneB }))
        XCTAssertEqual(action.view.id, refreshedA.viewUUID.toRUMDataFormat)

        let refreshedSessionID = refreshedSession.sessionUUID.toRUMDataFormat
        let refreshedViewEvents = writer.events(ofType: RUMViewEvent.self).filter {
            $0.session.id == refreshedSessionID
        }
        XCTAssertEqual(Set(refreshedViewEvents.map(\.view.id)), Set([
            refreshedA.viewUUID.toRUMDataFormat,
            refreshedB.viewUUID.toRUMDataFormat
        ]))

        let cacheLookupTime = actionTime.addingTimeInterval(0.001).timeIntervalSince1970.dd.toInt64Milliseconds
        XCTAssertEqual(
            viewCache.lastView(before: cacheLookupTime, sceneIdentifier: sceneB),
            refreshedB.viewUUID.toRUMDataFormat
        )
    }

    func testGivenConcurrentScenes_whenSessionTimesOutOnOneSceneStopping_itTransfersTheOtherActiveScene() throws {
        let startTime = Date()
        let sdkContext: DatadogContext = .mockWith(
            sdkInitDate: startTime,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: startTime),
            applicationStateHistory: .mockAppInForeground(since: startTime)
        )
        let scope = createRUMApplicationScope(dependencies: .mockWith(samplingRate: 100), sdkContext: sdkContext)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let viewA = ViewIdentifier("view-A")

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: viewA,
                name: "View A",
                target: .scene(sceneA)
            ),
            context: sdkContext,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: ViewIdentifier("view-B"),
                name: "View B",
                target: .scene(sceneB)
            ),
            context: sdkContext,
            writer: writer
        )

        var stopA = RUMStopViewCommand.mockWith(
            time: startTime.addingTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration),
            identity: viewA
        )
        stopA.target = .scene(sceneA)
        _ = scope.process(command: stopA, context: sdkContext, writer: writer)

        let refreshedSession = try XCTUnwrap(scope.activeSession)
        XCTAssertEqual(refreshedSession.context.sessionPrecondition, .inactivityTimeout)
        XCTAssertEqual(refreshedSession.viewScopes.filter(\.isActiveView).count, 1)
        XCTAssertEqual(refreshedSession.viewScopes.first?.sceneIdentifier, sceneB)
        XCTAssertEqual(refreshedSession.viewScopes.first?.viewName, "View B")
    }
    #endif

    // MARK: - RUM Session Sampling

    func testWhenSamplingRateIs100_allEventsAreSent() {
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 100
            )
        )

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
            context: .mockAny(),
            writer: writer
        )

        // Two extra because of the ApplicationLaunch view start / stop
        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 4)
    }

    func testWhenSamplingRateIs0_noEventsAreSent() {
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 0
            )
        )

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
            context: .mockAny(),
            writer: writer
        )

        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 0)
    }

    func testWhenSamplingRateIs50_onlyHalfOfTheEventsAreSent() throws {
        var currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 50
            )
        )

        let simulatedSessionsCount = 400
        (0..<simulatedSessionsCount).forEach { _ in
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: .mockAny(),
                writer: writer
            )
            _ = scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: .mockViewIdentifier()),
                context: .mockAny(),
                writer: writer
            )
            currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration) // force the Session to be re-created
        }

        let viewEventsCount = writer.events(ofType: RUMViewEvent.self).count
        let trackedSessionsCount = Double(viewEventsCount) / 2 // each Session should send 2 View updates

        let halfSessionsCount = 0.5 * Double(simulatedSessionsCount)
        XCTAssertGreaterThan(trackedSessionsCount, halfSessionsCount * 0.8) // -20%
        XCTAssertLessThan(trackedSessionsCount, halfSessionsCount * 1.2) // +20%
    }

    // MARK: - Stopping and Restarting Sessions

    func testWhenStoppingSession_itHasNoActiveSesssion() throws {
        // Given
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: .mockRandom(min: 0, max: 100) // no matter sampling
            )
        )
        recorder.assertActiveSessions([true])

        let command = RUMStartResourceCommand.mockWith(time: currentTime.addingTimeInterval(1))
        _ = scope.process(command: command, context: .mockAny(), writer: writer)
        recorder.assertActiveSessions([true])

        // When
        let stopCommand = RUMStopSessionCommand.mockAny()
        _ = scope.process(command: stopCommand, context: .mockAny(), writer: writer)
        recorder.assertActiveSessions([true, false])

        // Then
        XCTAssertNil(scope.activeSession)
    }

    func testGivenStoppedSession_whenUserActionEvent_itStartsANewSession() throws {
        // Given
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 100
            )
        )
        recorder.assertSamplingDecisions([true])
        _ = scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(1), isUserInteraction: true),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true])
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true, nil])

        // When
        _ = scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(3), isUserInteraction: true),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true, nil, true])

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertNotNil(scope.activeSession)
    }

    func testGivenStoppedSessionWithConcurrentScenes_whenSceneActionStartsNewSession_itRestoresEveryScene() throws {
        let startTime = Date()
        let sdkContext: DatadogContext = .mockWith(
            sdkInitDate: startTime,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: startTime),
            applicationStateHistory: .mockAppInForeground(since: startTime)
        )
        let scope = createRUMApplicationScope(dependencies: .mockWith(samplingRate: 100), sdkContext: sdkContext)
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: ViewIdentifier("view-A"),
                name: "View A",
                target: .scene(sceneA)
            ),
            context: sdkContext,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: ViewIdentifier("view-B"),
                name: "View B",
                target: .scene(sceneB)
            ),
            context: sdkContext,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: startTime.addingTimeInterval(1)),
            context: sdkContext,
            writer: writer
        )
        XCTAssertNil(scope.activeSession)

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                time: startTime.addingTimeInterval(2),
                actionType: .custom,
                name: "Action in A",
                target: .scene(sceneA)
            ),
            context: sdkContext,
            writer: writer
        )

        let newSession = try XCTUnwrap(scope.activeSession)
        XCTAssertEqual(newSession.viewScopes.filter(\.isActiveView).count, 2)
        XCTAssertEqual(Set(newSession.viewScopes.compactMap(\.sceneIdentifier)), Set([sceneA, sceneB]))
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        let viewA = try XCTUnwrap(newSession.viewScopes.first(where: { $0.sceneIdentifier == sceneA }))
        XCTAssertEqual(action.view.id, viewA.viewUUID.toRUMDataFormat)
    }

    func testGivenStoppedSessionWithConcurrentScenes_whenStartingViewInOneScene_itRestoresTheOtherScene() throws {
        let startTime = Date()
        let viewCache = ViewCache(dateProvider: DateProviderMock(now: startTime))
        let sdkContext: DatadogContext = .mockWith(
            sdkInitDate: startTime,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: startTime),
            applicationStateHistory: .mockAppInForeground(since: startTime)
        )
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 100,
                viewCache: viewCache,
                featureFlags: [.viewUpdates: false]
            ),
            sdkContext: sdkContext
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: ViewIdentifier("view-A"),
                name: "View A",
                target: .scene(sceneA)
            ),
            context: sdkContext,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime,
                identity: ViewIdentifier("view-B"),
                name: "View B",
                target: .scene(sceneB)
            ),
            context: sdkContext,
            writer: writer
        )
        let initialSession = try XCTUnwrap(scope.activeSession)
        let initialA = try XCTUnwrap(initialSession.viewScopes.first(where: { $0.sceneIdentifier == sceneA }))

        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: startTime.addingTimeInterval(1)),
            context: sdkContext,
            writer: writer
        )
        XCTAssertNil(scope.activeSession)

        let detailStartTime = startTime.addingTimeInterval(2)
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: detailStartTime,
                identity: ViewIdentifier("detail-B"),
                name: "Detail B",
                target: .scene(sceneB)
            ),
            context: sdkContext,
            writer: writer
        )

        let newSession = try XCTUnwrap(scope.activeSession)
        let activeViews = newSession.viewScopes.filter(\.isActiveView)
        XCTAssertEqual(activeViews.count, 2)
        let restoredA = try XCTUnwrap(activeViews.first(where: { $0.sceneIdentifier == sceneA }))
        let detailB = try XCTUnwrap(activeViews.first(where: { $0.sceneIdentifier == sceneB }))
        XCTAssertEqual(restoredA.viewName, "View A")
        XCTAssertNotEqual(restoredA.viewUUID, initialA.viewUUID)
        XCTAssertEqual(detailB.viewName, "Detail B")

        let newSessionViewEvents = writer.events(ofType: RUMViewEvent.self).filter {
            $0.session.id == newSession.sessionUUID.toRUMDataFormat
        }
        XCTAssertEqual(Set(newSessionViewEvents.map(\.view.id)), Set([
            restoredA.viewUUID.toRUMDataFormat,
            detailB.viewUUID.toRUMDataFormat
        ]))

        let cacheLookupTime = detailStartTime.addingTimeInterval(0.001).timeIntervalSince1970.dd.toInt64Milliseconds
        XCTAssertEqual(
            viewCache.lastView(before: cacheLookupTime, sceneIdentifier: sceneA),
            restoredA.viewUUID.toRUMDataFormat
        )
    }

    #if !os(tvOS) && !os(watchOS)
    private enum RestorationBoundary {
        case explicitStop, timeout, maximumDuration, delayedTimeout, delayedMaximumDuration
    }

    private enum RestoringNavigation {
        case inferredStart, sceneStart, identityStop, sceneStop
    }

    func testGivenStoppedConcurrentSession_whenSourceLessViewStarts_itPreservesOldOwner() throws {
        try assertNavigationRestoration(boundary: .explicitStop, navigation: .inferredStart)
    }

    func testGivenStoppedConcurrentSession_whenNonrepresentativeIdentityStops_itPreservesPeer() throws {
        try assertNavigationRestoration(boundary: .explicitStop, navigation: .identityStop)
    }

    func testGivenLifecycleTimeout_whenViewStarts_itRestoresEligiblePeer() throws {
        try assertNavigationRestoration(boundary: .delayedTimeout, navigation: .sceneStart)
    }

    func testGivenLifecycleTimeout_whenViewStops_itRestoresEligiblePeer() throws {
        try assertNavigationRestoration(boundary: .delayedTimeout, navigation: .sceneStop)
    }

    func testGivenLifecycleMaximumDuration_whenViewStarts_itRestoresEligiblePeer() throws {
        try assertNavigationRestoration(boundary: .delayedMaximumDuration, navigation: .sceneStart)
    }

    func testGivenLifecycleMaximumDuration_whenViewStops_itRestoresEligiblePeer() throws {
        try assertNavigationRestoration(boundary: .delayedMaximumDuration, navigation: .sceneStop)
    }

    func testGivenImmediateTimeout_whenNavigationChanges_itPreservesEveryUnaffectedBranch() throws {
        for navigation in [RestoringNavigation.inferredStart, .sceneStart, .identityStop, .sceneStop] {
            try assertNavigationRestoration(boundary: .timeout, navigation: navigation)
        }
    }

    func testGivenImmediateMaximumDuration_whenNavigationChanges_itPreservesEveryUnaffectedBranch() throws {
        for navigation in [RestoringNavigation.inferredStart, .sceneStart, .identityStop, .sceneStop] {
            try assertNavigationRestoration(boundary: .maximumDuration, navigation: navigation)
        }
    }

    func testGivenDelayedExpiration_whenNavigationIsInferred_itKeepsTheOldOwner() throws {
        for boundary in [RestorationBoundary.delayedTimeout, .delayedMaximumDuration] {
            for navigation in [RestoringNavigation.inferredStart, .identityStop] {
                try assertNavigationRestoration(boundary: boundary, navigation: navigation)
            }
        }
    }

    func testGivenExplicitStop_whenNavigationHasSceneTarget_itRestoresOnlyPeers() throws {
        for navigation in [RestoringNavigation.sceneStart, .sceneStop] {
            try assertNavigationRestoration(boundary: .explicitStop, navigation: navigation)
        }
    }

    func testGivenRepresentativeChangedBeforeBoundary_whenSourceLessNavigationStarts_itUsesThatRepresentative() throws {
        for boundary in [RestorationBoundary.explicitStop, .delayedTimeout] {
            try assertNavigationRestoration(boundary: boundary, navigation: .inferredStart, representativeIsA: true)
        }
    }

    func testGivenExpiration_whenNavigationRunsInBackground_itDoesNotResumeForegroundPeers() throws {
        for boundary in [RestorationBoundary.explicitStop, .timeout, .maximumDuration, .delayedTimeout, .delayedMaximumDuration] {
            for enabled in [false, true] {
                for navigation in [RestoringNavigation.sceneStart, .sceneStop] {
                    try assertNavigationRestoration(
                        boundary: boundary,
                        navigation: navigation,
                        inBackground: true,
                        trackBackgroundEvents: enabled
                    )
                }
            }
        }
    }

    func testGivenSceneLessView_whenNavigationRestartsSession_itKeepsLegacyViewShape() throws {
        let start: Date = .mockDecember15th2019At10AMUTC()
        let context: DatadogContext = .mockWith(
            sdkInitDate: start,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: start),
            applicationStateHistory: .mockAppInForeground(since: start)
        )
        for delayed in [false, true] {
            let scope = createRUMApplicationScope(dependencies: .mockWith(samplingRate: 100), sdkContext: context)
            _ = scope.process(command: RUMStartViewCommand.mockWith(time: start, identity: ViewIdentifier("old")), context: context, writer: writer)
            let old = try XCTUnwrap(scope.activeSession?.activeView)
            let boundary = start.addingTimeInterval(delayed ? RUMSessionScope.Constants.sessionTimeoutDuration : 1)
            let end: RUMCommand = delayed
                ? RUMHandleAppLifecycleEventCommand(time: boundary, event: .willEnterForeground)
                : RUMStopSessionCommand(time: boundary)
            _ = scope.process(command: end, context: context, writer: writer)
            XCTAssertNil(scope.activeSession)
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: boundary.addingTimeInterval(1), identity: ViewIdentifier("new"), name: "New"),
                context: context,
                writer: writer
            )
            let session = try XCTUnwrap(scope.activeSession)
            let view = try XCTUnwrap(session.activeView)
            XCTAssertEqual(session.viewScopes.filter(\.isActiveView).count, 1)
            XCTAssertEqual(view.viewName, "New")
            XCTAssertNil(view.sceneIdentifier)
            XCTAssertNotEqual(view.viewUUID, old.viewUUID)
        }
    }

    private func assertNavigationRestoration(
        boundary: RestorationBoundary,
        navigation: RestoringNavigation,
        representativeIsA: Bool = false,
        inBackground: Bool = false,
        trackBackgroundEvents: Bool = false
    ) throws {
        let start: Date = .mockDecember15th2019At10AMUTC()
        var context: DatadogContext = .mockWith(
            sdkInitDate: start,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: start),
            applicationStateHistory: .mockAppInForeground(since: start)
        )
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100, trackBackgroundEvents: trackBackgroundEvents, featureFlags: [.viewUpdates: false]),
            sdkContext: context
        )
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        for (scene, key, name) in [(sceneA, "A", "View A"), (sceneB, "B", "View B")] {
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: start, identity: ViewIdentifier(key), name: name, target: .scene(scene)),
                context: context,
                writer: writer
            )
        }
        if representativeIsA {
            _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(time: start, actionType: .custom, name: "Select A", target: .scene(sceneA)),
                context: context,
                writer: writer
            )
        }
        let oldSession = try XCTUnwrap(scope.activeSession)
        let oldViews = oldSession.viewScopes.filter(\.isActiveView)
        XCTAssertEqual(oldViews.count, 2)
        XCTAssertEqual(oldSession.activeView?.sceneIdentifier, representativeIsA ? sceneA : sceneB)
        let isMaximum = boundary == .maximumDuration || boundary == .delayedMaximumDuration
        let boundaryTime = start.addingTimeInterval(
            boundary == .explicitStop ? 1 : isMaximum
                ? RUMSessionScope.Constants.sessionMaxDuration
                : RUMSessionScope.Constants.sessionTimeoutDuration
        )
        if isMaximum {
            var heartbeat = start
            while heartbeat.addingTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration - 1) < boundaryTime {
                heartbeat.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration - 1)
                _ = scope.process(command: RUMCommandMock(time: heartbeat, isUserInteraction: true), context: context, writer: writer)
            }
            XCTAssertTrue(scope.activeSession === oldSession, "Maximum duration must not accidentally test an inactivity timeout")
        }
        if inBackground {
            context = .mockWith(
                sdkInitDate: start,
                launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: start),
                applicationStateHistory: .mockAppInBackground(since: boundaryTime)
            )
        }
        if boundary == .explicitStop {
            _ = scope.process(command: RUMStopSessionCommand(time: boundaryTime), context: context, writer: writer)
            XCTAssertNil(scope.activeSession)
        } else if boundary == .delayedTimeout || boundary == .delayedMaximumDuration {
            _ = scope.process(
                command: RUMHandleAppLifecycleEventCommand(time: boundaryTime, event: inBackground ? .didEnterBackground : .willEnterForeground),
                context: context,
                writer: writer
            )
            XCTAssertNil(scope.activeSession, "Lifecycle expiration must defer the replacement session")
        }
        let navigationTime = boundaryTime.addingTimeInterval(1)
        let command: RUMCommand
        let expectedNames: [RUMSceneIdentifier: String]
        switch navigation {
        case .inferredStart:
            command = RUMStartViewCommand.mockWith(time: navigationTime, identity: ViewIdentifier("new"), name: "New")
            expectedNames = representativeIsA ? [sceneA: "New", sceneB: "View B"] : [sceneA: "View A", sceneB: "New"]
        case .sceneStart:
            command = RUMStartViewCommand.mockWith(
                time: navigationTime, identity: ViewIdentifier("new"), name: "New", target: .scene(sceneA)
            )
            expectedNames = [sceneA: "New", sceneB: "View B"]
        case .identityStop, .sceneStop:
            command = RUMStopViewCommand.mockWith(
                time: navigationTime,
                identity: ViewIdentifier("A"),
                target: navigation == .sceneStop ? .scene(sceneA) : .processRepresentative
            )
            expectedNames = [sceneB: "View B"]
        }
        _ = scope.process(command: command, context: context, writer: writer)
        let newSession = try XCTUnwrap(scope.activeSession)
        XCTAssertNotEqual(newSession.sessionUUID, oldSession.sessionUUID)
        XCTAssertEqual(newSession.context.sessionPrecondition, boundary == .explicitStop ? .explicitStop : isMaximum ? .maxDuration : .inactivityTimeout)
        let active = newSession.viewScopes.filter(\.isActiveView)
        if inBackground {
            XCTAssertFalse(active.contains { $0.viewName == "View A" || $0.viewName == "View B" })
            XCTAssertEqual(active.count, navigation == .sceneStart ? 1 : 0)
            return
        }
        XCTAssertEqual(active.count, expectedNames.count)
        for (scene, name) in expectedNames {
            let view = try XCTUnwrap(active.first { $0.sceneIdentifier == scene })
            XCTAssertEqual(view.viewName, name)
            XCTAssertNotEqual(view.viewUUID, oldViews.first { $0.sceneIdentifier == scene }?.viewUUID)
        }
        let viewEvents = writer.events(ofType: RUMViewEvent.self).filter { $0.session.id == newSession.sessionUUID.toRUMDataFormat }
        XCTAssertEqual(Set(viewEvents.map(\.view.id)), Set(active.map { $0.viewUUID.toRUMDataFormat }), "No phantom restored occurrence")

        let peerScene = navigation == .inferredStart && !representativeIsA ? sceneA : sceneB
        let peer = try XCTUnwrap(active.first { $0.sceneIdentifier == peerScene })
        let markerTime = navigationTime.addingTimeInterval(1)
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: markerTime, actionType: .custom, name: "Peer action", target: .scene(peerScene)),
            context: context,
            writer: writer
        )
        var resource = RUMStartResourceCommand.mockWith(resourceKey: "peer", time: markerTime, url: "https://example.com/peer")
        resource.target = .scene(peerScene)
        _ = scope.process(command: resource, context: context, writer: writer)
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: "peer", time: markerTime.addingTimeInterval(1)),
            context: context,
            writer: writer
        )
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        let resourceEvent = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        XCTAssertEqual(action.session.id, newSession.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(action.view.id, peer.viewUUID.toRUMDataFormat)
        XCTAssertEqual(resourceEvent.session.id, newSession.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(resourceEvent.view.id, peer.viewUUID.toRUMDataFormat)
    }
    #endif

    func testGivenSessionProcessingResources_whenStopped_itStaysInactive() throws {
        // Given
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 100
            )
        )
        recorder.assertSamplingDecisions([true])
        _ = scope.process(
            command: RUMStartResourceCommand.mockRandom(),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true])

        // When
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true, nil])

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertNil(scope.activeSession)
    }

    func testGivenSessionProcessingResources_whenStopped_itIsRemovedWhenResourceFinishes() throws {
        // Given
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 100
            )
        )
        recorder.assertSamplingDecisions([true])
        let resourceKey = "resources/1"
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: currentTime.addingTimeInterval(1)
            ),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true])

        // When
        let firstSession = try XCTUnwrap(scope.activeSession)
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true, nil])
        XCTAssertEqual(scope.sessionScopes.count, 1)
        _ = scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(3), isUserInteraction: true),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true, nil, true])
        XCTAssertEqual(scope.sessionScopes.count, 2)
        let secondSession = try XCTUnwrap(scope.activeSession)
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: currentTime.addingTimeInterval(4)
            ),
            context: .mockAny(),
            writer: writer
        )
        recorder.assertSamplingDecisions([true, nil, true])

        // Then
        XCTAssertNotEqual(firstSession.sessionUUID, secondSession.sessionUUID)
        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertEqual(scope.activeSession?.sessionUUID, secondSession.sessionUUID)
    }

    func testGivenStoppedSessionHasPendingResource_whenNewSessionReusesViewIdentity_itKeepsOccurrencesIsolated() throws {
        let startTime = Date()
        let sdkContext: DatadogContext = .mockWith(
            sdkInitDate: startTime,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: startTime),
            applicationStateHistory: .mockAppInForeground(since: startTime)
        )
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let homeIdentity = ViewIdentifier("home")
        let resourceKey = "home-1-resource"

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime.addingTimeInterval(1),
                attributes: ["occurrence": "home-1"],
                identity: homeIdentity,
                name: "Home",
                target: .scene(scene)
            ),
            context: sdkContext,
            writer: writer
        )
        let firstSession = try XCTUnwrap(scope.activeSession)
        let firstHome = try XCTUnwrap(firstSession.activeView)

        var startResource = RUMStartResourceCommand.mockWith(
            resourceKey: resourceKey,
            time: startTime.addingTimeInterval(2)
        )
        startResource.target = .view(firstHome.viewUUID)
        _ = scope.process(command: startResource, context: sdkContext, writer: writer)
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: startTime.addingTimeInterval(3)),
            context: sdkContext,
            writer: writer
        )
        XCTAssertNil(scope.activeSession)

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: startTime.addingTimeInterval(4),
                attributes: ["occurrence": "home-2"],
                identity: homeIdentity,
                name: "Home",
                target: .scene(scene)
            ),
            context: sdkContext,
            writer: writer
        )
        let secondSession = try XCTUnwrap(scope.activeSession)
        let secondHome = try XCTUnwrap(secondSession.activeView)

        XCTAssertEqual(scope.sessionScopes.count, 2)
        XCTAssertTrue(firstSession.viewScopes.contains { $0 === firstHome })
        XCTAssertEqual(firstHome.attributes["occurrence"] as? String, "home-1")
        XCTAssertEqual(secondHome.attributes["occurrence"] as? String, "home-2")
        XCTAssertNotEqual(firstHome.viewUUID, secondHome.viewUUID)

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                time: startTime.addingTimeInterval(5),
                actionType: .custom,
                name: "home-2-action",
                target: .scene(scene)
            ),
            context: sdkContext,
            writer: writer
        )
        var stopResource = RUMStopResourceCommand.mockWith(
            resourceKey: resourceKey,
            time: startTime.addingTimeInterval(6)
        )
        stopResource.target = .view(firstHome.viewUUID)
        _ = scope.process(command: stopResource, context: sdkContext, writer: writer)

        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertTrue(scope.activeSession === secondSession)
        XCTAssertEqual(
            writer.events(ofType: RUMActionEvent.self).last?.view.id,
            secondHome.viewUUID.toRUMDataFormat
        )
        XCTAssertEqual(
            writer.events(ofType: RUMResourceEvent.self).last?.view.id,
            firstHome.viewUUID.toRUMDataFormat
        )
    }

    private enum ResourceCompletionTarget: CaseIterable {
        case inferred, ownerView, ownerScene, peerScene
    }

    func testLateResourceSuccessDoesNotAlterNewSessionContinuousAction() throws {
        for target in [ResourceCompletionTarget.inferred, .ownerView, .ownerScene] {
            try assertResourceCompletionOwnership(stopsSession: true, fails: false, target: target)
        }
    }

    func testLateResourceFailureDoesNotAlterNewSessionContinuousAction() throws {
        for target in [ResourceCompletionTarget.inferred, .ownerView, .ownerScene] {
            try assertResourceCompletionOwnership(stopsSession: true, fails: true, target: target)
        }
    }

    func testSceneResourceCompletionDoesNotAlterLaterViewContinuousAction() throws {
        for fails in [false, true] {
            try assertResourceCompletionOwnership(stopsSession: false, fails: fails, target: .ownerScene)
        }
    }

    func testPeerResourceCompletionTargetCannotOverrideCapturedOwner() throws {
        for fails in [false, true] {
            try assertResourceCompletionOwnership(stopsSession: false, fails: fails, target: .peerScene)
        }
    }

    func testLateResourceMetricsAndRepeatedCompletionKeepOriginalOwner() throws {
        for target in ResourceCompletionTarget.allCases {
            for fails in [false, true] {
                try assertResourceCompletionOwnership(
                    stopsSession: true, fails: fails, target: target, addsMetrics: true, repeatsCompletion: true
                )
            }
        }
    }

    private func assertResourceCompletionOwnership(
        stopsSession: Bool,
        fails: Bool,
        target: ResourceCompletionTarget,
        addsMetrics: Bool = false,
        repeatsCompletion: Bool = false
    ) throws {
        let time: Date = .mockDecember15th2019At10AMUTC()
        let context: DatadogContext = .mockWith(
            sdkInitDate: time,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: time),
            applicationStateHistory: .mockAppInForeground(since: time)
        )
        let scope = createRUMApplicationScope(dependencies: .mockWith(samplingRate: 100), sdkContext: context)
        let writer = FileWriterMock()
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("old-A"), name: "Old A", target: .scene(sceneA)),
            context: context,
            writer: writer
        )
        let oldSession = try XCTUnwrap(scope.activeSession)
        let oldView = try XCTUnwrap(oldSession.activeView)
        var resource = RUMStartResourceCommand.mockWith(resourceKey: "old-resource", time: time.addingTimeInterval(0.01))
        resource.target = .view(oldView.viewUUID)
        _ = scope.process(command: resource, context: context, writer: writer)
        if stopsSession {
            _ = scope.process(command: RUMStopSessionCommand(time: time.addingTimeInterval(0.02)), context: context, writer: writer)
        }
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.03), identity: ViewIdentifier("new-A"), name: "New A", target: .scene(sceneA)),
            context: context,
            writer: writer
        )
        let newSession = try XCTUnwrap(scope.activeSession)
        let newView = try XCTUnwrap(newSession.activeView)
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.04), identity: ViewIdentifier("B"), name: "Peer B", target: .scene(sceneB)),
            context: context,
            writer: writer
        )
        let peer = try XCTUnwrap(newSession.activeView)
        for scene in [sceneA, sceneB] {
            var action = RUMStartUserActionCommand.mockWith(time: time.addingTimeInterval(0.05), actionType: .tap, name: "Current action")
            action.target = .scene(scene)
            _ = scope.process(command: action, context: context, writer: writer)
        }
        let completionTarget: RUMCommandTarget
        switch target {
        case .inferred: completionTarget = .processRepresentative
        case .ownerView: completionTarget = .view(oldView.viewUUID)
        case .ownerScene: completionTarget = .scene(sceneA)
        case .peerScene: completionTarget = .scene(sceneB)
        }
        let metrics = ResourceMetrics.mockWith(
            fetch: .init(start: time.addingTimeInterval(0.01), end: time.addingTimeInterval(0.04)),
            responseBodySize: (encoded: 555, decoded: 777)
        )
        if addsMetrics {
            var command = RUMAddResourceMetricsCommand.mockWith(
                resourceKey: "old-resource",
                time: time.addingTimeInterval(0.055),
                attributes: ["metrics": "owner"],
                metrics: metrics
            )
            command.target = completionTarget
            _ = scope.process(command: command, context: context, writer: writer)
        }
        if fails {
            var completion = RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                resourceKey: "old-resource", time: time.addingTimeInterval(0.06), message: "Old request failed", source: .network
            )
            completion.target = completionTarget
            _ = scope.process(command: completion, context: context, writer: writer)
            if repeatsCompletion {
                completion.time = time.addingTimeInterval(0.065)
                _ = scope.process(command: completion, context: context, writer: writer)
            }
        } else {
            var completion = RUMStopResourceCommand.mockWith(resourceKey: "old-resource", time: time.addingTimeInterval(0.06))
            completion.target = completionTarget
            _ = scope.process(command: completion, context: context, writer: writer)
            if repeatsCompletion {
                completion.time = time.addingTimeInterval(0.065)
                _ = scope.process(command: completion, context: context, writer: writer)
            }
        }
        for scene in [sceneA, sceneB] {
            var stop = RUMStopUserActionCommand.mockWith(time: time.addingTimeInterval(0.07), attributes: ["result": "current"], actionType: .tap)
            stop.target = .scene(scene)
            _ = scope.process(command: stop, context: context, writer: writer)
        }

        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(Set(actions.map(\.view.id)), Set([newView.viewUUID.toRUMDataFormat, peer.viewUUID.toRUMDataFormat]))
        for action in actions {
            XCTAssertEqual(action.session.id, newSession.sessionUUID.toRUMDataFormat)
            XCTAssertEqual(action.action.resource?.count, 0, "Completion target: \(target)")
            XCTAssertEqual(action.action.error?.count, 0, "Completion target: \(target)")
            XCTAssertEqual(action.context?.contextInfo["result"] as? String, "current")
            XCTAssertNil(action.context?.contextInfo["metrics"])
        }
        if fails {
            let errors = writer.events(ofType: RUMErrorEvent.self)
            XCTAssertEqual(errors.count, 1)
            XCTAssertEqual(errors.first?.view.id, oldView.viewUUID.toRUMDataFormat)
            XCTAssertEqual(errors.first?.session.id, oldSession.sessionUUID.toRUMDataFormat)
            if addsMetrics {
                XCTAssertEqual(errors.first?.context?.contextInfo["metrics"] as? String, "owner")
            }
        } else {
            let resources = writer.events(ofType: RUMResourceEvent.self)
            XCTAssertEqual(resources.count, 1)
            XCTAssertEqual(resources.first?.view.id, oldView.viewUUID.toRUMDataFormat)
            XCTAssertEqual(resources.first?.session.id, oldSession.sessionUUID.toRUMDataFormat)
            if addsMetrics {
                XCTAssertEqual(resources.first?.context?.contextInfo["metrics"] as? String, "owner")
                XCTAssertEqual(resources.first?.resource.duration, metrics.fetch.duration.dd.toInt64Nanoseconds)
                XCTAssertEqual(resources.first?.resource.size, 777)
                XCTAssertEqual(resources.first?.resource.encodedBodySize, 555)
            }
        }
        XCTAssertNil(oldView.resourceScopes["old-resource"])
    }

    // MARK: - Starting Session With Different Preconditions

    func testGivenAppLaunchInForegroundAndNoPrewarming_whenInitialSessionIsStarted() throws {
        // Given
        let sdkContext: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .userLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInForeground(since: .mockDecember15th2019At10AMUTC())
        )

        // When
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        // Then
        let session = try XCTUnwrap(scope.activeSession)
        let view = try XCTUnwrap(session.viewScopes.first)
        XCTAssertEqual(
            session.context.sessionPrecondition,
            .userAppLaunch,
            "It should set 'user app launch' precondition"
        )
        XCTAssertEqual(
            view.viewName,
            RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            "It should start 'application launch' view"
        )
    }

    func testGivenAppLaunchInBackgroundAndNoPrewarming_whenInitialSessionIsStarted() throws {
        // Given
        let sdkContext: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .backgroundLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: .mockDecember15th2019At10AMUTC())
        )

        // When
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        // Then
        let session = try XCTUnwrap(scope.activeSession)
        XCTAssertEqual(
            session.context.sessionPrecondition,
            .backgroundLaunch,
            "It should set 'background launch' precondition"
        )
        XCTAssertTrue(
            session.viewScopes.isEmpty,
            "It should not start any view"
        )
    }

    func testGivenLaunchWithPrewarming_whenInitialSessionIsStarted() throws {
        // Given
        let sdkContext: DatadogContext = .mockWith(
            launchInfo: .mockWith(
                launchReason: .prewarming,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockWith(initialState: .background, date: .mockDecember15th2019At10AMUTC())
        )

        // When
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        // Then
        let session = try XCTUnwrap(scope.activeSession)
        XCTAssertEqual(
            session.context.sessionPrecondition,
            .prewarm,
            "It should set 'prewarm' precondition"
        )
        XCTAssertTrue(
            session.viewScopes.isEmpty,
            "It should not start any view"
        )
    }

    func testGivenInactiveSession_whenNewOneIsStarted_itSetsInactivityTimeoutPrecondition() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let sdkContext: DatadogContext = .mockWith(sdkInitDate: currentTime)
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        // When
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)
        _ = scope.process(
            command: RUMCommandMock(time: currentTime, isUserInteraction: true),
            context: sdkContext,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .inactivityTimeout)
    }

    func testGivenExpiredSession_whenNewOneIsStarted_itSetsMaxDurationPrecondition() {
        // Given
        let initialTime: Date = .mockDecember15th2019At10AMUTC()
        var currentTime: Date = initialTime
        let sdkContext: DatadogContext = .mockWith(sdkInitDate: currentTime)
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        // keep session active until it expires
        while currentTime < initialTime.addingTimeInterval(RUMSessionScope.Constants.sessionMaxDuration) {
            currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration - 1)
            _ = scope.process(
                command: RUMCommandMock(time: currentTime, isUserInteraction: true),
                context: sdkContext,
                writer: writer
            )
        }

        // When
        _ = scope.process(
            command: RUMCommandMock(time: currentTime, isUserInteraction: true),
            context: sdkContext,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .maxDuration)
    }

    func testGivenStoppedSession_whenNewOneIsStarted_itSetsExplicitStopPrecondition() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let sdkContext: DatadogContext = .mockWith(sdkInitDate: currentTime)
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMStopSessionCommand(time: currentTime), context: sdkContext, writer: writer)

        // When
        currentTime.addTimeInterval(1)
        _ = scope.process(
            command: RUMCommandMock(time: currentTime, isUserInteraction: true),
            context: sdkContext,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .explicitStop)
    }

    func testGivenInactiveSession_whenNewOneIsStartedInBackground_itSetsBackgroundLaunchPrecondition() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let sdkContext: DatadogContext = .mockWith(sdkInitDate: currentTime)
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        // When
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)
        let backgroundContext: DatadogContext = .mockWith(
            sdkInitDate: .mockDecember15th2019At10AMUTC(),
            launchInfo: .mockWith(
                launchReason: .backgroundLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: currentTime)
        )
        _ = scope.process(
            command: RUMCommandMock(time: currentTime, isUserInteraction: true),
            context: backgroundContext,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .backgroundLaunch)
    }

    func testGivenExpiredSession_whenNewOneIsStartedInBackground_itSetsBackgroundLaunchPrecondition() {
        // Given
        let initialTime: Date = .mockDecember15th2019At10AMUTC()
        var currentTime: Date = initialTime
        let sdkContext: DatadogContext = .mockWith(sdkInitDate: currentTime)
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        // Keep session active without exceeding maxDuration — stop one step before it would expire
        while currentTime.addingTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration - 1) < initialTime.addingTimeInterval(RUMSessionScope.Constants.sessionMaxDuration) {
            currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration - 1)
            _ = scope.process(
                command: RUMCommandMock(time: currentTime, isUserInteraction: true),
                context: sdkContext,
                writer: writer
            )
        }

        // When - advance past maxDuration without triggering inactivity timeout, then send in background
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration - 1)
        let backgroundContext: DatadogContext = .mockWith(
            sdkInitDate: .mockDecember15th2019At10AMUTC(),
            launchInfo: .mockWith(
                launchReason: .backgroundLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: currentTime)
        )
        _ = scope.process(
            command: RUMCommandMock(time: currentTime, isUserInteraction: true),
            context: backgroundContext,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .backgroundLaunch)
    }

    func testGivenStoppedSession_whenNewOneIsStartedInBackground_itSetsBackgroundLaunchPrecondition() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let sdkContext: DatadogContext = .mockWith(sdkInitDate: currentTime)
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMStopSessionCommand(time: currentTime), context: sdkContext, writer: writer)

        // When
        currentTime.addTimeInterval(1)
        let backgroundContext: DatadogContext = .mockWith(
            sdkInitDate: .mockDecember15th2019At10AMUTC(),
            launchInfo: .mockWith(
                launchReason: .backgroundLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: currentTime)
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: currentTime),
            context: backgroundContext,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .backgroundLaunch)
    }

    func testGivenInactiveSession_whenNewOneIsStartedInBackgroundWithPrewarming_itSetsPrewarmPrecondition() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let sdkContext: DatadogContext = .mockWith(sdkInitDate: currentTime)
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        // When
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)
        let backgroundContext: DatadogContext = .mockWith(
            sdkInitDate: .mockDecember15th2019At10AMUTC(),
            launchInfo: .mockWith(
                launchReason: .prewarming,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: currentTime)
        )
        _ = scope.process(
            command: RUMCommandMock(time: currentTime, isUserInteraction: true),
            context: backgroundContext,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .prewarm)
    }

    func testGivenStoppedSession_whenNewOneIsStartedInBackgroundWithPrewarming_itSetsPrewarmPrecondition() {
        // Given
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let sdkContext: DatadogContext = .mockWith(sdkInitDate: currentTime)
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(samplingRate: 100),
            sdkContext: sdkContext
        )

        currentTime.addTimeInterval(1)
        _ = scope.process(command: RUMStopSessionCommand(time: currentTime), context: sdkContext, writer: writer)

        // When
        currentTime.addTimeInterval(1)
        let backgroundContext: DatadogContext = .mockWith(
            sdkInitDate: .mockDecember15th2019At10AMUTC(),
            launchInfo: .mockWith(
                launchReason: .prewarming,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: currentTime)
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: currentTime),
            context: backgroundContext,
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .prewarm)
    }

    func testGivenUserLaunchedApp_whenSessionTimesOutInBackground_itSetsInactivityTimeoutPrecondition() {
        // Given - app launched by user, session becomes inactive
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let sdkContext: DatadogContext = .mockWith(
            sdkInitDate: currentTime,
            launchInfo: .mockWith(launchReason: .userLaunch)
        )
        let featureScope = FeatureScopeMock()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(featureScope: featureScope, samplingRate: 100),
            sdkContext: sdkContext
        )

        // When - session times out while app is in background
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)
        let backgroundContext: DatadogContext = .mockWith(
            sdkInitDate: .mockDecember15th2019At10AMUTC(),
            launchInfo: .mockWith(
                launchReason: .userLaunch,
                processLaunchDate: .mockDecember15th2019At10AMUTC()
            ),
            applicationStateHistory: .mockAppInBackground(since: currentTime)
        )
        _ = scope.process(
            command: RUMCommandMock(time: currentTime, isUserInteraction: true),
            context: backgroundContext,
            writer: writer
        )

        // Then - end-reason-based precondition is used, not backgroundLaunch
        XCTAssertEqual(scope.activeSession?.context.sessionPrecondition, .inactivityTimeout)
        // And no error telemetry is fired for .userLaunch in background (it is a valid scenario)
        XCTAssertNil(featureScope.telemetryMock.messages.firstError())
    }
}
