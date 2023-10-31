/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class RUMApplicationScopeTests: XCTestCase {
    let context: DatadogContext = .mockAny()
    let writer = FileWriterMock()

    func testRootContext() {
        let scope = RUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "abc-123")
        )

        XCTAssertEqual(scope.context.rumApplicationID, "abc-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenFirstEventIsReceived_itStartsNewSession() throws {
        let expectation = self.expectation(description: "onSessionStart is called")
        let onSessionStart: RUM.SessionListener = { sessionId, isDiscarded in
            XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
            XCTAssertTrue(isDiscarded)
            expectation.fulfill()
        }

        // Given
        let currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockRejectAll(),
                onSessionStart: onSessionStart
            )
        )
        XCTAssertNil(scope.activeSession)

        // When
        let command = mockRandomRUMCommand().replacing(time: currentTime.addingTimeInterval(1))
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        waitForExpectations(timeout: 0.5)

        // Then
        let sessionScope = try XCTUnwrap(scope.activeSession)
        XCTAssertTrue(sessionScope.isInitialSession, "Starting the very first view in application must create initial session")
    }

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
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                onSessionStart: onSessionStart
            )
        )

        let view = createMockViewInWindow()

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: view.asRUMViewIdentity()),
            context: context,
            writer: writer
        )

        let initialSession = try XCTUnwrap(scope.activeSession)

        // When
        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: currentTime),
            context: context,
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
        XCTAssertTrue(transferredViewScope.identity.equals(view), "Transferred view scope must track the same view")
        XCTAssertFalse(nextSession.isInitialSession, "Any next session in the application must be marked as 'not initial'")
    }

    // MARK: - RUM Session Sampling

    func testWhenSamplingRateIs100_allEventsAreSent() {
        let currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: Sampler(samplingRate: 100)
            )
        )

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockViewIdentity),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(time: currentTime, identity: mockViewIdentity),
            context: context,
            writer: writer
        )

        // Two extra because of the ApplicationLaunch view start / stop
        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 4)
    }

    func testWhenSamplingRateIs0_noEventsAreSent() {
        let currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: Sampler(samplingRate: 0)
            )
        )

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockViewIdentity),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockViewIdentity),
            context: context,
            writer: writer
        )

        XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, 0)
    }

    func testWhenSamplingRateIs50_onlyHalfOfTheEventsAreSent() throws {
        var currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: Sampler(samplingRate: 50)
            )
        )

        let simulatedSessionsCount = 400
        (0..<simulatedSessionsCount).forEach { _ in
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockViewIdentity),
                context: context,
                writer: writer
            )
            _ = scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: mockViewIdentity),
                context: context,
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
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )

        let command = mockRandomRUMCommand().replacing(time: currentTime.addingTimeInterval(1))
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // When
        let stopCommand = RUMStopSessionCommand.mockAny()
        XCTAssertFalse(scope.process(command: stopCommand, context: context, writer: writer))

        // Then
        XCTAssertNil(scope.activeSession)
    }

    func testGivenStoppedSession_whenUserActionEvent_itStartsANewSession() throws {
        // Given
        let currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )
        XCTAssertTrue(scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(1), isUserInteraction: true),
            context: context,
            writer: writer
        ))
        XCTAssertFalse(scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: context,
            writer: writer
        ))
        XCTAssertTrue(scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(3), isUserInteraction: true),
            context: context,
            writer: writer
        ))

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertNotNil(scope.activeSession)
    }

    func testGivenStoppedSession_whenAUserActionOccurs_itRestartsTheLastKnownView() throws {
        // Given
        let currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )
        let viewName: String = .mockRandom()
        let viewPath: String = .mockRandom()
        XCTAssertTrue(scope.process(
            command: RUMStartViewCommand.mockWith(
                name: viewName,
                path: viewPath
            ),
            context: context,
            writer: writer
        ))
        XCTAssertFalse(scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: context,
            writer: writer
        ))
        let secondSesionStartTime = currentTime.addingTimeInterval(3)
        XCTAssertTrue(scope.process(
            command: RUMCommandMock(time: secondSesionStartTime, isUserInteraction: true),
            context: context,
            writer: writer
        ))

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 1)
        let activeSession = try XCTUnwrap(scope.activeSession)
        XCTAssertEqual(activeSession.viewScopes.count, 1)
        let activeView = try XCTUnwrap(activeSession.viewScopes.first)
        XCTAssertEqual(activeView.viewPath, viewPath)
        XCTAssertEqual(activeView.viewName, viewName)
        XCTAssertEqual(activeView.viewStartTime, secondSesionStartTime)
    }

    func testGivenStoppedSession_whenNonUserIntaractionEvent_itDoesNotStartANewSession() throws {
        // Given
        let currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )
        XCTAssertTrue(scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(1), isUserInteraction: true),
            context: context,
            writer: writer
        ))
        XCTAssertFalse(scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: context,
            writer: writer
        ))
        XCTAssertFalse(scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(3), isUserInteraction: false),
            context: context,
            writer: writer
        ))

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 0)
        XCTAssertNil(scope.activeSession)
    }

    func testGivenStoppedSessionProcessingResources_itCanStayInactive() throws {
        // Given
        let currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )
        XCTAssertTrue(scope.process(
            command: RUMStartResourceCommand.mockRandom(),
            context: context,
            writer: writer
        ))
        XCTAssertFalse(scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: context,
            writer: writer
        ))

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertNil(scope.activeSession)
    }

    func testGivenStoppedSessionProcessingResources_itIsRemovedWhenFinished() throws {
        // Given
        let currentTime = Date()
        let scope = RUMApplicationScope(
            dependencies: .mockWith(
                sessionSampler: .mockKeepAll()
            )
        )
        let resourceKey = "resources/1"
        XCTAssertTrue(scope.process(
            command: RUMStartResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: currentTime.addingTimeInterval(1)
            ),
            context: context,
            writer: writer
        ))
        let firstSession = scope.activeSession
        XCTAssertFalse(scope.process(
            command: RUMStopSessionCommand.mockWith(time: currentTime.addingTimeInterval(2)),
            context: context,
            writer: writer
        ))
        XCTAssertTrue(scope.process(
            command: RUMCommandMock(time: currentTime.addingTimeInterval(3), isUserInteraction: true),
            context: context,
            writer: writer
        ))
        let secondSession = scope.activeSession
        XCTAssertTrue(scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: currentTime.addingTimeInterval(4)
            ),
            context: context,
            writer: writer
        ))

        // Then
        XCTAssertEqual(scope.sessionScopes.count, 1)
        XCTAssertNotEqual(scope.activeSession?.sessionUUID, firstSession?.sessionUUID)
        XCTAssertEqual(scope.activeSession?.sessionUUID, secondSession?.sessionUUID)
    }
}
