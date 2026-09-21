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

    #if !os(macOS)
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
    #endif

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

    #if !os(macOS)
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
    #endif

    // MARK: - Resource Completion Ownership

    func testGivenStoppedSessionResource_whenItSucceeds_itDoesNotCountInNewSessionAction() throws {
        let time = Date.mockDecember15th2019At10AMUTC()
        let scope = createRUMApplicationScope(dependencies: .mockWith(samplingRate: 100, trackFrustrations: true))
        let resourceKey = "exp206-stopped-success"
        let firstView = ViewIdentifier("exp206-first")
        let secondView = ViewIdentifier("exp206-second")
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: firstView),
            context: .mockAny(),
            writer: writer
        )
        let firstSession = try XCTUnwrap(scope.activeSession)
        let firstViewID = try XCTUnwrap(firstSession.viewScopes.last?.viewUUID)
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.010),
                url: "https://example.com/stopped-success"
            ),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: time.addingTimeInterval(0.030)),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.040), identity: secondView),
            context: .mockAny(),
            writer: writer
        )
        let secondSession = try XCTUnwrap(scope.activeSession)
        let secondViewID = try XCTUnwrap(secondSession.viewScopes.last?.viewUUID)
        _ = scope.process(
            command: RUMStartUserActionCommand.mockWith(time: time.addingTimeInterval(0.050), actionType: resourceActionType, name: "new session action"),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.055), metrics: resourceMetrics(at: time)),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.060),
                kind: .native,
                httpStatusCode: 200,
                size: 42
            ),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(time: time.addingTimeInterval(0.070), actionType: resourceActionType),
            context: .mockAny(),
            writer: writer
        )

        let resources = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertEqual(resources.count, 1)
        let resource = try XCTUnwrap(resources.first)
        XCTAssertEqual(resource.session.id, firstSession.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(resource.view.id, firstViewID.toRUMDataFormat)
        XCTAssertEqual(resource.resource.encodedBodySize, 1_500)
        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action.session.id, secondSession.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(action.view.id, secondViewID.toRUMDataFormat)
        XCTAssertEqual(try XCTUnwrap(action.action.resource).count, 0)
        XCTAssertEqual(try XCTUnwrap(action.action.error).count, 0)
        XCTAssertNil(action.action.frustration)
    }

    func testGivenStoppedSessionResource_whenItFails_itDoesNotFrustrateNewSessionAction() throws {
        let time = Date.mockDecember15th2019At10AMUTC()
        let scope = createRUMApplicationScope(dependencies: .mockWith(samplingRate: 100, trackFrustrations: true))
        let resourceKey = "exp206-stopped-error"
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("exp206-first-error")),
            context: .mockAny(),
            writer: writer
        )
        let firstSession = try XCTUnwrap(scope.activeSession)
        let firstViewID = try XCTUnwrap(firstSession.viewScopes.last?.viewUUID)
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.010), url: "https://example.com/stopped-error"),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: time.addingTimeInterval(0.030)),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.040), identity: ViewIdentifier("exp206-second-error")),
            context: .mockAny(),
            writer: writer
        )
        let secondSession = try XCTUnwrap(scope.activeSession)
        let secondViewID = try XCTUnwrap(secondSession.viewScopes.last?.viewUUID)
        _ = scope.process(
            command: RUMStartUserActionCommand.mockWith(time: time.addingTimeInterval(0.050), actionType: resourceActionType, name: "new session action"),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.055), metrics: resourceMetrics(at: time)),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.060),
                message: "stopped error",
                type: "EXP206",
                source: .network,
                httpStatusCode: 500
            ),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(time: time.addingTimeInterval(0.070), actionType: resourceActionType),
            context: .mockAny(),
            writer: writer
        )

        let errors = writer.events(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errors.count, 1)
        let error = try XCTUnwrap(errors.first)
        XCTAssertEqual(error.session.id, firstSession.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(error.view.id, firstViewID.toRUMDataFormat)
        XCTAssertEqual(error.error.resource?.url, "https://example.com/stopped-error")
        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action.session.id, secondSession.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(action.view.id, secondViewID.toRUMDataFormat)
        XCTAssertEqual(try XCTUnwrap(action.action.resource).count, 0)
        XCTAssertEqual(try XCTUnwrap(action.action.error).count, 0)
        XCTAssertNil(action.action.frustration)
    }

    private var resourceActionType: RUMActionType {
        #if os(macOS)
        .click
        #else
        .tap
        #endif
    }

    private func resourceMetrics(at time: Date) -> ResourceMetrics {
        .mockWith(
            fetch: .init(start: time.addingTimeInterval(0.010), end: time.addingTimeInterval(0.020)),
            dns: .init(start: time.addingTimeInterval(0.011), end: time.addingTimeInterval(0.012)),
            responseBodySize: (encoded: 1_500, decoded: 2_048)
        )
    }
}

extension RUMApplicationScopeTests {
    func testGivenSameResourceKeyInSeparateApplications_itResolvesOwnersIndependently() throws {
        let first = E03ResourceScopeFixture(applicationScope: true)
        let second = E03ResourceScopeFixture(applicationScope: true)
        let completion = try first.automaticCompletion(error: true)
        let key = try XCTUnwrap(completion as? RUMResourceCommand).resourceKey
        for fixture in [first, second] {
            fixture.startView("owner"); fixture.startAction("owner"); fixture.startResource(key)
            fixture.send(completion); fixture.stopAction()
            XCTAssertEqual(fixture.errors.count, 1)
            try fixture.assertAction("owner", resources: 0, errors: 1)
        }
        XCTAssertNotEqual(first.errors.first?.view.id, second.errors.first?.view.id)
        XCTAssertNotEqual(first.errors.first?.session.id, second.errors.first?.session.id)
    }

    func testGivenExpiredAutomaticResourceOwner_itDoesNotAdoptRestoredView() throws {
        let fixture = E03ResourceScopeFixture(applicationScope: true)
        let completion = try fixture.automaticCompletion(error: true)
        let key = try XCTUnwrap(completion as? RUMResourceCommand).resourceKey
        fixture.startView("owner"); fixture.startResource(key)
        let previous = try XCTUnwrap(fixture.application.activeSession).sessionUUID
        fixture.time.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration + 1)
        fixture.send(completion)
        fixture.startView("new"); fixture.startAction("new"); fixture.stopAction()
        XCTAssertNotEqual(fixture.application.activeSession?.sessionUUID, previous)
        XCTAssertTrue(fixture.errors.isEmpty)
        XCTAssertTrue(fixture.resources.isEmpty)
        try fixture.assertAction("new", resources: 0, errors: 0)
    }
}
