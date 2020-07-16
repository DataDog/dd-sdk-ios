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
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny())

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, RUMApplicationScope.Constants.nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewURI)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenFirstViewIsStarted_itStartsNewSession() {
        let parent: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny())

        XCTAssertFalse(scope.process(command: .startView(id: UIViewController(), attributes: nil)))

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertNotEqual(scope.context.sessionID, RUMApplicationScope.Constants.nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewURI)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenSessionExceedsMaxDuration_itStartsNewSession() {
        let dateProvider = RelativeDateProvider()
        let parent: RUMApplicationScope = .mockAny()
        let scope = RUMSessionScope(
            parent: parent,
            dependencies: .mockWith(dateProvider: dateProvider)
        )

        XCTAssertFalse(scope.process(command: .startView(id: UIViewController(), attributes: nil)))
        let firstSessionID = scope.context.sessionID
        XCTAssertFalse(parent.process(command: .stopView(id: UIViewController(), attributes: nil)))
        XCTAssertFalse(scope.process(command: .startView(id: UIViewController(), attributes: nil)))
        XCTAssertEqual(scope.context.sessionID, firstSessionID, "It should keep the same session")

        // Push time forward by the max session duration:
        dateProvider.advance(bySeconds: RUMSessionScope.Constants.sessionMaxDuration)

        XCTAssertFalse(scope.process(command: .stopView(id: UIViewController(), attributes: nil)))
        XCTAssertNotEqual(scope.context.sessionID, firstSessionID, "It should start new session")
    }

    func testWhenSessionIsInactiveForCertainDuration_itStartsNewSession() {
        let dateProvider = RelativeDateProvider()
        let parent: RUMApplicationScope = .mockAny()
        let scope = RUMSessionScope(
            parent: parent,
            dependencies: .mockWith(dateProvider: dateProvider)
        )

        XCTAssertFalse(scope.process(command: .startView(id: UIViewController(), attributes: nil)))
        let firstSessionID = scope.context.sessionID

        // Push time forward by less than the session timeout duration:
        dateProvider.advance(bySeconds: 0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)
        XCTAssertFalse(scope.process(command: .addUserAction(userAction: .tap, attributes: nil)))
        XCTAssertEqual(scope.context.sessionID, firstSessionID, "It should keep the same session")

        // Push time forward by the session timeout duration:
        dateProvider.advance(bySeconds: RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertFalse(scope.process(command: .stopView(id: UIViewController(), attributes: nil)))
        XCTAssertNotEqual(scope.context.sessionID, firstSessionID, "It should start new session")
    }
}
