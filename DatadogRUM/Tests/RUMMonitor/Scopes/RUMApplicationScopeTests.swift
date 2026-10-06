/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
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
        XCTAssertTrue(transferredViewScope.isActiveView)
        XCTAssertEqual(nextSession.viewScopes.filter(\.isActiveView).count, 1)
        XCTAssertFalse(nextSession.isInitialSession, "Any next session in the application must be marked as 'not initial'")
    }
    #endif

    // MARK: - RUM Session Sampling

    func testWhenSamplingRateIs100_allEventsAreSent() {
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                samplingRate: 100,
                featureFlags: [.viewUpdates: false]
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
        let resourceKey = "stopped-session-success"
        let firstView = ViewIdentifier("previous-session-view")
        let secondView = ViewIdentifier("current-session-view")
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
        let resourceKey = "stopped-session-error"
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("previous-session-error-view")),
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
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.040), identity: ViewIdentifier("current-session-error-view")),
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
                type: "TestResourceError",
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
        let first = RUMResourceCompletionFixture(applicationScope: true)
        let second = RUMResourceCompletionFixture(applicationScope: true)
        let completion = try first.automaticCompletion(error: true)
        let key = try XCTUnwrap(completion as? RUMResourceCommand).resourceKey
        for fixture in [first, second] {
            fixture.startView("owner")
            fixture.startAction("owner")
            fixture.startResource(key)
            fixture.send(completion)
            fixture.stopAction()
            XCTAssertEqual(fixture.errors.count, 1)
            try fixture.assertAction("owner", resources: 0, errors: 1)
        }
        XCTAssertNotEqual(first.errors.first?.view.id, second.errors.first?.view.id)
        XCTAssertNotEqual(first.errors.first?.session.id, second.errors.first?.session.id)
    }

    func testGivenExpiredAutomaticResourceOwner_itDoesNotAdoptRestoredView() throws {
        let fixture = RUMResourceCompletionFixture(applicationScope: true)
        let completion = try fixture.automaticCompletion(error: true)
        let key = try XCTUnwrap(completion as? RUMResourceCommand).resourceKey
        fixture.startView("owner")
        fixture.startResource(key)
        let previous = try XCTUnwrap(fixture.application.activeSession).sessionUUID
        fixture.time.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration + 1)
        fixture.send(completion)
        fixture.startView("new")
        fixture.startAction("new")
        fixture.stopAction()
        XCTAssertNotEqual(fixture.application.activeSession?.sessionUUID, previous)
        XCTAssertTrue(fixture.errors.isEmpty)
        XCTAssertTrue(fixture.resources.isEmpty)
        try fixture.assertAction("new", resources: 0, errors: 0)
    }
}

extension RUMApplicationScopeTests {
    private var routingDate: Date { Date(timeIntervalSince1970: 1_600_000_000) }
    private var routingSceneA: RUMSceneIdentifier { RUMSceneIdentifier(rawValue: "scene-a") }
    private var routingSceneB: RUMSceneIdentifier { RUMSceneIdentifier(rawValue: "scene-b") }

    private func routingApplication(
        enabled: Bool = true, mapper: RUMEventsMapper = .mockNoOp(), featureScope: FeatureScope = NOPFeatureScope()
    ) -> (RUMApplicationScope, DatadogContext) {
        let context = DatadogContext.mockWith(
            sdkInitDate: routingDate,
            launchInfo: .mockWith(launchReason: .userLaunch, processLaunchDate: routingDate),
            applicationStateHistory: .mockAppInForeground(since: routingDate)
        )
        let cache = ViewCache(dateProvider: DateProviderMock(now: routingDate), isMultiSceneTrackingEnabled: enabled)
        let app = createRUMApplicationScope(
            dependencies: .mockWith(featureScope: featureScope, eventBuilder: RUMEventBuilder(eventsMapper: mapper), viewCache: cache, featureFlags: [.multiSceneTracking: enabled]),
            sdkContext: context
        )
        return (app, context)
    }

    private func navigate(_ app: RUMApplicationScope, context: DatadogContext, scene: RUMSceneIdentifier?, name: String, after seconds: TimeInterval) {
        let command = RUMStartViewCommand(
            time: routingDate.addingTimeInterval(seconds),
            identity: ViewIdentifier(name),
            name: name,
            path: name,
            globalAttributes: [:],
            attributes: [:],
            instrumentationType: .manual,
            target: scene.map(RUMCommandTarget.scene) ?? .processRepresentative
        )
        _ = app.process(command: command, context: context, writer: writer)
    }

    private func startRoutingPeers(_ app: RUMApplicationScope, context: DatadogContext) {
        navigate(app, context: context, scene: routingSceneA, name: "a", after: 1)
        navigate(app, context: context, scene: routingSceneB, name: "b", after: 2)
    }

