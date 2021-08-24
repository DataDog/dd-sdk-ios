/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

class RUMViewScopeTests: XCTestCase {
    private let output = RUMEventOutputMock()
    private let parent = RUMContextProviderMock()
    private lazy var dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

    func testDefaultContext() {
        let applicationScope: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let sessionScope: RUMSessionScope = .mockWith(parent: applicationScope)
        let scope = RUMViewScope(
            parent: sessionScope,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockRandom(),
            name: .mockRandom(),
            attributes: [:],
            customTimings: [:],
            startTime: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, sessionScope.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, scope.viewUUID)
        XCTAssertEqual(scope.context.activeViewPath, scope.viewPath)
        XCTAssertEqual(scope.context.activeViewName, scope.viewName)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenViewHasAnActiveUserAction() {
        let applicationScope: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let sessionScope: RUMSessionScope = .mockWith(parent: applicationScope)
        let scope = RUMViewScope(
            parent: sessionScope,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockRandom(),
            name: .mockRandom(),
            attributes: [:],
            customTimings: [:],
            startTime: .mockAny()
        )

        _ = scope.process(command: RUMStartUserActionCommand.mockAny())

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, sessionScope.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, scope.viewUUID)
        XCTAssertEqual(scope.context.activeViewPath, scope.viewPath)
        XCTAssertEqual(scope.context.activeViewName, scope.viewName)
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(scope.userActionScope?.actionUUID))
    }

    func testWhenInitialViewIsStarted_itSendsApplicationStartAction() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: .mockWith(
                launchTimeProvider: LaunchTimeProviderMock(launchTime: 2), // 2 seconds
                eventOutput: output
            ),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: mockView, isInitialView: true)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMActionEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "UIViewController")
        XCTAssertEqual(event.model.view.name, "ViewName")
        XCTAssertValidRumUUID(event.model.action.id)
        XCTAssertEqual(event.model.action.type, .applicationStart)
        XCTAssertEqual(event.model.action.loadingTime, 2_000_000_000) // 2e+9 ns
        XCTAssertEqual(event.model.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
    }

    func testWhenInitialViewIsStarted_itSendsViewUpdateEvent() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: mockView, isInitialView: true)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "UIViewController")
        XCTAssertEqual(event.model.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.model.view.isActive)
        XCTAssertTrue(viewIsActive)
        XCTAssertEqual(event.model.view.timeSpent, 0)
        XCTAssertEqual(event.model.view.action.count, 1, "The initial view udate must have come with `application_start` action sent.")
        XCTAssertEqual(event.model.view.error.count, 0)
        XCTAssertEqual(event.model.view.resource.count, 0)
        XCTAssertEqual(event.model.dd.documentVersion, 1)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.model.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
    }

    func testWhenViewIsStarted_itSendsViewUpdateEvent() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: ["foo": "bar", "fizz": "buzz"],
            customTimings: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar 2"], identity: mockView)
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "UIViewController")
        XCTAssertEqual(event.model.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.model.view.isActive)
        XCTAssertTrue(viewIsActive)
        XCTAssertEqual(event.model.view.timeSpent, 0)
        XCTAssertEqual(event.model.view.action.count, 0)
        XCTAssertEqual(event.model.view.error.count, 0)
        XCTAssertEqual(event.model.view.resource.count, 0)
        XCTAssertEqual(event.model.dd.documentVersion, 1)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar 2", "fizz": "buzz"])
    }

    func testWhenViewIsStopped_itSendsViewUpdateEvent_andEndsTheScope() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView))
        )
        currentTime.addTimeInterval(2)
        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand.mockWith(time: currentTime, identity: mockView)),
            "The scope should end."
        )

        let viewEvents = try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self)
        XCTAssertEqual(viewEvents.count, 2)
        viewEvents.forEach { viewEvent in
            XCTAssertEqual(
                viewEvent.model.date,
                Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds,
                "All View events must share the same creation date"
            )
        }

        let event = try XCTUnwrap(viewEvents.dropFirst().first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.model.session.type, .user)
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "UIViewController")
        XCTAssertEqual(event.model.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.model.view.isActive)
        XCTAssertFalse(viewIsActive)
        XCTAssertEqual(event.model.view.timeSpent, TimeInterval(2).toInt64Nanoseconds)
        XCTAssertEqual(event.model.view.action.count, 0)
        XCTAssertEqual(event.model.view.error.count, 0)
        XCTAssertEqual(event.model.view.resource.count, 0)
        XCTAssertEqual(event.model.dd.documentVersion, 2)
        XCTAssertTrue(event.attributes.isEmpty)
    }

    func testWhenAnotherViewIsStarted_itEndsTheScope() throws {
        let view1 = createMockView(viewControllerClassName: "FirstViewController")
        let view2 = createMockView(viewControllerClassName: "SecondViewController")
        var currentTime = Date()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: view1,
            path: "FirstViewController",
            name: "FirstViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
             scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: view1))
         )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: view2)),
            "The scope should end as another View is started."
        )

        let viewEvents = try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self)
        XCTAssertEqual(viewEvents.count, 2)
        let view1WasActive = try XCTUnwrap(viewEvents[0].model.view.isActive)
        XCTAssertTrue(view1WasActive)
        XCTAssertEqual(viewEvents[1].model.view.url, "FirstViewController")
        XCTAssertEqual(viewEvents[1].model.view.name, "FirstViewName")
        let view2IsActive = try XCTUnwrap(viewEvents[1].model.view.isActive)
        XCTAssertFalse(view2IsActive)
        XCTAssertEqual(viewEvents[1].model.view.timeSpent, TimeInterval(1).toInt64Nanoseconds, "The View should last for 1 second")
    }

    func testWhenTheViewIsStartedAnotherTime_itEndsTheScope() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "FirstViewController",
            name: "FirstViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView)),
            "The scope should be kept as the View was started for the first time."
        )
        XCTAssertFalse(
            scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView)),
            "The scope should end as the View was started for another time."
        )

        let viewEvents = try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self)
        XCTAssertEqual(viewEvents.count, 2)
        let viewWasActive = try XCTUnwrap(viewEvents[0].model.view.isActive)
        XCTAssertTrue(viewWasActive)
        XCTAssertEqual(viewEvents[0].model.view.url, "FirstViewController")
        XCTAssertEqual(viewEvents[0].model.view.name, "FirstViewName")
        let viewIsActive = try XCTUnwrap(viewEvents[1].model.view.isActive)
        XCTAssertFalse(viewIsActive)
        XCTAssertEqual(viewEvents[0].model.view.timeSpent, TimeInterval(1).toInt64Nanoseconds, "The View should last for 1 second")
    }

    func testGivenMultipleViewScopes_whenSendingViewEvent_eachScopeUsesUniqueViewID() throws {
        func createScope(uri: String, name: String) -> RUMViewScope {
            RUMViewScope(
                parent: parent,
                dependencies: dependencies,
                identity: mockView,
                path: uri,
                name: name,
                attributes: [:],
                customTimings: [:],
                startTime: .mockAny()
            )
        }

        // Given
        let scope1 = createScope(uri: "View1URL", name: "View1Name")
        let scope2 = createScope(uri: "View2URL", name: "View2Name")

        // When
        [scope1, scope2].forEach { scope in
            _ = scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
            _ = scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        }

        // Then
        let viewEvents = try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self)
        let view1Events = viewEvents.filter { $0.model.view.url == "View1URL" && $0.model.view.name == "View1Name" }
        let view2Events = viewEvents.filter { $0.model.view.url == "View2URL" && $0.model.view.name == "View2Name" }
        XCTAssertEqual(view1Events.count, 2)
        XCTAssertEqual(view2Events.count, 2)
        XCTAssertEqual(view1Events[0].model.view.id, view1Events[1].model.view.id)
        XCTAssertEqual(view2Events[0].model.view.id, view2Events[1].model.view.id)
        XCTAssertNotEqual(view1Events[0].model.view.id, view2Events[0].model.view.id)
    }

    // MARK: - Resources Tracking

    func testItManagesResourceScopesLifecycle() throws {
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: Date()
        )
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        )

        XCTAssertEqual(scope.resourceScopes.count, 0)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1")
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 1)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2")
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 2)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1")
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 1)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2")
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 0)

        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        )
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(event.model.view.resource.count, 1, "View should record 1 successfull Resource")
        XCTAssertEqual(event.model.view.error.count, 1, "View should record 1 error due to second Resource failure")
    }

    func testGivenViewWithPendingResources_whenItGetsStopped_itDoesNotFinishUntilResourcesComplete() throws {
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: Date()
        )

        // given
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        )
        XCTAssertTrue(
            scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"))
        )
        XCTAssertTrue(
            scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"))
        )

        // when
        XCTAssertTrue(
            scope.process(command: RUMStopViewCommand.mockWith(identity: mockView)),
            "The View should be kept alive as its Resources havent yet finished loading"
        )

        // then
        XCTAssertTrue(
            scope.process(command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1")),
            "The View should be kept alive as all its Resources havent yet finished loading"
        )
        XCTAssertFalse(
            scope.process(command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2")),
            "The View should stop as all its Resources finished loading"
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(event.model.view.resource.count, 1, "View should record 1 successfull Resource")
        XCTAssertEqual(event.model.view.error.count, 1, "View should record 1 error due to second Resource failure")
    }

    // MARK: - User Action Tracking

    func testItManagesContinuousUserActionScopeLifecycle() throws {
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: Date()
        )

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        )

        XCTAssertNil(scope.userActionScope)
        let actionName = String.mockRandom()
        XCTAssertTrue(
            scope.process(command: RUMStartUserActionCommand.mockWith(actionType: .swipe, name: actionName))
        )
        XCTAssertNotNil(scope.userActionScope)
        XCTAssertEqual(scope.userActionScope?.name, actionName)

        let secondAction = RUMStartUserActionCommand.mockWith(actionType: .swipe, name: .mockRandom())
        XCTAssertTrue(
            scope.process(command: secondAction)
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should ignore the next (only non-custom) UA if one is pending.")
        XCTAssertEqual(
            logOutput.recordedLog?.message,
            """
            RUM Action '\(secondAction.actionType)' on '\(secondAction.name)' was dropped, because another action is still active for the same view.
            """
        )

        XCTAssertTrue(
            scope.process(command: RUMAddUserActionCommand.mockWith(actionType: .custom, name: .mockRandom()))
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should not change existing pending action when adding custom UA (but this custom action should be recorded anyway).")

        XCTAssertTrue(
            scope.process(command: RUMStopUserActionCommand.mockWith(actionType: .swipe))
        )
        XCTAssertNil(scope.userActionScope)

        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        )
        let viewEvent = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(viewEvent.model.view.action.count, 2, "View should record 2 actions: non-custom + instant custom")
    }

    func testItManagesDiscreteUserActionScopeLifecycle() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView))
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertNil(scope.userActionScope)
        let actionName = String.mockRandom()
        XCTAssertTrue(
            scope.process(command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap, name: actionName))
        )
        XCTAssertNotNil(scope.userActionScope)
        XCTAssertEqual(scope.userActionScope?.name, actionName)

        let secondAction = RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap, name: .mockRandom())
        XCTAssertTrue(
            scope.process(command: secondAction)
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should ignore the next (only non-custom) UA if one is pending.")
        XCTAssertEqual(
            logOutput.recordedLog?.message,
            """
            RUM Action '\(secondAction.actionType)' on '\(secondAction.name)' was dropped, because another action is still active for the same view.
            """
        )

        XCTAssertTrue(
            scope.process(command: RUMAddUserActionCommand.mockWith(actionType: .custom, name: .mockRandom()))
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should not change existing pending action when adding custom UA (but this custom action should be recorded anyway).")

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand.mockWith(time: currentTime, identity: mockView))
        )
        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(event.model.view.action.count, 2, "View should record 2 actions: non-custom + instant custom")
    }

    // MARK: - Error Tracking

    func testWhenViewErrorIsAdded_itSendsErrorEventAndViewUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: mockView, isInitialView: true)
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime, message: "view error", source: .source, stack: nil)
            )
        )

        let error = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self).last)
        XCTAssertEqual(error.model.date, Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1).timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(error.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(error.model.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(error.model.session.type, .user)
        XCTAssertValidRumUUID(error.model.view.id)
        XCTAssertEqual(error.model.view.url, "UIViewController")
        XCTAssertEqual(error.model.view.name, "ViewName")
        XCTAssertNil(error.model.usr)
        XCTAssertNil(error.model.connectivity)
        XCTAssertEqual(error.model.error.type, "abc")
        XCTAssertEqual(error.model.error.message, "view error")
        XCTAssertEqual(error.model.error.source, .source)
        XCTAssertNil(error.model.error.stack)
        XCTAssertNil(error.model.error.isCrash)
        XCTAssertNil(error.model.error.resource)
        XCTAssertNil(error.model.action)
        XCTAssertEqual(error.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(error.model.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")

        let viewUpdate = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(viewUpdate.model.view.error.count, 1)
    }

    func testWhenResourceIsFinishedWithError_itSendsViewUpdateEvent() throws {
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: Date()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(attributes: ["foo": "bar"], identity: mockView, isInitialView: true)
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1")
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorObject(resourceKey: "/resource/1")
            )
        )

        let viewUpdate = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(viewUpdate.model.view.resource.count, 0, "Failed Resource should not be counted")
        XCTAssertEqual(viewUpdate.model.view.error.count, 1, "Failed Resource should be counted as Error")
    }

    // MARK: - Custom Timings Tracking

    func testGivenActiveView_whenCustomTimingIsRegistered_itSendsViewUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        )

        // Given
        XCTAssertTrue(scope.isActiveView)
        XCTAssertEqual(scope.customTimings.count, 0)

        // When
        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns")
            )
        )
        XCTAssertEqual(scope.customTimings.count, 1)

        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-1000000000ns")
            )
        )
        XCTAssertEqual(scope.customTimings.count, 2)

        // Then
        let events = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self))

        XCTAssertEqual(events.count, 3, "There should be 3 View updates sent")
        XCTAssertEqual(events[0].model.view.customTimings, [:])
        XCTAssertEqual(
            events[1].model.view.customTimings,
            ["timing-after-500000000ns": 500_000_000]
        )
        XCTAssertEqual(
            events[2].model.view.customTimings,
            ["timing-after-500000000ns": 500_000_000, "timing-after-1000000000ns": 1_000_000_000]
        )
    }

    func testGivenInactiveView_whenCustomTimingIsRegistered_itDoesNotSendViewUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        )
        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        )

        // Given
        XCTAssertFalse(scope.isActiveView)

        // When
        currentTime.addTimeInterval(0.5)

        _ = scope.process(
            command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns")
        )

        // Then
        let lastEvent = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
        XCTAssertEqual(lastEvent.model.view.customTimings, [:])
    }

    func testGivenActiveView_whenCustomTimingIsRegistered_itSanitizesCustomTiming() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime
        )
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView))
        )

        // Given
        XCTAssertTrue(scope.isActiveView)
        XCTAssertEqual(scope.customTimings.count, 0)

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        // When
        currentTime.addTimeInterval(0.5)
        let originalTimingName = "timing1_.@$-()&+=Д"
        let sanitizedTimingName = "timing1_.@$-______"
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: originalTimingName)
            )
        )
        XCTAssertEqual(scope.customTimings.count, 1)

        // Then
        let events = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self))

        XCTAssertEqual(events.count, 2, "There should be 2 View updates sent")
        XCTAssertEqual(events[0].model.view.customTimings, [:])
        XCTAssertEqual(
            events[1].model.view.customTimings,
            [sanitizedTimingName: 500_000_000]
        )
        XCTAssertEqual(
            logOutput.recordedLog?.message,
            """
            Custom timing '\(originalTimingName)' was modified to '\(sanitizedTimingName)' to match Datadog constraints.
            """
        )
    }

    // MARK: - Dates Correction

    func testGivenViewStartedWithServerTimeDifference_whenDifferentEventsAreSend_itAppliesTheSameCorrectionToAll() throws {
        let initialDeviceTime: Date = .mockDecember15th2019At10AMUTC()
        let initialServerTimeOffset: TimeInterval = 120 // 2 minutes
        let dateCorrectorMock = DateCorrectorMock(correctionOffset: initialServerTimeOffset)

        var currentDeviceTime = initialDeviceTime

        // Given
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies.replacing(dateCorrector: dateCorrectorMock),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: initialDeviceTime
        )

        // When
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentDeviceTime, identity: mockView))

        dateCorrectorMock.correctionOffset = .random(in: -10...10) // randomize server time offset
        currentDeviceTime.addTimeInterval(1) // advance device time

        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1", time: currentDeviceTime)
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2", time: currentDeviceTime)
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1", time: currentDeviceTime)
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2", time: currentDeviceTime)
        )
        _ = scope.process(
            command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentDeviceTime)
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: currentDeviceTime)
        )

        _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentDeviceTime, identity: mockView))

        // Then
        let viewEvents = try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self)
        let resourceEvents = try output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self)
        let errorEvents = try output.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self)
        let actionEvents = try output.recordedEvents(ofType: RUMEvent<RUMActionEvent>.self)

        let initialRealTime = initialDeviceTime.addingTimeInterval(initialServerTimeOffset)
        let expectedViewEventsDate = initialRealTime.timeIntervalSince1970.toInt64Milliseconds
        let expectedOtherEventsDate = initialRealTime.addingTimeInterval(1).timeIntervalSince1970.toInt64Milliseconds

        viewEvents.forEach { view in
            XCTAssertEqual(view.model.date, expectedViewEventsDate)
        }
        resourceEvents.forEach { view in
            XCTAssertEqual(view.model.date, expectedOtherEventsDate)
        }
        errorEvents.forEach { view in
            XCTAssertEqual(view.model.date, expectedOtherEventsDate)
        }
        actionEvents.forEach { view in
            XCTAssertEqual(view.model.date, expectedOtherEventsDate)
        }
    }

    // MARK: ViewScope counts Correction

    func testGivenViewScopeWithDependentActionsResourcesErrors_whenDroppingEvents_thenCountsAreAdjusted() throws {
        struct ResourceMapperHolder {
            var resourceEventMapper: RUMResourceEventMapper?
        }
        var resourceMapperHolder = ResourceMapperHolder()

        // Given an eventBuilder using an eventsMapper that:
        // - discards `RUMActionEvent` for `RUMAddUserActionCommand`
        // - discards `RUMErrorEvent` for `RUMAddCurrentViewErrorCommand`
        // - discards `RUMResourceEvent` from `RUMStartResourceCommand` /resource/1
        let eventBuilder = RUMEventBuilder(
            userInfoProvider: UserInfoProvider.mockAny(),
            eventsMapper: RUMEventsMapper.mockWith(
                errorEventMapper: { event in
                    nil
                },
                resourceEventMapper: {
                    resourceMapperHolder.resourceEventMapper?($0)
                },
                actionEventMapper: { event in
                    event.action.type == .applicationStart ? event : nil
                }
            )
        )
        let dependencies: RUMScopeDependencies = .mockWith(eventBuilder: eventBuilder, eventOutput: output)

        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "UIViewController",
            name: "ViewController",
            attributes: [:],
            customTimings: [:],
            startTime: Date()
        )
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView, isInitialView: true))
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1")
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockAny()
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage()
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2")
            )
        )

        XCTAssertEqual(scope.resourceScopes.count, 2)

        let resourceScope1 = try XCTUnwrap(scope.resourceScopes["/resource/1"])
        let resourceID1 = resourceScope1.resourceUUID.toRUMDataFormat

        resourceMapperHolder.resourceEventMapper = { event in
            return event.resource.id == resourceID1 ? nil : event
        }

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/2")
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1")
            )
        )

        XCTAssertEqual(scope.resourceScopes.count, 0)

        XCTAssertFalse(
            scope.process(command: RUMStopViewCommand.mockWith(identity: mockView))
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)

        // Then
        XCTAssertEqual(event.model.view.resource.count, 1, "After dropping 1 Resource event (out of 2), View should record 1 Resource")
        XCTAssertEqual(event.model.view.action.count, 1, "After dropping a User Action event, View should record only ApplicationStart Action")
        XCTAssertEqual(event.model.view.error.count, 0, "After dropping an Error event, View should record 0 Errors")
        XCTAssertEqual(event.model.dd.documentVersion, 3, "After starting the application, stopping the view, starting/stopping one resource out of 2, discarding a user action and an error, the View scope should have sent 3 View events.")
    }

    func testGivenViewScopeWithDroppingEventsMapper_whenProcessingApplicationStartAction_thenNoEventIsSent() throws {
        let eventBuilder = RUMEventBuilder(
            userInfoProvider: UserInfoProvider.mockAny(),
            eventsMapper: RUMEventsMapper.mockWith(
                actionEventMapper: { event in
                    nil
                }
            )
        )
        let dependencies: RUMScopeDependencies = .mockWith(eventBuilder: eventBuilder, eventOutput: output)

        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "UIViewController",
            name: "ViewController",
            attributes: [:],
            customTimings: [:],
            startTime: Date()
        )
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView, isInitialView: true))
        )

        XCTAssertNil(try output.recordedEvents(ofType: RUMEvent<RUMViewEvent>.self).last)
    }
}
