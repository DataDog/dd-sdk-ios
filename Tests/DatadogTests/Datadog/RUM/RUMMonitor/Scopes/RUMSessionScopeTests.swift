/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMSessionScopeTests: XCTestCase {
    func testDefaultContext() {
        let parent: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: .mockAny())

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertNotEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenSessionIsSampled() {
        let parent: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 0, startTime: .mockAny())

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenSessionExceedsMaxDuration_itGetsClosed() {
        var currentTime = Date()
        let parent = RUMContextProviderMock()
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 50, startTime: currentTime)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)))
    }

    func testWhenSessionIsInactiveForCertainDuration_itGetsClosed() {
        var currentTime = Date()
        let parent = RUMContextProviderMock()
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 50, startTime: currentTime)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by less than the session timeout duration:
        currentTime.addTimeInterval(0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by the session timeout duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)))
    }

    func testItManagesViewScopeLifecycle() {
        let parent = RUMContextProviderMock()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date())
        XCTAssertEqual(scope.viewScopes.count, 0)
        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        XCTAssertEqual(scope.viewScopes.count, 1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        XCTAssertEqual(scope.viewScopes.count, 0)

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        XCTAssertEqual(scope.viewScopes.count, 1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testWhenSessionIsSampled_itDoesNotCreateViewScopes() {
        let parent = RUMContextProviderMock()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 0, startTime: Date())
        XCTAssertEqual(scope.viewScopes.count, 0)
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView)),
            "Sampled session should be kept until it expires or reaches the timeout."
        )
        XCTAssertEqual(scope.viewScopes.count, 0)
    }
}
