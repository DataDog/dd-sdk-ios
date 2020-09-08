/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMUserActionScopeTests: XCTestCase {
    private let output = RUMEventOutputMock()
    private lazy var dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)
    private let parent = RUMContextProviderMock(
        context: .mockWith(
            rumApplicationID: "rum-123",
            sessionID: .mockRandom(),
            activeViewID: .mockRandom(),
            activeViewURI: "FooViewController",
            activeUserActionID: .mockRandom()
        )
    )

    func testDefaultContext() {
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .swipe,
            attributes: [:],
            startTime: .mockAny(),
            isContinuous: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, parent.context.rumApplicationID)
        XCTAssertEqual(scope.context.sessionID, parent.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, try XCTUnwrap(parent.context.activeViewID))
        XCTAssertEqual(scope.context.activeViewURI, try XCTUnwrap(parent.context.activeViewURI))
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(parent.context.activeUserActionID))
    }

    func testGivenActiveUserAction_whenViewIsStopped_itSendsUserActionEvent() throws {
        let scope = RUMViewScope.mockWith(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            attributes: [:],
            startTime: Date()
        )
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(identity: mockView)))
        let mockUserActionCmd = RUMAddUserActionCommand.mockAny()
        XCTAssertTrue(scope.process(command: mockUserActionCmd))
        XCTAssertFalse(scope.process(command: RUMStopViewCommand.mockWith(identity: mockView)))

        let recordedActionEvents = try output.recordedEvents(ofType: RUMEvent<RUMAction>.self)
        XCTAssertEqual(recordedActionEvents.count, 1)
        let recordedAction = try XCTUnwrap(recordedActionEvents.last)
        XCTAssertEqual(recordedAction.model.action.type.rawValue, String(describing: mockUserActionCmd.actionType))
    }

    // MARK: - Continuous User Action

    func testWhenContinuousUserActionEnds_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .swipe,
            attributes: [:],
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand(
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    actionType: .swipe,
                    name: nil
                )
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMAction>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertEqual(event.model.view.id, parent.context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.action.id, scope.actionUUID.toRUMDataFormat)
        XCTAssertEqual(event.model.action.type, .swipe)
        XCTAssertEqual(event.model.action.loadingTime, 1_000_000_000)
        XCTAssertEqual(event.model.action.resource?.count, 0)
        XCTAssertEqual(event.model.action.error?.count, 0)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
    }

    func testWhenContinuousUserActionExpires_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .swipe,
            attributes: [:],
            startTime: currentTime,
            isContinuous: true
        )

        let expirationInterval = RUMUserActionScope.Constants.continuousActionMaxDuration

        currentTime = .mockDecember15th2019At10AMUTC(addingTimeInterval: expirationInterval * 0.5)
        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)), "Continuous User Action should not expire after \(expirationInterval * 0.5)s")

        currentTime = .mockDecember15th2019At10AMUTC(addingTimeInterval: expirationInterval * 2.0)
        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)), "Continuous User Action should expire after \(expirationInterval)s")

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMAction>.self).first)
        XCTAssertEqual(event.model.action.loadingTime, 10_000_000_000, "Loading time should not exceed expirationInterval")
    }

    func testWhileContinuousUserActionIsActive_itTracksCompletedResources() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .scroll,
            attributes: [:],
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceName: "/resource/1", time: currentTime)
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceName: "/resource/2", time: currentTime)
            )
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceName: "/resource/1", time: currentTime)
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorObject(resourceName: "/resource/2", time: currentTime)
            )
        )

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand.mockWith(time: currentTime, actionType: .scroll)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMAction>.self).last)
        XCTAssertEqual(event.model.action.resource?.count, 1, "User Action should track first succesfull Resource")
        XCTAssertEqual(event.model.action.error?.count, 1, "User Action should track second Resource failure as Error")
    }

    func testWhileContinuousUserActionIsActive_itCountsViewErrors() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .scroll,
            attributes: [:],
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime)
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand.mockWith(time: currentTime, actionType: .scroll)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMAction>.self).last)
        XCTAssertEqual(event.model.action.error?.count, 1)
    }

    func testWhenContinuousUserActionStopsWithName_itChangesItsName() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .scroll,
            attributes: [:],
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(scope.process(command: RUMCommandMock()))

        currentTime.addTimeInterval(1)
        let differentName = String.mockRandom()
        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand.mockWith(time: currentTime, actionType: .scroll, name: differentName)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMAction>.self).last)
        XCTAssertEqual(event.model.action.target?.name, differentName)
    }

    // MARK: - Discrete User Action

    func testWhenDiscreteUserActionTimesOut_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .swipe,
            attributes: [:],
            startTime: currentTime,
            isContinuous: false
        )

        let timeOutInterval = RUMUserActionScope.Constants.discreteActionTimeoutDuration

        currentTime = .mockDecember15th2019At10AMUTC(addingTimeInterval: timeOutInterval * 0.5)
        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)), "Discrete User Action should not time out after \(timeOutInterval * 0.5)s")

        currentTime.addTimeInterval(timeOutInterval)
        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)), "Discrete User Action should time out after \(timeOutInterval)s")

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMAction>.self).first)
        let nanosecondsInSecond: Double = 1_000_000_000
        let actionLoadingTimeInSeconds = Double(try XCTUnwrap(event.model.action.loadingTime)) / nanosecondsInSecond
        XCTAssertEqual(actionLoadingTimeInSeconds, RUMUserActionScope.Constants.discreteActionTimeoutDuration, accuracy: 0.1)
    }

    func testWhileDiscreteUserActionIsActive_itDoesNotComplete_untilAllTrackedResourcesAreCompleted() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .scroll,
            attributes: [:],
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(0.05)

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceName: "/resource/1", time: currentTime)
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceName: "/resource/2", time: currentTime)
            )
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceName: "/resource/1", time: currentTime)
            ),
            "Discrete User Action should not yet complete as it still has 1 pending Resource"
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorObject(resourceName: "/resource/2", time: currentTime)
            ),
            "Discrete User Action should not yet complete as it haven't reached the time out duration"
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(command: RUMCommandMock(time: currentTime)),
            "Discrete User Action should complete as it has no more pending Resources and it reached the timeout duration"
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMAction>.self).last)
        XCTAssertEqual(event.model.action.resource?.count, 1, "User Action should track first succesfull Resource")
        XCTAssertEqual(event.model.action.error?.count, 1, "User Action should track second Resource failure as Error")
    }

    func testWhileDiscreteUserActionIsActive_itCountsViewErrors() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            name: .mockAny(),
            actionType: .scroll,
            attributes: [:],
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(0.05)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime)
            )
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(command: RUMCommandMock(time: currentTime)),
            "Discrete User Action should complete as it reached the timeout duration"
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMAction>.self).last)
        XCTAssertEqual(event.model.action.error?.count, 1)
    }
}
