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

    /// Creates `RUMApplicationScope` instance and configures it with the effects applied when RUM gets enabled.
    /// TODO: RUM-1649 Move this configuration to `RUMApplicationScope.init()`, so we can remove this setup in tests.
    private func createRUMApplicationScope(
        dependencies: RUMScopeDependencies,
        sdkContext: DatadogContext = .mockWith(sdkInitDate: Date())
    ) -> RUMApplicationScope {
        let scope = RUMApplicationScope(dependencies: dependencies)
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
        let expectation = self.expectation(description: "onSessionStart is called")
        let onSessionStart: RUM.SessionListener = { sessionId, isDiscarded in
            XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
            XCTAssertTrue(isDiscarded)
            expectation.fulfill()
        }

        // When
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockRejectAll(),
                onSessionStart: onSessionStart
            )
        )

        waitForExpectations(timeout: 0.5)

        // Then
        let session = try XCTUnwrap(scope.activeSession)
        XCTAssertTrue(session.isInitialSession, "Starting the very first view in application must create initial session")
    }

    #if !os(watchOS)
    func testWhenSessionExpires_itStartsANewOneAndTransfersActiveViews() throws {
        let expectation = self.expectation(description: "onSessionStart is called twice")
        expectation.expectedFulfillmentCount = 2

        let onSessionStart: RUM.SessionListener = { sessionId, isDiscarded in
            XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
            XCTAssertFalse(isDiscarded)
            expectation.fulfill()
        }

        // Given
        var currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                onSessionStart: onSessionStart
            )
        )

        let view = createMockViewInWindow()

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: ViewIdentifier(view)),
            context: .mockAny(),
            writer: writer
        )

        let initialSession = try XCTUnwrap(scope.activeSession)

        // When
        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: currentTime),
            context: .mockAny(),
            writer: writer
        )

        // Then
        waitForExpectations(timeout: 0.5)

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
                sessionSampler: Sampler(samplingRate: 100)
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
                sessionSampler: Sampler(samplingRate: 0)
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
                sessionSampler: Sampler(samplingRate: 50)
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
                sessionSampler: .mockRandom() // no matter sampling
            )
        )

        let command = RUMStartResourceCommand.mockWith(time: currentTime.addingTimeInterval(1))
        _ = scope.process(command: command, context: .mockAny(), writer: writer)

        // When
        let stopCommand = RUMStopSessionCommand.mockAny()
        _ = scope.process(command: stopCommand, context: .mockAny(), writer: writer)

        // Then
        XCTAssertNil(scope.activeSession)
    }

    func testGivenStoppedSession_whenUserActionEvent_itStartsANewSession() throws {
        // Given
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )
        _ = scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(1), isUserInteraction: true),
            context: .mockAny(),
            writer: writer
        )
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: .mockAny(),
            writer: writer
        )

        // When
        _ = scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(3), isUserInteraction: true),
            context: .mockAny(),
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertNotNil(scope.activeSession)
    }

    func testGivenSessionProcessingResources_whenStopped_itStaysInactive() throws {
        // Given
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockRandom(),
            context: .mockAny(),
            writer: writer
        )

        // When
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: .mockAny(),
            writer: writer
        )

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertNil(scope.activeSession)
    }

    func testGivenSessionProcessingResources_whenStopped_itIsRemovedWhenResourceFinishes() throws {
        // Given
        let currentTime = Date()
        let scope = createRUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )
        let resourceKey = "resources/1"
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: currentTime.addingTimeInterval(1)
            ),
            context: .mockAny(),
            writer: writer
        )

        // When
        let firstSession = try XCTUnwrap(scope.activeSession)
        _ = scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: .mockAny(),
            writer: writer
        )
        XCTAssertEqual(scope.sessionScopes.count, 1)
        _ = scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(3), isUserInteraction: true),
            context: .mockAny(),
            writer: writer
        )
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
            dependencies: .mockWith(sessionSampler: .mockKeepAll()),
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
            dependencies: .mockWith(sessionSampler: .mockKeepAll()),
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
            dependencies: .mockWith(sessionSampler: .mockKeepAll()),
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
            dependencies: .mockWith(sessionSampler: .mockKeepAll()),
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
            dependencies: .mockWith(sessionSampler: .mockKeepAll()),
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
            dependencies: .mockWith(sessionSampler: .mockKeepAll()),
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
}