    private final class DeferredRoutingWriter: Writer {
        var events: [Encodable] = []
        var completions: [CompletionHandler] = []

        func write<T: Encodable, M: Encodable>(value: T, metadata: M?, completion: @escaping CompletionHandler) {
            events.append(value)
            completions.append(completion)
        }
    }

    func testMultiSceneSessionStop_restoresForegroundPeersWithFreshViewIDs() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let old = try XCTUnwrap(app.activeSession)
        let oldViews = old.viewScopes.filter { $0.isActiveView }
        _ = app.process(command: RUMStopSessionCommand(time: routingDate.addingTimeInterval(3)), context: context, writer: writer)
        var action = RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(4), actionType: .custom, name: "restart")
        action.target = .scene(routingSceneA)
        _ = app.process(command: action, context: context, writer: writer)
        let restored = try XCTUnwrap(app.activeSession)
        XCTAssertNotEqual(restored.sessionUUID, old.sessionUUID)
        XCTAssertEqual(Set(restored.viewScopes.filter { $0.isActiveView }.map { $0.viewName }), Set(["a", "b"]))
        XCTAssertTrue(Set(oldViews.map { $0.viewUUID }).isDisjoint(with: restored.viewScopes.map { $0.viewUUID }))
        XCTAssertTrue(restored.viewScopes.allSatisfy { $0.resourceScopes.isEmpty && $0.userActionScope == nil })
        XCTAssertEqual(Set(writer.events(ofType: RUMViewEvent.self).filter { $0.session.id == restored.sessionUUID.toRUMDataFormat }.map { $0.view.name }), Set(["a", "b"]))
    }

    func testMultiSceneSessionTimeout_restoresForegroundPeersWithFreshViewIDs() throws {
        for maximumDuration in [false, true] {
            let (app, context) = routingApplication()
            startRoutingPeers(app, context: context)
            let old = try XCTUnwrap(app.activeSession)
            let ids = Set(old.viewScopes.map { $0.viewUUID })
            if maximumDuration {
                for elapsed in stride(from: 600.0, to: RUMSessionScope.Constants.sessionMaxDuration, by: 600.0) {
                    var interaction = RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(elapsed), actionType: .custom)
                    interaction.target = .scene(routingSceneA)
                    _ = app.process(command: interaction, context: context, writer: writer)
                    XCTAssertEqual(app.activeSession?.sessionUUID, old.sessionUUID)
                }
            }
            let elapsed = (maximumDuration ? RUMSessionScope.Constants.sessionMaxDuration : RUMSessionScope.Constants.sessionTimeoutDuration) + 3
            var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingDate.addingTimeInterval(elapsed))
            error.target = .scene(routingSceneA)
            _ = app.process(command: error, context: context, writer: writer)
            let current = try XCTUnwrap(app.activeSession)
            XCTAssertEqual(old.endReason, maximumDuration ? .maxDuration : .timeOut)
            XCTAssertEqual(current.startPrecondition, maximumDuration ? .maxDuration : .inactivityTimeout)
            XCTAssertNotEqual(current.sessionUUID, old.sessionUUID)
            XCTAssertEqual(Set(current.viewScopes.filter { $0.isActiveView }.map { $0.viewName }), Set(["a", "b"]))
            XCTAssertTrue(ids.isDisjoint(with: current.viewScopes.map { $0.viewUUID }))
            XCTAssertEqual(writer.events(ofType: RUMErrorEvent.self).last?.view.name, "a")
            XCTAssertTrue(current.viewScopes.allSatisfy { $0.resourceScopes.isEmpty && $0.userActionScope == nil })
        }
    }

    func testMultiSceneNavigationAfterRollover_restoresOnlyUnaffectedPeers() throws {
        for expiration in ["stop", "timeout", "maximum"] {
            for targetKind in ["scene", "representative", "legacy", "nil-legacy", "unknown"] {
                for stopNavigation in [false, true] {
                    let (app, context) = routingApplication()
                    if targetKind == "nil-legacy" {
                        navigate(app, context: context, scene: nil, name: "legacy", after: 1)
                        let legacy = try XCTUnwrap(app.activeSession?.viewScopes.last(where: { $0.isActiveView && $0.viewName == "legacy" }))
                        navigate(app, context: context, scene: routingSceneA, name: "a", after: 2)
                        var interaction = RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(2.5), actionType: .custom)
                        interaction.target = .view(legacy.viewUUID)
                        _ = app.process(command: interaction, context: context, writer: writer)
                    } else {
                        startRoutingPeers(app, context: context)
                    }
                    let old = try XCTUnwrap(app.activeSession)
                    let representativeName = targetKind == "nil-legacy" ? "legacy" : "b"
                    let selectedName = targetKind == "scene" ? "a" : representativeName
                    let peerName = selectedName == "a" ? "b" : "a"
                    let selected = try XCTUnwrap(old.viewScopes.last(where: { $0.isActiveView && $0.viewName == selectedName }))
                    var target: RUMCommandTarget = targetKind == "scene" ? .scene(routingSceneA) : .processRepresentative
                    if targetKind == "legacy" || targetKind == "nil-legacy" {
                        let legacyID = DefaultRUMUUIDGenerator().generateUnique()
                        old.dependencies.viewCache.insert(id: legacyID.toRUMDataFormat, timestamp: routingDate.timeIntervalSince1970.dd.toInt64Milliseconds)
                        target = .view(legacyID)
                    }
                    if targetKind == "unknown" {
                        target = .view(DefaultRUMUUIDGenerator().generateUnique())
                    }
                    var navigationTime: TimeInterval = 4
                    if expiration == "stop" {
                        _ = app.process(command: RUMStopSessionCommand(time: routingDate.addingTimeInterval(3)), context: context, writer: writer)
                    } else if expiration == "timeout" {
                        navigationTime = RUMSessionScope.Constants.sessionTimeoutDuration + 4
                    } else {
                        for elapsed in stride(from: 600.0, to: RUMSessionScope.Constants.sessionMaxDuration, by: 600.0) {
                            var interaction = RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(elapsed), actionType: .custom)
                            interaction.target = .view(selected.viewUUID)
                            _ = app.process(command: interaction, context: context, writer: writer)
                        }
                        navigationTime = RUMSessionScope.Constants.sessionMaxDuration + 4
                    }
                    if stopNavigation {
                        var stop = RUMStopViewCommand.mockWith(time: routingDate.addingTimeInterval(navigationTime), identity: ViewIdentifier(selectedName))
                        stop.target = target
                        _ = app.process(command: stop, context: context, writer: writer)
                    } else {
                        let start = RUMStartViewCommand(
                            time: routingDate.addingTimeInterval(navigationTime),
                            identity: ViewIdentifier("next"),
                            name: "next",
                            path: "next",
                            globalAttributes: [:],
                            attributes: [:],
                            instrumentationType: .manual,
                            target: target
                        )
                        _ = app.process(command: start, context: context, writer: writer)
                    }
                    let current = try XCTUnwrap(app.activeSession)
                    XCTAssertNotEqual(current.sessionUUID, old.sessionUUID)
                    let expected = targetKind == "unknown" ? Set(["a", "b"]) : (stopNavigation ? Set([peerName]) : Set(["next", peerName]))
                    XCTAssertEqual(Set(current.viewScopes.filter { $0.isActiveView }.map { $0.viewName }), expected)
                    if targetKind != "unknown" {
                        XCTAssertTrue(current.viewScopes.allSatisfy { $0.viewName != selectedName })
                    }
                    if !stopNavigation && targetKind != "unknown" {
                        XCTAssertEqual(current.viewScopes.last(where: { $0.isActiveView && $0.viewName == "next" })?.sceneIdentifier, selected.sceneIdentifier)
                    }
                }
            }
        }
    }

    func testMultiSceneBackgroundRollover_doesNotRestoreForegroundViews() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let background = DatadogContext.mockWith(
            sdkInitDate: routingDate,
            launchInfo: context.launchInfo,
            applicationStateHistory: AppStateHistory(initialState: .background, date: routingDate.addingTimeInterval(3))
        )
        _ = app.process(command: RUMStopSessionCommand(time: routingDate.addingTimeInterval(3)), context: background, writer: writer)
        _ = app.process(command: RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(4), actionType: .custom), context: background, writer: writer)
        let current = try XCTUnwrap(app.activeSession)
        XCTAssertTrue(current.viewScopes.allSatisfy { $0.viewName != "a" && $0.viewName != "b" })
    }

    func testMultiSceneStoppedResource_retainsOriginalSessionAndViewOwner() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let oldSession = try XCTUnwrap(app.activeSession)
        let oldA = try XCTUnwrap(oldSession.viewScopes.first(where: { $0.sceneIdentifier == routingSceneA }))
        var start = RUMStartResourceCommand.mockWith(resourceKey: "late", time: routingDate.addingTimeInterval(3))
        start.target = .scene(routingSceneA)
        _ = app.process(command: start, context: context, writer: writer)
        _ = app.process(command: RUMStopSessionCommand(time: routingDate.addingTimeInterval(4)), context: context, writer: writer)
        navigate(app, context: context, scene: routingSceneB, name: "next-b", after: 5)
        let newSession = try XCTUnwrap(app.activeSession)
        var stop = RUMStopResourceCommand.mockWith(resourceKey: "late", time: routingDate.addingTimeInterval(6))
        stop.isAutomatic = true
        _ = app.process(command: stop, context: context, writer: writer)
        let resource = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        XCTAssertEqual(resource.session.id, oldSession.sessionUUID.toRUMDataFormat)
        XCTAssertEqual(resource.view.id, oldA.viewUUID.toRUMDataFormat)
        XCTAssertNotEqual(resource.session.id, newSession.sessionUUID.toRUMDataFormat)
        XCTAssertTrue(newSession.viewScopes.allSatisfy { $0.resourceScopes.isEmpty })
    }

    func testMultiSceneErrorCompletion_waitsForAllRecipientWrites() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let deferred = DeferredRoutingWriter()
        var count = 0
        var command = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingDate.addingTimeInterval(3), completionHandler: { count += 1 })
        command.target = .allActiveViews
        _ = app.process(command: command, context: context, writer: deferred)
        XCTAssertEqual(deferred.events.compactMap { $0 as? RUMErrorEvent }.count, 2)
        XCTAssertEqual(deferred.completions.count, 4)
        XCTAssertEqual(count, 0)
        while deferred.completions.count > 1 {
            deferred.completions.removeLast()()
            XCTAssertEqual(count, 0)
        }
        let last = try XCTUnwrap(deferred.completions.popLast())
        last()
        XCTAssertEqual(count, 1)
    }

    func testMultiSceneErrorCompletion_withNoEligibleRecipient_finishesOnce() {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let deferred = DeferredRoutingWriter()
        var count = 0
        var command = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingDate.addingTimeInterval(3), completionHandler: { count += 1 })
        command.target = .none
        _ = app.process(command: command, context: context, writer: deferred)
        XCTAssertTrue(deferred.events.isEmpty)
        XCTAssertEqual(count, 1)
    }

    func testMultiSceneErrorCompletion_withMapperDrop_finishesOnce() {
        let mapper = RUMEventsMapper.mockWith(errorEventMapper: { $0.view.name == "a" ? nil : $0 })
        let (app, context) = routingApplication(mapper: mapper)
        startRoutingPeers(app, context: context)
        let deferred = DeferredRoutingWriter()
        var count = 0
        var command = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingDate.addingTimeInterval(3), completionHandler: { count += 1 })
        command.target = .allActiveViews
        _ = app.process(command: command, context: context, writer: deferred)
        XCTAssertEqual(deferred.events.compactMap { $0 as? RUMErrorEvent }.count, 1)
        XCTAssertEqual(deferred.completions.count, 2)
        XCTAssertEqual(count, 0)
        deferred.completions.removeLast()()
        XCTAssertEqual(count, 0)
        deferred.completions.removeLast()()
        XCTAssertEqual(count, 1)
    }

    func testDefaultModeErrorCompletion_preservesExistingWriterDelivery() throws {
        let (app, context) = routingApplication(enabled: false)
        startRoutingPeers(app, context: context)
        let deferred = DeferredRoutingWriter()
        var count = 0
        let command = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingDate.addingTimeInterval(3), completionHandler: { count += 1 })
        _ = app.process(command: command, context: context, writer: deferred)
        XCTAssertEqual(deferred.events.compactMap { $0 as? RUMErrorEvent }.count, 1)
        XCTAssertEqual(deferred.completions.count, 2)
        deferred.completions.removeFirst()()
        XCTAssertEqual(count, 0)
        let viewCompletion = try XCTUnwrap(deferred.completions.popLast())
        viewCompletion()
        XCTAssertEqual(count, 1)
    }
}

