/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

private class ViewControllerMock: UIViewController {}

class RUMViewScopeTests: XCTestCase {
    private let output = RUMEventOutputMock()
    private let view = ViewControllerMock()
    private let parent = RUMScopeMock()
    private lazy var dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

    func testDefaultContext() {
        let applicationScope: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let sessionScope: RUMSessionScope = .mockWith(parent: applicationScope)
        let scope = RUMViewScope(
            parent: sessionScope,
            dependencies: .mockAny(),
            identity: view,
            attributes: [:],
            startTime: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, sessionScope.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, scope.viewUUID)
        XCTAssertEqual(scope.context.activeViewURI, scope.viewURI)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenViewHasAnActiveUserAction() {
        let applicationScope: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let sessionScope: RUMSessionScope = .mockWith(parent: applicationScope)
        let scope = RUMViewScope(
            parent: sessionScope,
            dependencies: .mockAny(),
            identity: view,
            attributes: [:],
            startTime: .mockAny()
        )

        _ = scope.process(
            command: RUMStartUserActionCommand(time: Date(), attributes: [:], actionType: .swipe)
        )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, sessionScope.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, scope.viewUUID)
        XCTAssertEqual(scope.context.activeViewURI, scope.viewURI)
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(scope.userActionScope?.actionUUID))
    }

    func testWhenInitialViewIsStarted_itSendsApplicationStartAction() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: view,
            attributes: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand(time: currentTime, attributes: ["foo": "bar"], identity: view, isInitialView: true)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMActionEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "ViewControllerMock")
        XCTAssertValidRumUUID(event.model.action.id)
        XCTAssertEqual(event.model.action.type, "application_start")
        XCTAssertTrue(event.attributes.isEmpty, "The `application_start` event must have no attributes.")
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }

    func testWhenInitialViewIsStarted_itSendsViewUpdateEvent() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: view,
            attributes: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand(time: currentTime, attributes: ["foo": "bar"], identity: view, isInitialView: true)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "ViewControllerMock")
        XCTAssertEqual(event.model.view.timeSpent, 0)
        XCTAssertEqual(event.model.view.action.count, 1, "The initial view udate must have come with `applicat_start` action sent.")
        XCTAssertEqual(event.model.view.error.count, 0)
        XCTAssertEqual(event.model.view.resource.count, 0)
        XCTAssertEqual(event.model.dd.documentVersion, 1)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }

    func testWhenViewIsStarted_itSendsViewUpdateEvent() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: view,
            attributes: ["foo": "bar", "fizz": "buzz"],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand(time: currentTime, attributes: ["foo": "bar 2"], identity: view)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "ViewControllerMock")
        XCTAssertEqual(event.model.view.timeSpent, 0)
        XCTAssertEqual(event.model.view.action.count, 0)
        XCTAssertEqual(event.model.view.error.count, 0)
        XCTAssertEqual(event.model.view.resource.count, 0)
        XCTAssertEqual(event.model.dd.documentVersion, 1)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar 2", "fizz": "buzz"])
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }

    func testWhenViewIsStopped_itSendsViewUpdateEvent_andEndsTheScope() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: view,
            attributes: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand(time: currentTime, attributes: [:], identity: view))
        )
        currentTime.addTimeInterval(2)
        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand(time: currentTime, attributes: [:], identity: view)),
            "The scope should end."
        )

        let viewEvents = try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self)
        XCTAssertEqual(viewEvents.count, 2)
        viewEvents.forEach { viewEvent in
            XCTAssertEqual(
                viewEvent.model.date,
                Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toMilliseconds,
                "All View events must share the same creation date"
            )
        }

        let event = try XCTUnwrap(viewEvents.dropFirst().first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "ViewControllerMock")
        XCTAssertEqual(event.model.view.timeSpent, TimeInterval(2).toNanoseconds)
        XCTAssertEqual(event.model.view.action.count, 0)
        XCTAssertEqual(event.model.view.error.count, 0)
        XCTAssertEqual(event.model.view.resource.count, 0)
        XCTAssertEqual(event.model.dd.documentVersion, 2)
        XCTAssertTrue(event.attributes.isEmpty)
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }

    // MARK: - Resources Tracking

    func testItManagesResourceScopesLifecycle() throws {
        let scope = RUMViewScope(parent: parent, dependencies: dependencies, identity: view, attributes: [:], startTime: Date())
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand(time: Date(), attributes: [:], identity: view))
        )

        XCTAssertEqual(scope.resourceScopes.count, 0)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand(resourceName: "/resource/1", time: Date(), attributes: [:], url: .mockAny(), httpMethod: .mockAny())
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 1)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand(resourceName: "/resource/2", time: Date(), attributes: [:], url: .mockAny(), httpMethod: .mockAny())
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 2)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand(resourceName: "/resource/1", time: Date(), attributes: [:], type: .mockAny(), httpStatusCode: 200, size: 0)
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 1)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand(resourceName: "/resource/2", time: Date(), attributes: [:], errorMessage: .mockAny(), errorSource: .mockAny(), httpStatusCode: 400)
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 0)

        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand(time: Date(), attributes: [:], identity: view))
        )
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(event.model.view.resource.count, 2, "View should record 2 resources")
    }

    // MARK: - User Action Tracking

    func testItManagesContinuousUserActionScopeLifecycle() throws {
        let scope = RUMViewScope(parent: parent, dependencies: dependencies, identity: view, attributes: [:], startTime: Date())
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand(time: Date(), attributes: [:], identity: view))
        )

        XCTAssertNil(scope.userActionScope)
        XCTAssertTrue(
            scope.process(command: RUMStartUserActionCommand(time: Date(), attributes: [:], actionType: .swipe))
        )
        XCTAssertNotNil(scope.userActionScope)
        XCTAssertTrue(
            scope.process(command: RUMStopUserActionCommand(time: Date(), attributes: [:], actionType: .swipe))
        )
        XCTAssertNil(scope.userActionScope)

        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand(time: Date(), attributes: [:], identity: view))
        )
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(event.model.view.action.count, 1, "View should record 1 action")
    }

    func testItManagesDiscreteUserActionScopeLifecycle() throws {
        var currentTime = Date()
        let scope = RUMViewScope(parent: parent, dependencies: dependencies, identity: view, attributes: [:], startTime: currentTime)
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand(time: currentTime, attributes: [:], identity: view))
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertNil(scope.userActionScope)
        XCTAssertTrue(
            scope.process(command: RUMAddUserActionCommand(time: currentTime, attributes: [:], actionType: .tap))
        )
        XCTAssertNotNil(scope.userActionScope)

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand(time: currentTime, attributes: [:], identity: view))
        )
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(event.model.view.action.count, 1, "View should record 1 action")
    }
}
