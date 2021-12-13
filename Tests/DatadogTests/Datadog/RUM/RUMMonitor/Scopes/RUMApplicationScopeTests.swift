/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMApplicationScopeTests: XCTestCase {
    func testRootContext() {
        let scope = RUMApplicationScope(
            rumApplicationID: "abc-123",
            dependencies: .mockAny(),
            samplingRate: .mockAny(),
            sdkInitDate: .mockAny(),
            backgroundEventTrackingEnabled: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, "abc-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenFirstEventIsReceived_itStartsNewSession() throws {
        let expectation = self.expectation(description: "onSessionStart is called")
        let onSessionStart: RUMSessionListener = { sessionId, isDiscarded in
            XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
            XCTAssertTrue(isDiscarded)
            expectation.fulfill()
        }

        let scope = RUMApplicationScope(
            rumApplicationID: .mockAny(),
            dependencies: .mockWith(onSessionStart: onSessionStart),
            samplingRate: 0,
            sdkInitDate: .mockAny(),
            backgroundEventTrackingEnabled: .mockRandom()
        )

        XCTAssertNil(scope.sessionScope)
        XCTAssertTrue(scope.process(command: mockRandomRUMCommand()))
        waitForExpectations(timeout: 0.5)

        let sessionScope = try XCTUnwrap(scope.sessionScope)
        XCTAssertEqual(sessionScope.backgroundEventTrackingEnabled, scope.backgroundEventTrackingEnabled)
        XCTAssertTrue(sessionScope.isInitialSession, "Starting the very first view in application must create initial session")
    }

    func testWhenSessionExpires_itStartsANewOneAndTransfersActiveViews() throws {
        let expectation = self.expectation(description: "onSessionStart is called twice")
        expectation.expectedFulfillmentCount = 2

        let onSessionStart: RUMSessionListener = { sessionId, isDiscarded in
            XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
            XCTAssertFalse(isDiscarded)
            expectation.fulfill()
        }

        // Given
        let scope = RUMApplicationScope(
            rumApplicationID: .mockAny(),
            dependencies: .mockWith(onSessionStart: onSessionStart),
            samplingRate: 100,
            sdkInitDate: .mockAny(),
            backgroundEventTrackingEnabled: .mockAny()
        )

        var currentTime = Date()

        let view = createMockViewInWindow()
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: view))

        let initialSession = try XCTUnwrap(scope.sessionScope)

        // When
        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
        _ = scope.process(command: RUMAddUserActionCommand.mockWith(time: currentTime))

        // Then
        waitForExpectations(timeout: 0.5)

        let nextSession = try XCTUnwrap(scope.sessionScope)
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
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(
            rumApplicationID: .mockAny(),
            dependencies: dependencies,
            samplingRate: 100,
            sdkInitDate: .mockAny(),
            backgroundEventTrackingEnabled: .mockAny()
        )

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))

        XCTAssertEqual(try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).count, 2)
    }

    func testWhenSamplingRateIs0_noEventsAreSent() {
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(
            rumApplicationID: .mockAny(),
            dependencies: dependencies,
            samplingRate: 0,
            sdkInitDate: .mockAny(),
            backgroundEventTrackingEnabled: .mockAny()
        )

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))

        XCTAssertEqual(try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).count, 0)
    }

    func testWhenSamplingRateIs50_onlyHalfOfTheEventsAreSent() throws {
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(
            rumApplicationID: .mockAny(),
            dependencies: dependencies,
            samplingRate: 50,
            sdkInitDate: .mockAny(),
            backgroundEventTrackingEnabled: .mockAny()
        )

        var currentTime = Date()
        let simulatedSessionsCount = 200
        (0..<simulatedSessionsCount).forEach { _ in
            _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView))
            _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentTime, identity: mockView))
            currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration) // force the Session to be re-created
        }

        let viewEventsCount = try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).count
        let trackedSessionsCount = Double(viewEventsCount) / 2 // each Session should send 2 View updates

        XCTAssertGreaterThan(trackedSessionsCount, 100 * 0.8) // -20%
        XCTAssertLessThan(trackedSessionsCount, 100 * 1.2) // +20%
    }
}