extension RUMApplicationScopeTests {
    private func capturedReceiptContext(_ app: RUMApplicationScope, view: RUMViewScope) throws -> RUMCoreContext {
        let session = try XCTUnwrap(app.activeSession)
        return RUMCoreContext(
            applicationID: view.context.rumApplicationID,
            sessionID: session.sessionUUID.toRUMDataFormat,
            sessionSampler: session.sampler,
            viewID: view.viewUUID.toRUMDataFormat,
            userActionID: view.userActionScope?.actionUUID.toRUMDataFormat,
            viewServerTimeOffset: view.serverTimeOffset,
            viewPath: view.viewPath,
            viewName: view.viewName
        )
    }

    func testCapturedActionReceiptKeepsTheOriginalActionAfterReplacement() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let view = try XCTUnwrap(app.activeSession?.viewScopes.first { $0.sceneIdentifier == routingSceneA && $0.isActiveView })
        let captured = try capturedReceiptContext(app, view: view)
        let owner = RUMContextHandoff.Owner()
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: captured)
        var original = RUMStartUserActionCommand(
            time: routingDate.addingTimeInterval(3),
            globalAttributes: [:],
            attributes: [:],
            instrumentation: .swiftuiAutomatic,
            actionType: .scroll,
            name: "original"
        )
        original.target = .scene(routingSceneA)
        original.actionReceipt = receipt
        _ = app.process(command: original, context: context, writer: writer)
        let originalID = try XCTUnwrap(view.userActionScope).actionUUID.toRUMDataFormat
        var replacement = RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(4), instrumentation: .manual, name: "replacement")
        replacement.target = .scene(routingSceneA)
        _ = app.process(command: replacement, context: context, writer: writer)
        XCTAssertNotEqual(view.userActionScope?.actionUUID.toRUMDataFormat, originalID)
        XCTAssertEqual(view.userActionScope?.name, "replacement")
        XCTAssertEqual(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID), originalID)
        XCTAssertNil(app.activeSession?.viewScopes.first { $0.sceneIdentifier == routingSceneB && $0.isActiveView }?.userActionScope)
    }

    func testPriorityDroppedReceiptDoesNotAdoptTheExistingOrLaterAction() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let view = try XCTUnwrap(app.activeSession?.viewScopes.first { $0.sceneIdentifier == routingSceneA && $0.isActiveView })
        var existing = RUMStartUserActionCommand(
            time: routingDate.addingTimeInterval(3),
            globalAttributes: [:],
            attributes: [:],
            instrumentation: .manual,
            actionType: .scroll,
            name: "existing"
        )
        existing.target = .scene(routingSceneA)
        _ = app.process(command: existing, context: context, writer: writer)
        let existingID = try XCTUnwrap(view.userActionScope).actionUUID
        let captured = try capturedReceiptContext(app, view: view)
        let owner = RUMContextHandoff.Owner()
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: captured)
        var dropped = RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(4), instrumentation: .swiftuiAutomatic, name: "dropped")
        dropped.target = .scene(routingSceneA)
        dropped.actionReceipt = receipt
        _ = app.process(command: dropped, context: context, writer: writer)
        XCTAssertEqual(view.userActionScope?.actionUUID, existingID)
        XCTAssertEqual(view.userActionScope?.name, "existing")
        XCTAssertNil(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID))
        var later = RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(5), instrumentation: .crossPlatform("later"), name: "later")
        later.target = .scene(routingSceneA)
        _ = app.process(command: later, context: context, writer: writer)
        let laterScope = try XCTUnwrap(view.userActionScope)
        XCTAssertEqual(laterScope.name, "later")
        XCTAssertNotEqual(laterScope.actionUUID.toRUMDataFormat, captured.userActionID)
        XCTAssertNil(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID))
    }

    func testImmediateCustomActionReceiptClaimsTheEmittedLocalScope() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let view = try XCTUnwrap(app.activeSession?.viewScopes.first { $0.sceneIdentifier == routingSceneA && $0.isActiveView })
        let captured = try capturedReceiptContext(app, view: view)
        let owner = RUMContextHandoff.Owner()
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: captured)
        var command = RUMAddUserActionCommand.mockWith(time: routingDate.addingTimeInterval(3), actionType: .custom, name: "custom")
        command.target = .scene(routingSceneA)
        command.actionReceipt = receipt
        _ = app.process(command: command, context: context, writer: writer)
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first { $0.action.target?.name == "custom" })
        XCTAssertNil(view.userActionScope)
        XCTAssertEqual(action.view.id, captured.viewID)
        XCTAssertEqual(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID), action.action.id)
    }

    #if !os(macOS)
    func testUncertainLaunchReceiptRemainsUnclaimedUntilActualResolution() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let view = try XCTUnwrap(app.activeSession?.viewScopes.first { $0.sceneIdentifier == routingSceneA && $0.isActiveView })
        let captured = try capturedReceiptContext(app, view: view)
        let owner = RUMContextHandoff.Owner()
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: captured)
        let uncertain = DatadogContext.mockWith(
            sdkInitDate: routingDate,
            launchInfo: .mockWith(launchReason: .uncertain, processLaunchDate: routingDate),
            applicationStateHistory: .mockWith(initialState: .background, date: routingDate)
        )
        var command = RUMStartUserActionCommand(
            time: routingDate.addingTimeInterval(3),
            globalAttributes: [:],
            attributes: [:],
            instrumentation: .swiftuiAutomatic,
            actionType: .scroll,
            name: "deferred"
        )
        command.target = .scene(routingSceneA)
        command.actionReceipt = receipt
        _ = app.process(command: command, context: uncertain, writer: writer)
        XCTAssertNil(view.userActionScope)
        XCTAssertNil(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID))
        _ = app.process(
            command: RUMHandleAppLifecycleEventCommand(time: routingDate.addingTimeInterval(4), event: .willEnterForeground),
            context: uncertain,
            writer: writer
        )
        let accepted = try XCTUnwrap(view.userActionScope)
        XCTAssertEqual(accepted.name, "deferred")
        XCTAssertEqual(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID), accepted.actionUUID.toRUMDataFormat)
    }
    #endif
}

