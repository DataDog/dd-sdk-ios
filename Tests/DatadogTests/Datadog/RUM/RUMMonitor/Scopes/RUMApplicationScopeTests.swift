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
            samplingRate: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, "abc-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenFirstViewIsStarted_itStartsNewSession() {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny(), samplingRate: 100)

        XCTAssertNil(scope.sessionScope)
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockAny()))
        XCTAssertNotNil(scope.sessionScope)
    }

    func testWhenSessionExpires_itStartsANewOneAndTransfersActiveViews() throws {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny(), samplingRate: 100)
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

        XCTAssertNotEqual(firstSessionUUID, secondSessionUUID)
        XCTAssertEqual(firstsSessionViewScopes.count, secondSessionViewScopes.count)
        XCTAssertTrue(secondSessionViewScope.identity.equals(view))
    }

    func testUntilSessionIsStarted_itIgnoresOtherCommands() {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny(), samplingRate: 100)

        XCTAssertTrue(scope.process(command: RUMStopViewCommand.mockAny()))
        XCTAssertTrue(scope.process(command: RUMAddUserActionCommand.mockAny()))
        XCTAssertTrue(scope.process(command: RUMStopResourceCommand.mockAny()))
        XCTAssertNil(scope.sessionScope)
    }

    // MARK: - RUM Session Sampling

    func testWhenSamplingRateIs100_allEventsAreSent() {
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: dependencies, samplingRate: 100)

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))

        XCTAssertEqual(try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).count, 2)
    }

    func testWhenSamplingRateIs0_noEventsAreSent() {
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: dependencies, samplingRate: 0)

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))

        XCTAssertEqual(try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).count, 0)
    }

    func testWhenSamplingRateIs50_onlyHalfOfTheEventsAreSent() throws {
        let output = RUMEventOutputMock()
        let dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: dependencies, samplingRate: 50)

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
