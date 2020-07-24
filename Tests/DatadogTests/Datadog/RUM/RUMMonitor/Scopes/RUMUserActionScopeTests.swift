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
    private let parent = RUMScopeMock(
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

    // MARK: - Continuous User Action

    func testWhenContinuousUserActionEnds_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
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
                    actionType: .swipe
                )
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMActionEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertEqual(event.model.view.id, parent.context.activeViewID?.toString)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.action.id, scope.actionUUID.toString)
        XCTAssertEqual(event.model.action.type, "swipe")
        XCTAssertEqual(event.model.action.loadingTime, 1_000_000_000)
        XCTAssertEqual(event.model.action.resource?.count, 0)
        XCTAssertEqual(event.model.action.error?.count, 0)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }

    func testWhenContinuousUserActionExpires_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            actionType: .swipe,
            attributes: [:],
            startTime: currentTime,
            isContinuous: true
        )

        let expirationInterval = RUMUserActionScope.Constants.continuousActionMaxDuration

        currentTime = .mockDecember15th2019At10AMUTC(addingTimeInterval: expirationInterval * 0.5)
        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)), "Continuous User Action should not expire after \(expirationInterval * 0.5)s")

        currentTime = .mockDecember15th2019At10AMUTC(addingTimeInterval: expirationInterval)
        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)), "Continuous User Action should expire after \(expirationInterval)s")

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMActionEvent>.self).first)
        XCTAssertEqual(event.model.action.loadingTime, 10_000_000_000)
    }

    func testWhileContinuousUserActionIsActive_itTracksCompletedResources() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            actionType: .scroll,
            attributes: [:],
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand(resourceName: "/resource/1", time: currentTime, attributes: [:], url: .mockAny(), httpMethod: .mockAny())
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand(resourceName: "/resource/2", time: currentTime, attributes: [:], url: .mockAny(), httpMethod: .mockAny())
            )
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand(resourceName: "/resource/1", time: currentTime, attributes: [:], type: .mockAny(), httpStatusCode: 200, size: 0)
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand(resourceName: "/resource/2", time: currentTime, attributes: [:], errorMessage: .mockAny(), errorSource: .mockAny(), httpStatusCode: 400)
            )
        )

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand(time: currentTime, attributes: [:], actionType: .scroll)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMActionEvent>.self).last)
        XCTAssertEqual(event.model.action.resource?.count, 2)
        XCTAssertEqual(event.model.action.error?.count, 1)
    }

    // MARK: - Discrete User Action

    func testWhenDiscreteUserActionTimesOut_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
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

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMActionEvent>.self).first)
        let nanosecondsInSecond: Double = 1_000_000_000
        let actionLoadingTimeInSeconds = Double(try XCTUnwrap(event.model.action.loadingTime)) / nanosecondsInSecond
        XCTAssertEqual(actionLoadingTimeInSeconds, RUMUserActionScope.Constants.discreteActionTimeoutDuration, accuracy: 0.1)
    }

    func testWhileDiscreteUserActionIsActive_itDoesNotComplete_untilAllTrackedResourcesAreCompleted() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope(
            parent: parent,
            dependencies: dependencies,
            actionType: .scroll,
            attributes: [:],
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(0.05)

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand(resourceName: "/resource/1", time: currentTime, attributes: [:], url: .mockAny(), httpMethod: .mockAny())
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand(resourceName: "/resource/2", time: currentTime, attributes: [:], url: .mockAny(), httpMethod: .mockAny())
            )
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand(resourceName: "/resource/1", time: currentTime, attributes: [:], type: .mockAny(), httpStatusCode: 200, size: 0)
            ),
            "Discrete User Action should not yet complete as it still has 1 pending Resource"
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand(resourceName: "/resource/2", time: currentTime, attributes: [:], errorMessage: .mockAny(), errorSource: .mockAny(), httpStatusCode: 400)
            ),
            "Discrete User Action should not yet complete as it haven't reached the time out duration"
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(command: RUMCommandMock(time: currentTime)),
            "Discrete User Action should complete as it has no more pending Resources and it reached the timeout duration"
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMActionEvent>.self).last)
        XCTAssertEqual(event.model.action.resource?.count, 2)
        XCTAssertEqual(event.model.action.error?.count, 1)
    }
}