extension RUMApplicationScopeTests {
    func testContinuousActionReceiptKeepsTheClaimedActionAfterTerminalAndReplacement() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let view = try XCTUnwrap(app.activeSession?.viewScopes.first {
            $0.sceneIdentifier == routingSceneA && $0.isActiveView
        })
        let captured = try capturedReceiptContext(app, view: view)
        let owner = RUMContextHandoff.Owner()
        let ownership = RUMContinuousActionOwnership(sceneIdentifier: routingSceneA, owner: owner)
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: captured)
        var start = RUMStartUserActionCommand(
            time: routingDate.addingTimeInterval(3),
            globalAttributes: [:],
            attributes: [:],
            instrumentation: .swiftuiAutomatic,
            actionType: .scroll,
            name: "original-scroll"
        )
        start.target = .continuousAction(ownership)
        start.actionReceipt = receipt
        _ = app.process(command: start, context: context, writer: writer)
        let original = try XCTUnwrap(ownership.claim)
        XCTAssertEqual(original.actionID, try XCTUnwrap(view.userActionScope).actionUUID)
        XCTAssertEqual(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID), original.actionID.toRUMDataFormat)
        var peer = RUMAddUserActionCommand.mockWith(
            time: routingDate.addingTimeInterval(4), instrumentation: .manual, name: "peer-action"
        )
        peer.target = .scene(routingSceneB)
        _ = app.process(command: peer, context: context, writer: writer)
        var stop = RUMStopUserActionCommand(
            time: routingDate.addingTimeInterval(5),
            globalAttributes: [:],
            attributes: [:],
            actionType: .scroll,
            name: nil
        )
        stop.target = .continuousAction(ownership)
        _ = app.process(command: stop, context: context, writer: writer)
        XCTAssertTrue(ownership.isClosed)
        let emitted = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first {
            $0.action.target?.name == "original-scroll"
        })
        XCTAssertEqual(emitted.view.id, captured.viewID)
        XCTAssertEqual(emitted.action.id, original.actionID.toRUMDataFormat)
        var later = RUMAddUserActionCommand.mockWith(
            time: routingDate.addingTimeInterval(6), instrumentation: .manual, name: "later-action"
        )
        later.target = .scene(routingSceneA)
        _ = app.process(command: later, context: context, writer: writer)
        XCTAssertNotEqual(view.userActionScope?.actionUUID, original.actionID)
        XCTAssertEqual(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID), original.actionID.toRUMDataFormat)
        owner.invalidate()
        XCTAssertNil(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID))
    }

    func testDroppedContinuousStartReceiptCannotClaimOnARepeatedStart() throws {
        let (app, context) = routingApplication()
        startRoutingPeers(app, context: context)
        let view = try XCTUnwrap(app.activeSession?.viewScopes.first {
            $0.sceneIdentifier == routingSceneA && $0.isActiveView
        })
        var manual = RUMStartUserActionCommand(
            time: routingDate.addingTimeInterval(3),
            globalAttributes: [:],
            attributes: [:],
            instrumentation: .manual,
            actionType: .scroll,
            name: "existing"
        )
        manual.target = .scene(routingSceneA)
        _ = app.process(command: manual, context: context, writer: writer)
        let existingID = try XCTUnwrap(view.userActionScope).actionUUID
        let captured = try capturedReceiptContext(app, view: view)
        let owner = RUMContextHandoff.Owner()
        let ownership = RUMContinuousActionOwnership(sceneIdentifier: routingSceneA, owner: owner)
        let receipt = RUMContextHandoff.ActionReceipt(owner: owner, context: captured)
        var start = RUMStartUserActionCommand(
            time: routingDate.addingTimeInterval(4),
            globalAttributes: [:],
            attributes: [:],
            instrumentation: .swiftuiAutomatic,
            actionType: .scroll,
            name: "dropped"
        )
        start.target = .continuousAction(ownership)
        start.actionReceipt = receipt
        _ = app.process(command: start, context: context, writer: writer)
        XCTAssertNil(ownership.claim)
        XCTAssertNil(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID))
        XCTAssertEqual(view.userActionScope?.actionUUID, existingID)
        XCTAssertEqual(view.userActionScope?.name, "existing")
        var stop = RUMStopUserActionCommand(
            time: routingDate.addingTimeInterval(5),
            globalAttributes: [:],
            attributes: [:],
            actionType: .scroll,
            name: nil
        )
        stop.target = .scene(routingSceneA)
        _ = app.process(command: stop, context: context, writer: writer)
        var replacement = RUMStartUserActionCommand(
            time: routingDate.addingTimeInterval(6),
            globalAttributes: [:],
            attributes: [:],
            instrumentation: .manual,
            actionType: .scroll,
            name: "replacement"
        )
        replacement.target = .scene(routingSceneA)
        _ = app.process(command: replacement, context: context, writer: writer)
        let replacementID = try XCTUnwrap(view.userActionScope).actionUUID
        XCTAssertNotEqual(replacementID, existingID)
        start.time = routingDate.addingTimeInterval(7)
        _ = app.process(command: start, context: context, writer: writer)
        XCTAssertEqual(view.userActionScope?.name, "replacement")
        XCTAssertEqual(view.userActionScope?.actionUUID, replacementID)
        XCTAssertNil(ownership.claim)
        XCTAssertNil(receipt.actionID(for: owner, sessionID: captured.sessionID, viewID: captured.viewID))
    }
}

