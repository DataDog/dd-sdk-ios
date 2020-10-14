/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension RUMContext: EquatableInTests {}

class RUMCurrentContextTests: XCTestCase {
    private let queue = DispatchQueue(label: "\(#file)")

    func testContextAfterInitializingTheApplication() {
        let applicationScope = RUMApplicationScope(rumApplicationID: "rum-123", dependencies: .mockAny(), samplingRate: .mockAny())
        let provider = RUMCurrentContext(applicationScope: applicationScope, queue: queue)

        XCTAssertEqual(
            provider.context,
            RUMContext(
                rumApplicationID: "rum-123",
                sessionID: RUMUUID.nullUUID,
                activeViewID: nil,
                activeViewURI: nil,
                activeUserActionID: nil
            )
        )
    }

    func testContextAfterStartingView() throws {
        let applicationScope = RUMApplicationScope(rumApplicationID: "rum-123", dependencies: .mockAny(), samplingRate: 100)
        let provider = RUMCurrentContext(applicationScope: applicationScope, queue: queue)

        _ = applicationScope.process(command: RUMStartViewCommand.mockWith(identity: mockView))

        try XCTAssertEqual(
            provider.context,
            RUMContext(
                rumApplicationID: "rum-123",
                sessionID: XCTUnwrap(applicationScope.sessionScope?.sessionUUID),
                activeViewID: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.viewUUID),
                activeViewURI: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.viewURI),
                activeUserActionID: nil
            )
        )
    }

    func testContextWhilePendingUserAction() throws {
        let applicationScope = RUMApplicationScope(rumApplicationID: "rum-123", dependencies: .mockAny(), samplingRate: 100)
        let provider = RUMCurrentContext(applicationScope: applicationScope, queue: queue)

        _ = applicationScope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        _ = applicationScope.process(command: RUMAddUserActionCommand.mockWith(actionType: .tap))

        try XCTAssertEqual(
            provider.context,
            RUMContext(
                rumApplicationID: "rum-123",
                sessionID: XCTUnwrap(applicationScope.sessionScope?.sessionUUID),
                activeViewID: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.viewUUID),
                activeViewURI: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.viewURI),
                activeUserActionID: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.userActionScope?.actionUUID)
            )
        )
    }

    func testContextChangeWhenNavigatingBetweenViews() throws {
        let applicationScope = RUMApplicationScope(rumApplicationID: "rum-123", dependencies: .mockAny(), samplingRate: 100)
        let provider = RUMCurrentContext(applicationScope: applicationScope, queue: queue)

        let firstView = createMockViewInWindow()
        _ = applicationScope.process(command: RUMStartViewCommand.mockWith(identity: firstView))
        let firstContext = provider.context

        let secondView = createMockViewInWindow()
        _ = applicationScope.process(command: RUMStartViewCommand.mockWith(identity: secondView))
        let secondContext = provider.context

        XCTAssertNotEqual(firstContext, secondContext)

        try XCTAssertEqual(
            provider.context,
            RUMContext(
                rumApplicationID: "rum-123",
                sessionID: XCTUnwrap(applicationScope.sessionScope?.sessionUUID),
                activeViewID: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.viewUUID),
                activeViewURI: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.viewURI),
                activeUserActionID: nil
            )
        )
    }

    func testContextChangeWhenSessionIsRenewed() throws {
        var currentTime = Date()
        let applicationScope = RUMApplicationScope(rumApplicationID: "rum-123", dependencies: .mockAny(), samplingRate: 100)
        let provider = RUMCurrentContext(applicationScope: applicationScope, queue: queue)

        let view = createMockViewInWindow()
        _ = applicationScope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: view))
        let firstContext = provider.context

        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)

        _ = applicationScope.process(command: RUMCommandMock(time: currentTime))
        let secondContext = provider.context

        XCTAssertNotEqual(firstContext.sessionID, secondContext.sessionID)
        XCTAssertNotEqual(
            firstContext.activeViewID,
            secondContext.activeViewID,
            "A new View should be started on session renewal."
        )
        XCTAssertEqual(
            firstContext.activeViewURI,
            secondContext.activeViewURI,
            "The View URI should be the same as in previous session."
        )

        try XCTAssertEqual(
            provider.context,
            RUMContext(
                rumApplicationID: "rum-123",
                sessionID: XCTUnwrap(applicationScope.sessionScope?.sessionUUID),
                activeViewID: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.viewUUID),
                activeViewURI: XCTUnwrap(applicationScope.sessionScope?.viewScopes.last?.viewURI),
                activeUserActionID: nil
            )
        )
    }

    func testContextWhenSessionIsSampled() throws {
        let applicationScope = RUMApplicationScope(rumApplicationID: "rum-123", dependencies: .mockAny(), samplingRate: 0)
        let provider = RUMCurrentContext(applicationScope: applicationScope, queue: queue)

        _ = applicationScope.process(command: RUMStartViewCommand.mockWith(identity: mockView))

        XCTAssertEqual(
            provider.context,
            RUMContext(
                rumApplicationID: "rum-123",
                sessionID: .nullUUID,
                activeViewID: nil,
                activeViewURI: nil,
                activeUserActionID: nil
            )
        )
    }
}
