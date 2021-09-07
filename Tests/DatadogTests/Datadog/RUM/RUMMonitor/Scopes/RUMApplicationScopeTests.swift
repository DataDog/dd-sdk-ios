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
            backgroundEventTrackingEnabled: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, "abc-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenFirstViewIsStarted_itStartsNewSession() {
        let expectation = self.expectation(description: "onSessionStart is called")
        let onSessionStart: RUMSessionListener = { sessionId, isDiscarded in
            XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
            XCTAssertTrue(isDiscarded)
            expectation.fulfill()
        }

        let scope = RUMApplicationScope(
            rumApplicationID: .mockAny(),
            dependencies: .mockWith(
                onSessionStart: onSessionStart
            ),
            samplingRate: 0,
            backgroundEventTrackingEnabled: .mockAny()
        )

        XCTAssertNil(scope.sessionScope)
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockAny()))
        waitForExpectations(timeout: 0.5)
        XCTAssertNotNil(scope.sessionScope)
        XCTAssertEqual(scope.sessionScope?.backgroundEventTrackingEnabled, scope.backgroundEventTrackingEnabled)
    }

    func testWhenSessionExpires_itStartsANewOneAndTransfersActiveViews() throws {
        let expectation = self.expectation(description: "onSessionStart is called twice")
        expectation.expectedFulfillmentCount = 2

        let onSessionStart: RUMSessionListener = { sessionId, isDiscarded in
            XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
            XCTAssertFalse(isDiscarded)
            expectation.fulfill()
        }

        let scope = RUMApplicationScope(
            rumApplicationID: .mockAny(),
            dependencies: .mockWith(
                onSessionStart: onSessionStart
            ),
            samplingRate: 100,
            backgroundEventTrackingEnabled: .mockAny()
        )

        var currentTime = Date()

        let view = createMockViewInWindow()
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: view))
        let firstSessionUUID = try XCTUnwrap(scope.sessionScope?.context.sessionID)
        let firstsSessionViewScopes = try XCTUnwrap(scope.sessionScope?.viewScopes)

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        _ = scope.process(command: RUMAddUserActionCommand.mockWith(time: currentTime))
        let secondSessionUUID = try XCTUnwrap(scope.sessionScope?.context.sessionID)
        let secondSessionViewScopes = try XCTUnwrap(scope.sessionScope?.viewScopes)
        let secondSessionViewScope = try XCTUnwrap(secondSessionViewScopes.first)

        waitForExpectations(timeout: 0.5)
        XCTAssertNotEqual(firstSessionUUID, secondSessionUUID)
        XCTAssertEqual(firstsSessionViewScopes.count, secondSessionViewScopes.count)
        XCTAssertTrue(secondSessionViewScope.identity.equals(view))
    }

    func testUntilSessionIsStarted_itIgnoresOtherCommands() {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny(), samplingRate: 100, backgroundEventTrackingEnabled: .mockAny())

        XCTAssertTrue(scope.process(command: RUMStopViewCommand.mockAny()))
        XCTAssertTrue(scope.process(command: RUMAddUserActionCommand.mockAny()))
        XCTAssertTrue(scope.process(command: RUMStopResourceCommand.mockAny()))
        XCTAssertNil(scope.sessionScope)
    }

    // MARK: - RUM Session Sampling

    func testWhenSamplingRateIs100_allEventsAreSent() {
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: dependencies, samplingRate: 100, backgroundEventTrackingEnabled: .mockAny())

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))

        XCTAssertEqual(try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).count, 2)
    }

    func testWhenSamplingRateIs0_noEventsAreSent() {
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: dependencies, samplingRate: 0, backgroundEventTrackingEnabled: .mockAny())

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))

        XCTAssertEqual(try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).count, 0)
    }

    func testWhenSamplingRateIs50_onlyHalfOfTheEventsAreSent() throws {
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: dependencies, samplingRate: 50, backgroundEventTrackingEnabled: .mockAny())

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