extension RUMApplicationScopeTests {
    private func webViewKeepAliveCapture(_ app: RUMApplicationScope, owner: RUMContextHandoff.Owner) throws -> RUMContextHandoff.Capture {
        let view = try XCTUnwrap(app.activeSession?.viewScopes.first { $0.sceneIdentifier == routingSceneA && $0.isActiveView })
        return .init(
            owner: owner,
            value: .init(
                rumContext: try capturedReceiptContext(app, view: view), sceneIdentifier: routingSceneA.rawValue,
                hasPendingUserAction: false, excludedUserActionID: nil
            )
        )
    }

    func testCapturedWebViewKeepAlive_rejectsSessionTransitionBeforeApplication() throws {
        for restart in [false, true] {
            let scope = WebViewKeepAliveOwnerScope()
            let (app, context) = routingApplication(featureScope: scope)
            startRoutingPeers(app, context: context)
            let capture = try webViewKeepAliveCapture(app, owner: scope.owner)
            let native = try XCTUnwrap(capture.value.resolvedRUMContext(for: scope.owner))
            let receiverScope = FeatureScopeMock(context: .mockWith(additionalContext: [native]), deferEventWriteContext: true)
            let subscriber = RUMCommandSubscriberMock()
            let core = WebViewKeepAliveOwnerCore()
            core.owner = scope.owner
            let receiver = WebViewEventReceiver(
                featureScope: receiverScope, dateProvider: DateProviderMock(now: routingDate.addingTimeInterval(5)),
                commandSubscriber: subscriber, viewCache: ViewCache(dateProvider: DateProviderMock())
            )
            XCTAssertTrue(receiver.receive(
                message: .payload(WebViewMessageWithRUMContext(message: .rum(["date": 1_600_000_003_000, "view": ["id": "browser"]]), capture: capture)),
                from: core
            ))
            receiverScope.flushDeferredEventWriteContexts()
            XCTAssertEqual(receiverScope.eventsWritten.count, 1)
            let queued = try XCTUnwrap(subscriber.receivedCommands.firstElement(of: RUMKeepSessionAliveCommand.self))
            XCTAssertTrue(queued.capture?.owner === scope.owner)
            _ = app.process(command: RUMStopSessionCommand(time: routingDate.addingTimeInterval(4)), context: context, writer: writer)
            if restart { navigate(app, context: context, scene: routingSceneB, name: "replacement", after: 4.5) }
            let before = app.sessionScopes.map { $0.sessionUUID }
            let active = app.activeSession
            let interaction = active?.lastInteractionTime
            let count = writer.events.count
            _ = app.process(command: queued, context: context, writer: writer)
            XCTAssertEqual(app.sessionScopes.map { $0.sessionUUID }, before)
            XCTAssertTrue(app.activeSession === active)
            XCTAssertEqual(app.activeSession?.lastInteractionTime, interaction)
            XCTAssertEqual(writer.events.count, count)
        }
    }

