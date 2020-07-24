/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMApplicationScopeTests: XCTestCase {
    private let view = UIViewController()

    func testRootContext() {
        let scope = RUMApplicationScope(
            rumApplicationID: "abc-123",
            dependencies: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, "abc-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewURI)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenFirstViewIsStarted_itStartsNewSession() {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny())

        XCTAssertNil(scope.sessionScope)
        XCTAssertTrue(scope.process(command: RUMStartViewCommand(time: .mockAny(), attributes: [:], identity: view)))
        XCTAssertNotNil(scope.sessionScope)
    }

    func testWhenSessionExpires_itStartsANewOneAndTransfersActiveViews() throws {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny())
        var currentTime = Date()

        _ = scope.process(command: RUMStartViewCommand(time: currentTime, attributes: [:], identity: view))
        let firstSessionUUID = try XCTUnwrap(scope.sessionScope?.context.sessionID)
        let firstsSessionViewScopes = try XCTUnwrap(scope.sessionScope?.viewScopes)

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        _ = scope.process(command: RUMAddUserActionCommand(time: currentTime, attributes: [:], action: .tap))
        let secondSessionUUID = try XCTUnwrap(scope.sessionScope?.context.sessionID)
        let secondSessionViewScopes = try XCTUnwrap(scope.sessionScope?.viewScopes)

        XCTAssertNotEqual(firstSessionUUID, secondSessionUUID)
        XCTAssertEqual(firstsSessionViewScopes.count, secondSessionViewScopes.count)
        XCTAssertTrue(secondSessionViewScopes.first?.identity === view)
    }

    func testUntilSessionIsStarted_itIgnoresOtherCommands() {
        let scope = RUMApplicationScope(rumApplicationID: .mockAny(), dependencies: .mockAny())

        XCTAssertTrue(scope.process(command: RUMStopViewCommand(time: .mockAny(), attributes: [:], identity: view)))
        XCTAssertTrue(scope.process(command: RUMAddUserActionCommand(time: .mockAny(), attributes: [:], action: .tap)))
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand(
                    resourceName: .mockAny(), time: .mockAny(), attributes: [:], type: .mockAny(), httpStatusCode: 200, size: 0
                )
            )
        )
        XCTAssertNil(scope.sessionScope)
    }
}