    func testCapturedWebViewKeepAlive_rejectsInvalidOrReplacedOwnerAtApplication() throws {
        for replacement in [false, true] {
            let scope = WebViewKeepAliveOwnerScope()
            let (app, context) = routingApplication(featureScope: scope)
            startRoutingPeers(app, context: context)
            let capture = try webViewKeepAliveCapture(app, owner: scope.owner)
            if replacement { scope.owner = RUMContextHandoff.Owner() } else { scope.owner.invalidate() }
            let count = writer.events.count
            let session = app.activeSession
            _ = app.process(
                command: RUMKeepSessionAliveCommand(time: routingDate.addingTimeInterval(5), attributes: [:], capture: capture),
                context: context, writer: writer
            )
            XCTAssertTrue(app.activeSession === session)
            XCTAssertEqual(writer.events.count, count)
        }
    }

    func testCapturedWebViewKeepAlive_doesNotRestartExpiredSession() throws {
        for elapsed in [RUMSessionScope.Constants.sessionTimeoutDuration + 3, RUMSessionScope.Constants.sessionMaxDuration + 3] {
            let scope = WebViewKeepAliveOwnerScope()
            let (app, context) = routingApplication(featureScope: scope)
            startRoutingPeers(app, context: context)
            let capture = try webViewKeepAliveCapture(app, owner: scope.owner)
            let session = try XCTUnwrap(app.activeSession)
            let interaction = session.lastInteractionTime
            let count = writer.events.count
            _ = app.process(
                command: RUMKeepSessionAliveCommand(time: routingDate.addingTimeInterval(elapsed), attributes: [:], capture: capture),
                context: context, writer: writer
            )
            XCTAssertTrue(app.activeSession === session)
            XCTAssertNil(session.endReason)
            XCTAssertEqual(session.lastInteractionTime, interaction)
            XCTAssertEqual(writer.events.count, count)
        }
    }

    func testCapturedWebViewKeepAlive_rejectsMaximumDurationWhileRecentlyActive() throws {
        let scope = WebViewKeepAliveOwnerScope()
        let (app, context) = routingApplication(featureScope: scope)
        startRoutingPeers(app, context: context)
        let capture = try webViewKeepAliveCapture(app, owner: scope.owner)
        let session = try XCTUnwrap(app.activeSession)

        for elapsed in stride(from: 600.0, to: RUMSessionScope.Constants.sessionMaxDuration, by: 600.0) {
            let time = routingDate.addingTimeInterval(elapsed)
            var interaction = RUMAddUserActionCommand.mockWith(time: time, actionType: .custom)
            interaction.target = .scene(routingSceneA)
            _ = app.process(command: interaction, context: context, writer: writer)
            XCTAssertTrue(app.activeSession === session)
            XCTAssertEqual(session.lastInteractionTime, time)
        }

        let expiredDate = routingDate.addingTimeInterval(RUMSessionScope.Constants.sessionMaxDuration + 3)
        XCTAssertFalse(RUMSessionScope.hasTimedOut(lastInteractionTime: session.lastInteractionTime, currentTime: expiredDate))
        XCTAssertTrue(RUMSessionScope.hasExpired(sessionStartTime: session.sessionStartTime, currentTime: expiredDate))
        let interaction = session.lastInteractionTime
        let count = writer.events.count

        _ = app.process(
            command: RUMKeepSessionAliveCommand(time: expiredDate, attributes: [:], capture: capture),
            context: context, writer: writer
        )

        XCTAssertTrue(app.activeSession === session)
        XCTAssertNil(session.endReason)
        XCTAssertEqual(session.lastInteractionTime, interaction)
        XCTAssertEqual(writer.events.count, count)
    }

    func testCapturedWebViewKeepAlive_preservesLegacyAndOriginatingSceneTargets() throws {
        let scope = WebViewKeepAliveOwnerScope()
        let (app, context) = routingApplication(featureScope: scope)
        startRoutingPeers(app, context: context)
        let capture = try webViewKeepAliveCapture(app, owner: scope.owner)
        let command = RUMKeepSessionAliveCommand(time: routingDate.addingTimeInterval(5), attributes: [:], capture: capture)
        if case .scene(let scene) = command.target { XCTAssertEqual(scene, routingSceneA) } else { XCTFail("Missing originating scene") }
        let session = try XCTUnwrap(app.activeSession)
        let interaction = session.lastInteractionTime
        _ = app.process(command: command, context: context, writer: writer)
        XCTAssertTrue(app.activeSession === session)
        XCTAssertEqual(session.lastInteractionTime, interaction)
        let legacy = RUMKeepSessionAliveCommand(time: routingDate.addingTimeInterval(6), attributes: [:])
        XCTAssertNil(legacy.capture)
        if case .processRepresentative = legacy.target {} else { XCTFail("Legacy target changed") }
    }
}

private final class WebViewKeepAliveOwnerScope: FeatureScope, RUMContextHandoffOwnerProviding, @unchecked Sendable {
    private let base = FeatureScopeMock()
    var owner = RUMContextHandoff.Owner()
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { owner }
    var dataStore: DataStore { base.dataStore }
    var telemetry: Telemetry { base.telemetry }
    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        base.eventWriteContext(bypassConsent: bypassConsent, block)
    }
    func context(_ block: @escaping (DatadogContext) -> Void) { base.context(block) }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { base.set(context: context) }
    func set(anonymousId: String?) { base.set(anonymousId: anonymousId) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { base.send(message: message, else: fallback) }
}

private final class WebViewKeepAliveOwnerCore: PassthroughCoreMock, RUMContextHandoffOwnerProviding, @unchecked Sendable {
    var owner: RUMContextHandoff.Owner?
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { owner }
}
