/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import TestUtilities
import DatadogInternal
@testable import Datadog

class RUMViewScopeTests: XCTestCase {
    let context: DatadogContext = .mockWith(
        service: "test-service",
        device: .mockWith(
            name: "device-name",
            osName: "device-os"
        ),
        networkConnectionInfo: nil,
        carrierInfo: nil
    )

    let writer = FileWriterMock()

    private let parent = RUMContextProviderMock()

    func testDefaultContext() {
        let applicationScope = RUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "rum-123")
        )

        let sessionScope: RUMSessionScope = .mockWith(parent: applicationScope)

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: sessionScope,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockRandom(),
            name: .mockRandom(),
            attributes: [:],
            customTimings: [:],
            startTime: .mockAny(),
            serverTimeOffset: .zero
        )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, sessionScope.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, scope.viewUUID)
        XCTAssertEqual(scope.context.activeViewPath, scope.viewPath)
        XCTAssertEqual(scope.context.activeViewName, scope.viewName)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenViewHasAnActiveUserAction() {
        let applicationScope = RUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "rum-123")
        )
        let sessionScope: RUMSessionScope = .mockWith(parent: applicationScope)

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: sessionScope,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockRandom(),
            name: .mockRandom(),
            attributes: [:],
            customTimings: [:],
            startTime: .mockAny(),
            serverTimeOffset: .zero
        )

        _ = scope.process(
            command: RUMStartUserActionCommand.mockAny(),
            context: context,
            writer: writer
        )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, sessionScope.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, scope.viewUUID)
        XCTAssertEqual(scope.context.activeViewPath, scope.viewPath)
        XCTAssertEqual(scope.context.activeViewName, scope.viewName)
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(scope.userActionScope?.actionUUID))
    }

    func testWhenInitialViewReceivesAnyCommand_itSendsApplicationStartAction() throws {
        // Given
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        var context = self.context
        context.launchTime = .init(
            launchTime: 2,
            launchDate: .distantPast,
            isActivePrewarm: false
        )

        let hasReplay: Bool = .mockRandom()
        context.featuresAttributes = .mockSessionReplayAttributes(hasReplay: hasReplay)

        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        // When
        _ = scope.process(
            command: RUMCommandMock(time: currentTime),
            context: context,
            writer: writer
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.session.hasReplay, hasReplay)
        XCTAssertValidRumUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        XCTAssertValidRumUUID(event.action.id)
        XCTAssertEqual(event.action.type, .applicationStart)
        XCTAssertEqual(event.action.loadingTime, 2_000_000_000) // 2e+9 ns
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertNil(event.context?.contextInfo[RUMViewScope.Constants.activePrewarm])
    }

    func testWhenConfigurationSourceIsSet_applicationStartUsesTheConfigurationSource() throws {
        // Given
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let source = String.mockAnySource()
        let customContext: DatadogContext = .mockWith(source: source)

        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        // When
        _ = scope.process(
            command: RUMCommandMock(time: currentTime),
            context: customContext,
            writer: writer
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.source, .init(rawValue: source))
    }

    func testWhenNoLoadingTime_itSendsApplicationStartAction_basedOnLoadingDate() throws {
        // Given
        var context = self.context
        let date = Date()
        context.launchTime = .init(
            launchTime: nil,
            launchDate: date.addingTimeInterval(-2),
            isActivePrewarm: false
        )

        let scope: RUMViewScope = .mockWith(
            isInitialView: true,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            startTime: date
        )

        // When
        _ = scope.process(
            command: RUMCommandMock(),
            context: context,
            writer: writer
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.action.loadingTime, 2_000_000_000) // 2e+9 ns
    }

    func testWhenActivePrewarm_itSendsApplicationStartAction_withoutLoadingTime() throws {
        // Given
        var context = self.context
        context.launchTime = .init(
            launchTime: 2,
            launchDate: .distantPast,
            isActivePrewarm: true
        )

        let scope: RUMViewScope = .mockWith(
            isInitialView: true,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView
        )

        // When
        _ = scope.process(
            command: RUMCommandMock(),
            context: context,
            writer: writer
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        let isActivePrewarm = try XCTUnwrap(event.context?.contextInfo[RUMViewScope.Constants.activePrewarm] as? Bool)
        XCTAssertEqual(event.action.type, .applicationStart)
        XCTAssertNil(event.action.loadingTime)
        XCTAssertTrue(isActivePrewarm)
    }

    func testWhenInitialViewReceivesAnyCommand_itSendsViewUpdateEvent() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.featuresAttributes = .mockSessionReplayAttributes(hasReplay: hasReplay)

        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        _ = scope.process(
            command: RUMCommandMock(time: currentTime),
            context: context,
            writer: writer
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.session.hasReplay, hasReplay)
        XCTAssertValidRumUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.view.isActive)
        XCTAssertTrue(viewIsActive)
        XCTAssertEqual(event.view.timeSpent, 1) // Minimum `time_spent of 1 nanosecond
        XCTAssertEqual(event.view.action.count, 1, "The initial view update must have come with `application_start` action sent.")
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.dd.documentVersion, 1)
        XCTAssertEqual(event.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testWhenInitialViewHasCconfiguredSource_itSendsViewUpdateEventWithConfiguredSource() throws {
        // GIVEN
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let source = String.mockAnySource()

        let customContext: DatadogContext = .mockWith(source: source)

        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        _ = scope.process(
            command: RUMCommandMock(time: currentTime),
            context: customContext,
            writer: writer
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(event.source, .init(rawValue: source))
    }

    func testWhenViewIsStarted_itSendsViewUpdateEvent() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let isInitialView: Bool = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: ["foo": "bar", "fizz": "buzz"],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar 2"], identity: mockView),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertValidRumUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.view.isActive)
        XCTAssertTrue(viewIsActive)
        XCTAssertEqual(event.view.timeSpent, 1) // Minimum `time_spent of 1 nanosecond
        XCTAssertEqual(event.view.action.count, isInitialView ? 1 : 0, "It must track application start action only if this is an initial view")
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.dd.documentVersion, 1)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar 2", "fizz": "buzz"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testWhenViewIsStopped_itSendsViewUpdateEvent_andEndsTheScope() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let isInitialView: Bool = .mockRandom()
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: ["foo": "bar"],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            )
        )
        currentTime.addTimeInterval(2)
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            ),
            "The scope should end."
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        viewEvents.forEach { viewEvent in
            XCTAssertEqual(
                viewEvent.date,
                Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds,
                "All View events must share the same creation date"
            )
        }

        let event = try XCTUnwrap(viewEvents.dropFirst().first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertValidRumUUID(event.view.id)
        XCTAssertEqual(event.view.url, "UIViewController")
        XCTAssertEqual(event.view.name, "ViewName")
        let viewIsActive = try XCTUnwrap(event.view.isActive)
        XCTAssertFalse(viewIsActive)
        XCTAssertEqual(event.view.timeSpent, TimeInterval(2).toInt64Nanoseconds)
        XCTAssertEqual(event.view.action.count, isInitialView ? 1 : 0, "It must track application start action only if this is an initial view")
        XCTAssertEqual(event.view.error.count, 0)
        XCTAssertEqual(event.view.resource.count, 0)
        XCTAssertEqual(event.dd.documentVersion, 2)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testWhenAnotherViewIsStarted_itEndsTheScope() throws {
        let view1 = createMockView(viewControllerClassName: "FirstViewController")
        let view2 = createMockView(viewControllerClassName: "SecondViewController")
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: view1,
            path: "FirstViewController",
            name: "FirstViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
             scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: view1),
                context: context,
                writer: writer
             )
         )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: view2),
                context: context,
                writer: writer
            ),
            "The scope should end as another View is started."
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        let view1WasActive = try XCTUnwrap(viewEvents[0].view.isActive)
        XCTAssertTrue(view1WasActive)
        XCTAssertEqual(viewEvents[1].view.url, "FirstViewController")
        XCTAssertEqual(viewEvents[1].view.name, "FirstViewName")
        let view2IsActive = try XCTUnwrap(viewEvents[1].view.isActive)
        XCTAssertFalse(view2IsActive)
        XCTAssertEqual(viewEvents[1].view.timeSpent, TimeInterval(1).toInt64Nanoseconds, "The View should last for 1 second")
    }

    func testWhenTheViewIsStartedAnotherTime_itEndsTheScope() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "FirstViewController",
            name: "FirstViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            ),
            "The scope should be kept as the View was started for the first time."
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            ),
            "The scope should end as the View was started for another time."
        )

        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewEvents.count, 2)
        let viewWasActive = try XCTUnwrap(viewEvents[0].view.isActive)
        XCTAssertTrue(viewWasActive)
        XCTAssertEqual(viewEvents[0].view.url, "FirstViewController")
        XCTAssertEqual(viewEvents[0].view.name, "FirstViewName")
        let viewIsActive = try XCTUnwrap(viewEvents[1].view.isActive)
        XCTAssertFalse(viewIsActive)
        XCTAssertEqual(viewEvents[0].view.timeSpent, TimeInterval(1).toInt64Nanoseconds, "The View should last for 1 second")
    }

    func testGivenMultipleViewScopes_whenSendingViewEvent_eachScopeUsesUniqueViewID() throws {
        func createScope(uri: String, name: String) -> RUMViewScope {
            RUMViewScope(
                isInitialView: false,
                parent: parent,
                dependencies: .mockAny(),
                identity: mockView,
                path: uri,
                name: name,
                attributes: [:],
                customTimings: [:],
                startTime: .mockAny(),
                serverTimeOffset: .zero
            )
        }

        // Given
        let scope1 = createScope(uri: "View1URL", name: "View1Name")
        let scope2 = createScope(uri: "View2URL", name: "View2Name")

        // When
        [scope1, scope2].forEach { scope in
            _ = scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
            _ = scope.process(
                command: RUMStopViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        }

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        let view1Events = viewEvents.filter { $0.view.url == "View1URL" && $0.view.name == "View1Name" }
        let view2Events = viewEvents.filter { $0.view.url == "View2URL" && $0.view.name == "View2Name" }
        XCTAssertEqual(view1Events.count, 2)
        XCTAssertEqual(view2Events.count, 2)
        XCTAssertEqual(view1Events[0].view.id, view1Events[1].view.id)
        XCTAssertEqual(view2Events[0].view.id, view2Events[1].view.id)
        XCTAssertNotEqual(view1Events[0].view.id, view2Events[0].view.id)
    }

    // MARK: - Resources Tracking

    func testItManagesResourceScopesLifecycle() throws {
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )

        XCTAssertEqual(scope.resourceScopes.count, 0)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 1)
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 2)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 1)
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.resourceScopes.count, 0)

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )
        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.resource.count, 1, "View should record 1 successful Resource")
        XCTAssertEqual(event.view.error.count, 1, "View should record 1 error due to second Resource failure")
    }

    func testGivenViewWithPendingResources_whenItGetsStopped_itDoesNotFinishUntilResourcesComplete() throws {
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero
        )

        // given
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )

        // when
        XCTAssertTrue(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            ),
            "The View should be kept alive as its Resources haven't yet finished loading"
        )

        // then
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            ),
            "The View should be kept alive as all its Resources haven't yet finished loading"
        )

        var event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertTrue(event.view.isActive ?? false, "View should stay active")

        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            ),
            "The View should stop as all its Resources finished loading"
        )

        event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.resource.count, 1, "View should record 1 successful Resource")
        XCTAssertEqual(event.view.error.count, 1, "View should record 1 error due to second Resource failure")
        XCTAssertFalse(event.view.isActive ?? true, "View should be inactive")
    }

    // MARK: - User Action Tracking

    func testItManagesContinuousUserActionScopeLifecycle() throws {
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero
        )

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )

        XCTAssertNil(scope.userActionScope)
        let actionName = String.mockRandom()
        XCTAssertTrue(
            scope.process(
                command: RUMStartUserActionCommand.mockWith(actionType: .swipe, name: actionName),
                context: context,
                writer: writer
            )
        )
        XCTAssertNotNil(scope.userActionScope)
        XCTAssertEqual(scope.userActionScope?.name, actionName)

        let secondAction = RUMStartUserActionCommand.mockWith(actionType: .swipe, name: .mockRandom())
        XCTAssertTrue(
            scope.process(
                command: secondAction,
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should ignore the next (only non-custom) UA if one is pending.")
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            RUM Action '\(secondAction.actionType)' on '\(secondAction.name)' was dropped, because another action is still active for the same view.
            """
        )

        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockWith(actionType: .custom, name: .mockRandom()),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should not change existing pending action when adding custom UA (but this custom action should be recorded anyway).")

        XCTAssertTrue(
            scope.process(
                command: RUMStopUserActionCommand.mockWith(actionType: .swipe),
                context: context,
                writer: writer
            )
        )
        XCTAssertNil(scope.userActionScope)

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )
        let viewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewEvent.view.action.count, 2, "View should record 2 actions: non-custom + instant custom")
    }

    func testItManagesDiscreteUserActionScopeLifecycle() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertNil(scope.userActionScope)
        let actionName = String.mockRandom()
        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap, name: actionName),
                context: context,
                writer: writer
            )
        )
        XCTAssertNotNil(scope.userActionScope)
        XCTAssertEqual(scope.userActionScope?.name, actionName)

        let secondAction = RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap, name: .mockRandom())
        XCTAssertTrue(
            scope.process(
                command: secondAction,
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should ignore the next (only non-custom) UA if one is pending.")
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            RUM Action '\(secondAction.actionType)' on '\(secondAction.name)' was dropped, because another action is still active for the same view.
            """
        )

        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockWith(actionType: .custom, name: .mockRandom()),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.userActionScope?.name, actionName, "View should not change existing pending action when adding custom UA (but this custom action should be recorded anyway).")

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            )
        )
        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.action.count, 2, "View should record 2 actions: non-custom + instant custom")
    }

    func testGivenViewWithPendingAction_whenCustomActionIsAdded_itSendsItInstantly() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            )

        // Given
        currentTime.addTimeInterval(0.5)

        let pendingActionName: String = .mockRandom()
        _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap, name: pendingActionName),
                context: context,
                writer: writer
            )
        XCTAssertEqual(scope.userActionScope?.name, pendingActionName)

        // When
        let customActionName: String = .mockRandom()
        _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .custom, name: customActionName),
                context: context,
                writer: writer
            )

        // Then
        XCTAssertEqual(scope.userActionScope?.name, pendingActionName, "It should not alter pending action")

        let lastViewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let firstActionEvent = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(lastViewEvent.view.action.count, 1, "View should record 1 only custom action (pending action is not yet finished)")
        XCTAssertEqual(firstActionEvent.action.target?.name, customActionName)
        XCTAssertEqual(firstActionEvent.source, .ios)
        XCTAssertEqual(firstActionEvent.service, "test-service")
        XCTAssertEqual(firstActionEvent.device?.name, "device-name")
        XCTAssertEqual(firstActionEvent.os?.name, "device-os")
    }

    func testGivenViewWithNoPendingAction_whenCustomActionIsAdded_itSendsItInstantly() throws {
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            )

        // Given
        currentTime.addTimeInterval(0.5)

        XCTAssertNil(scope.userActionScope)

        // When
        let customActionName: String = .mockRandom()
        _ = scope.process(
                command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .custom, name: customActionName),
                context: context,
                writer: writer
            )

        // Then
        XCTAssertNil(scope.userActionScope, "It should not count custom action as pending")

        let lastViewEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        let firstActionEvent = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(lastViewEvent.view.action.count, 1, "View should record custom action")
        XCTAssertEqual(firstActionEvent.action.target?.name, customActionName)
        XCTAssertEqual(firstActionEvent.source, .ios)
        XCTAssertEqual(firstActionEvent.service, "test-service")
        XCTAssertEqual(firstActionEvent.device?.name, "device-name")
        XCTAssertEqual(firstActionEvent.os?.name, "device-os")
    }

    func testWhenDiscreteUserActionHasFrustration_itSendsFrustrationCount() throws {
        // Given
        var currentTime = Date()
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            )
        )

        // When
        (0..<5).forEach { i in
            XCTAssertTrue(
                scope.process(
                    command: RUMAddUserActionCommand.mockWith(time: currentTime, actionType: .tap),
                    context: context,
                    writer: writer
                )
            )

            XCTAssertTrue(
                scope.process(
                    command: RUMAddCurrentViewErrorCommand.mockRandom(),
                    context: context,
                    writer: writer
                )
            )

            currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)
        }

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(time: currentTime, identity: mockView),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.frustration?.count, 5)
    }

    // MARK: - Error Tracking

    func testWhenViewErrorIsAdded_itSendsErrorEventAndViewUpdateEvent() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.featuresAttributes = .mockSessionReplayAttributes(hasReplay: hasReplay)

        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: mockView),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime, message: "view error", source: .source, stack: nil),
                context: context,
                writer: writer
            )
        )

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.date, Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1).timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(error.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(error.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(error.session.type, .user)
        XCTAssertEqual(error.session.hasReplay, hasReplay)
        XCTAssertValidRumUUID(error.view.id)
        XCTAssertEqual(error.view.url, "UIViewController")
        XCTAssertEqual(error.view.name, "ViewName")
        XCTAssertNil(error.usr)
        XCTAssertNil(error.connectivity)
        XCTAssertEqual(error.error.type, "abc")
        XCTAssertEqual(error.error.message, "view error")
        XCTAssertEqual(error.error.source, .source)
        XCTAssertEqual(error.error.sourceType, .ios)
        XCTAssertNil(error.error.stack)
        XCTAssertTrue(error.error.isCrash == false)
        XCTAssertNil(error.error.resource)
        XCTAssertNil(error.action)
        XCTAssertEqual(error.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(error.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(error.source, .ios)
        XCTAssertEqual(error.service, "test-service")
        XCTAssertEqual(error.device?.name, "device-name")
        XCTAssertEqual(error.os?.name, "device-os")

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.error.count, 1)
    }

    func testWhenViewErrorIsAddedWithConfiguredSource_itSendsErrorEventWithCorrectSource() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let source = String.mockAnySource()

        let customContext: DatadogContext = .mockWith(source: source)

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: currentTime, attributes: ["foo": "bar"], identity: mockView),
                context: customContext,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime, message: "view error", source: .source, stack: nil),
                context: customContext,
                writer: writer
            )
        )

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.source, .init(rawValue: source))
        // Configured source should not muck with sourceType, which is set seperately.
        XCTAssertEqual(error.error.sourceType, .ios)
    }

    func testGivenStartedView_whenCrossPlatformErrorIsAdded_itSendsCorrectErrorEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()

        let customSource = String.mockAnySource()
        let expectedSource = RUMErrorEvent.Source(rawValue: customSource)
        let customContext: DatadogContext = .mockWith(
            service: "test-service",
            source: customSource
        )

        let scope: RUMViewScope = .mockWith(
            parent: parent,
            dependencies: .mockAny()
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockAny(),
                context: customContext,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        let customSourceType = String.mockAnySource()
        let expectedSourceType = RUMErrorSourceType.init(rawValue: customSourceType)
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(
                    attributes: [
                        CrossPlatformAttributes.errorSourceType: customSourceType,
                        CrossPlatformAttributes.errorIsCrash: true
                    ]
                ),
                context: customContext,
                writer: writer
            )
        )

        let error = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self).last)
        XCTAssertEqual(error.error.sourceType, expectedSourceType)
        XCTAssertTrue(error.error.isCrash ?? false)
        XCTAssertEqual(error.source, expectedSource)
        XCTAssertEqual(error.service, "test-service")

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.error.count, 1)
        XCTAssertEqual(viewUpdate.source, RUMViewEvent.Source(rawValue: customSource))
        XCTAssertEqual(viewUpdate.service, "test-service")
    }

    func testWhenResourceIsFinishedWithError_itSendsViewUpdateEvent() throws {
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(attributes: ["foo": "bar"], identity: mockView),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorObject(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.resource.count, 0, "Failed Resource should not be counted")
        XCTAssertEqual(viewUpdate.view.error.count, 1, "Failed Resource should be counted as Error")
    }

    // MARK: - Long tasks

    func testWhenLongTaskIsAdded_itSendsLongTaskEventAndViewUpdateEvent() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.featuresAttributes = .mockSessionReplayAttributes(hasReplay: hasReplay)

        let startViewDate: Date = .mockDecember15th2019At10AMUTC()

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: startViewDate,
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: startViewDate, attributes: ["foo": "bar"], identity: mockView),
                context: context,
                writer: writer
            )
        )

        let addLongTaskDate = startViewDate + 1.0
        let duration: TimeInterval = 1.0

        XCTAssertTrue(
            scope.process(
                command: RUMAddLongTaskCommand(time: addLongTaskDate, attributes: ["foo": "bar"], duration: duration),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMLongTaskEvent.self).last)

        let longTaskStartingDate = addLongTaskDate - duration

        XCTAssertEqual(event.action?.id.stringValue, scope.context.activeUserActionID?.toRUMDataFormat)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.hasReplay, hasReplay)
        XCTAssertNil(event.connectivity)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.date, longTaskStartingDate.timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.dd.session?.plan, .plan1)
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.longTask.duration, (1.0).toInt64Nanoseconds)
        XCTAssertTrue(event.longTask.isFrozenFrame == true)
        XCTAssertEqual(event.view.id, scope.viewUUID.toRUMDataFormat)
        XCTAssertNil(event.synthetics)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")

        let viewUpdate = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(viewUpdate.view.longTask?.count, 1)
    }

    func testWhenLongTaskIsAddedWithConfiguredSource_itSendsLongTaskEventWithConfiguredSource() throws {
        let startViewDate: Date = .mockDecember15th2019At10AMUTC()

        let source = String.mockAnySource()
        let customContext: DatadogContext = .mockWith(source: source)

        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: "UIViewController",
            name: "ViewName",
            attributes: [:],
            customTimings: [:],
            startTime: startViewDate,
            serverTimeOffset: .zero
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(time: startViewDate, attributes: ["foo": "bar"], identity: mockView),
                context: customContext,
                writer: writer
            )
        )

        let addLongTaskDate = startViewDate + 1.0
        let duration: TimeInterval = 1.0

        XCTAssertTrue(
            scope.process(
                command: RUMAddLongTaskCommand(time: addLongTaskDate, attributes: ["foo": "bar"], duration: duration),
                context: customContext,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMLongTaskEvent.self).last)
        XCTAssertEqual(event.source, .init(rawValue: source))
    }

    // MARK: - Custom Timings Tracking

    func testGivenActiveView_whenCustomTimingIsRegistered_itSendsViewUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )

        // Given
        XCTAssertTrue(scope.isActiveView)
        XCTAssertEqual(scope.customTimings.count, 0)

        // When
        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.customTimings.count, 1)

        currentTime.addTimeInterval(0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-1000000000ns"),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.customTimings.count, 2)

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 3, "There should be 3 View updates sent")
        XCTAssertEqual(events[0].view.customTimings, [:])
        XCTAssertEqual(
            events[1].view.customTimings,
            ["timing-after-500000000ns": 500_000_000]
        )
        XCTAssertEqual(
            events[2].view.customTimings,
            ["timing-after-500000000ns": 500_000_000, "timing-after-1000000000ns": 1_000_000_000]
        )
    }

    func testGivenInactiveView_whenCustomTimingIsRegistered_itDoesNotSendViewUpdateEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )

        // Given
        XCTAssertFalse(scope.isActiveView)

        // When
        currentTime.addTimeInterval(0.5)

        _ = scope.process(
            command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: "timing-after-500000000ns"),
            context: context,
            writer: writer
        )

        // Then
        let lastEvent = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastEvent.view.customTimings, [:])
    }

    func testGivenActiveView_whenCustomTimingIsRegistered_itSanitizesCustomTiming() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )

        // Given
        XCTAssertTrue(scope.isActiveView)
        XCTAssertEqual(scope.customTimings.count, 0)

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        currentTime.addTimeInterval(0.5)
        let originalTimingName = "timing1_.@$-()&+=Д"
        let sanitizedTimingName = "timing1_.@$-______"
        XCTAssertTrue(
            scope.process(
                command: RUMAddViewTimingCommand.mockWith(time: currentTime, timingName: originalTimingName),
                context: context,
                writer: writer
            )
        )
        XCTAssertEqual(scope.customTimings.count, 1)

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 2, "There should be 2 View updates sent")
        XCTAssertEqual(events[0].view.customTimings, [:])
        XCTAssertEqual(
            events[1].view.customTimings,
            [sanitizedTimingName: 500_000_000]
        )
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            Custom timing '\(originalTimingName)' was modified to '\(sanitizedTimingName)' to match Datadog constraints.
            """
        )
    }

    // MARK: - Feature Flags

    func testGivenActiveView_whenFeatureFlagEvaluated_itAddsTheFeatureFlag() throws {
        // Given
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )
        let featureFlagCommand = RUMAddFeatureFlagEvaluationCommand.mockRandom()

        // When
        XCTAssertTrue(
            scope.process(
                command: featureFlagCommand,
                context: context,
                writer: writer
            )
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 2)
        let initialFlags = try XCTUnwrap(events[0].featureFlags)
        XCTAssertEqual(initialFlags.featureFlagsInfo.count, 0)
        let featureFlags = try XCTUnwrap(events[1].featureFlags)
        XCTAssertEqual(featureFlags.featureFlagsInfo.count, 1)
        XCTAssertEqual(featureFlags.featureFlagsInfo[featureFlagCommand.name] as! String, featureFlagCommand.value as! String)
    }

    func testGivenActiveView_whenFeatureFlagReEvaluated_itModifiesTheFeatureFlag() throws {
        // Given
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )
        let flagName: String = .mockRandom()
        let flagFinalValue: String = .mockRandom()

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddFeatureFlagEvaluationCommand.mockWith(
                    name: flagName
                ),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMAddFeatureFlagEvaluationCommand.mockWith(
                    name: flagName,
                    value: flagFinalValue
                ),
                context: context,
                writer: writer
            )
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self))

        XCTAssertEqual(events.count, 3)
        let featureFlags = try XCTUnwrap(events[2].featureFlags)
        XCTAssertEqual(featureFlags.featureFlagsInfo.count, 1)
        XCTAssertEqual(featureFlags.featureFlagsInfo[flagName] as! String, flagFinalValue)
    }

    func testGivenActiveViewWithFeatureFlag_itSendsThoseFlagsWithErrors() throws {
        // Given
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: currentTime,
            serverTimeOffset: .zero
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )
        let mockFeatureFlagCommand: RUMAddFeatureFlagEvaluationCommand = .mockRandom()
        XCTAssertTrue(
            scope.process(
                command: mockFeatureFlagCommand,
                context: context,
                writer: writer
            )
        )

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockAny(),
                context: context,
                writer: writer
            )
        )

        // Then
        let events = try XCTUnwrap(writer.events(ofType: RUMErrorEvent.self))

        XCTAssertEqual(events.count, 1)
        let featureFlags = try XCTUnwrap(events[0].featureFlags)
        XCTAssertEqual(featureFlags.featureFlagsInfo.count, 1)
        XCTAssertEqual(
            featureFlags.featureFlagsInfo[mockFeatureFlagCommand.name] as! String,
            mockFeatureFlagCommand.value as! String
        )
    }

    // MARK: - Dates Correction

    func testGivenViewStartedWithServerTimeDifference_whenDifferentEventsAreSend_itAppliesTheSameCorrectionToAll() throws {
        let initialDeviceTime: Date = .mockDecember15th2019At10AMUTC()
        let initialServerTimeOffset: TimeInterval = 120 // 2 minutes
        var currentDeviceTime = initialDeviceTime

        // Given
        let scope = RUMViewScope(
            isInitialView: false,
            parent: parent,
            dependencies: .mockAny(),
            identity: mockView,
            path: .mockAny(),
            name: .mockAny(),
            attributes: [:],
            customTimings: [:],
            startTime: initialDeviceTime,
            serverTimeOffset: initialServerTimeOffset
        )

        // When
        _ = scope.process(
                command: RUMStartViewCommand.mockWith(time: currentDeviceTime, identity: mockView),
                context: context,
                writer: writer
        )
        currentDeviceTime.addTimeInterval(1) // advance device time

        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1", time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2", time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1", time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "/resource/2", time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentDeviceTime),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: currentDeviceTime),
            context: context,
            writer: writer
        )

        _ = scope.process(
                command: RUMStopViewCommand.mockWith(time: currentDeviceTime, identity: mockView),
                context: context,
                writer: writer
        )

        // Then
        let viewEvents = writer.events(ofType: RUMViewEvent.self)
        let resourceEvents = writer.events(ofType: RUMResourceEvent.self)
        let errorEvents = writer.events(ofType: RUMErrorEvent.self)
        let actionEvents = writer.events(ofType: RUMActionEvent.self)

        let initialRealTime = initialDeviceTime.addingTimeInterval(initialServerTimeOffset)
        let expectedViewEventsDate = initialRealTime.timeIntervalSince1970.toInt64Milliseconds
        let expectedOtherEventsDate = initialRealTime.addingTimeInterval(1).timeIntervalSince1970.toInt64Milliseconds

        XCTAssertFalse(viewEvents.isEmpty)
        XCTAssertFalse(resourceEvents.isEmpty)
        XCTAssertFalse(errorEvents.isEmpty)
        XCTAssertFalse(actionEvents.isEmpty)

        viewEvents.forEach { view in
            XCTAssertEqual(view.date, expectedViewEventsDate)
        }
        resourceEvents.forEach { view in
            XCTAssertEqual(view.date, expectedOtherEventsDate)
        }
        errorEvents.forEach { view in
            XCTAssertEqual(view.date, expectedOtherEventsDate)
        }
        actionEvents.forEach { view in
            XCTAssertEqual(view.date, expectedOtherEventsDate)
        }
    }

    // MARK: ViewScope Counts Correction

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
            eventsMapper: .mockWith(
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
        let dependencies: RUMScopeDependencies = .mockWith(
            eventBuilder: eventBuilder
        )

        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "UIViewController",
            name: "ViewController",
            attributes: [:],
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMAddUserActionCommand.mockAny(),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2"),
                context: context,
                writer: writer
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
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/2"),
                context: context,
                writer: writer
            )
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1"),
                context: context,
                writer: writer
            )
        )

        XCTAssertEqual(scope.resourceScopes.count, 0)

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)

        // Then
        XCTAssertEqual(event.view.resource.count, 1, "After dropping 1 Resource event (out of 2), View should record 1 Resource")
        XCTAssertEqual(event.view.action.count, 1, "After dropping a User Action event, View should record only ApplicationStart Action")
        XCTAssertEqual(event.view.error.count, 0, "After dropping an Error event, View should record 0 Errors")
        XCTAssertEqual(event.dd.documentVersion, 3, "After starting the application, stopping the view, starting/stopping one resource out of 2, discarding a user action and an error, the View scope should have sent 3 View events.")
    }

    func testGivenViewScopeWithDroppingEventsMapper_whenProcessingApplicationStartAction_thenCountIsAdjusted() throws {
        let eventBuilder = RUMEventBuilder(
            eventsMapper: .mockWith(
                actionEventMapper: { event in
                    nil
                }
            )
        )
        let dependencies: RUMScopeDependencies = .mockWith(
            eventBuilder: eventBuilder
        )

        // Given
        let scope = RUMViewScope(
            isInitialView: true,
            parent: parent,
            dependencies: dependencies,
            identity: mockView,
            path: "UIViewController",
            name: "ViewController",
            attributes: [:],
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero
        )

        // When
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: mockView),
                context: context,
                writer: writer
            )
        )

        // Then
        let event = try XCTUnwrap(writer.events(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(event.view.action.count, 0, "All actions, including ApplicationStart action should be dropped")
        XCTAssertEqual(event.dd.documentVersion, 1, "It should record only one view update")
    }

    // MARK: Suppressing number of view updates

    // swiftlint:disable opening_brace
    func testGivenScopeWithViewUpdatesThrottler_whenReceivingStreamOfCommands_thenItSendsLessViewUpdatesThanScopeWithNoThrottler() throws {
        let commandsIssuingViewUpdates: [(Date) -> RUMCommand] = [
            // receive resource:
            { date in RUMStartResourceCommand.mockWith(resourceKey: "resource", time: date) },
            { date in RUMStopResourceCommand.mockWith(resourceKey: "resource", time: date) },
            // add action:
            { date in RUMStartUserActionCommand.mockWith(time: date, actionType: .scroll) },
            { date in RUMStopUserActionCommand.mockWith(time: date, actionType: .scroll) },
            // add error:
            { date in RUMAddCurrentViewErrorCommand.mockWithErrorObject(time: date) },
            // add long task:
            { date in RUMAddLongTaskCommand.mockWith(time: date) },
            // receive timing:
            { date in RUMAddViewTimingCommand.mockWith(time: date, timingName: .mockRandom()) },
        ]
        let stopViewCommand: [(Date) -> RUMCommand] = [
            { date in RUMStopViewCommand.mockWith(time: date, identity: mockView) }
        ]

        let commands = (0..<5).flatMap({ _ in commandsIssuingViewUpdates }) + stopViewCommand // loop 5 times through all commands
        let timeIntervalBetweenCommands = 1.0
        let simulationDuration = timeIntervalBetweenCommands * Double(commands.count)
        let samplingDuration = simulationDuration * 0.5 // at least half view updates should be skipped

        // Given
        let throttler = RUMViewUpdatesThrottler(viewUpdateThreshold: samplingDuration)
        let sampledWriter = FileWriterMock()
        let sampledScope: RUMViewScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(
                viewUpdatesThrottlerFactory: { throttler }
            )
        )

        let noOpThrottler = NoOpRUMViewUpdatesThrottler()
        let notSampledWriter = FileWriterMock()
        let notSampledScope: RUMViewScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(
                viewUpdatesThrottlerFactory: { noOpThrottler }
            )
        )

        // When
        func send(commands: [(Date) -> RUMCommand], to scope: RUMViewScope, writer: Writer) {
            var currentTime = scope.viewStartTime
            commands.forEach { command in
                currentTime.addTimeInterval(timeIntervalBetweenCommands)
                _ = scope.process(
                    command: command(currentTime),
                    context: context,
                    writer: writer
                )
            }
        }

        send(commands: commands, to: sampledScope, writer: sampledWriter)
        send(commands: commands, to: notSampledScope, writer: notSampledWriter)

        // Then
        let viewUpdatesInSampledScope = sampledWriter.events(ofType: RUMViewEvent.self)
        let viewUpdatesInNotSampledScope = notSampledWriter.events(ofType: RUMViewEvent.self)
        XCTAssertLessThan(
            viewUpdatesInSampledScope.count,
            viewUpdatesInNotSampledScope.count ,
            "Sampled scope should send less view updates than not sampled"
        )

        let actualSamplingRatio = Double(viewUpdatesInSampledScope.count) / Double(viewUpdatesInNotSampledScope.count)
        let maxExpectedSamplingRatio = samplingDuration / simulationDuration
        XCTAssertLessThan(
            actualSamplingRatio,
            maxExpectedSamplingRatio,
            "Less than \(maxExpectedSamplingRatio * 100)% of view updates should be sampled"
        )

        let actualLastUpdate = try XCTUnwrap(viewUpdatesInSampledScope.last)
        let expectedLastUpdate = try XCTUnwrap(viewUpdatesInNotSampledScope.last)
        XCTAssertEqual(actualLastUpdate.view.resource.count, expectedLastUpdate.view.resource.count, "It should count all resources")
        XCTAssertEqual(actualLastUpdate.view.action.count, expectedLastUpdate.view.action.count, "It should count all actions")
        XCTAssertEqual(actualLastUpdate.view.error.count, expectedLastUpdate.view.error.count, "It should count all errors")
        XCTAssertEqual(actualLastUpdate.view.longTask?.count, expectedLastUpdate.view.longTask?.count, "It should count all long tasks")
        XCTAssertEqual(actualLastUpdate.view.customTimings?.count, expectedLastUpdate.view.customTimings?.count, "It should count all view timings")
        XCTAssertTrue(actualLastUpdate.view.isActive == false, "Terminal view update must always be sent")
    }
    // swiftlint:enable opening_brace

    // MARK: Integration with Crash Context

    func testWhenViewIsStarted_thenItUpdatesLastRUMViewEventInCrashContext() throws {
        var viewEvent: RUMViewEvent? = nil
        let messageReciever = FeatureMessageReceiverMock { message in
            if case let .custom(_, baggage) = message {
                viewEvent = baggage[RUMBaggageKeys.viewEvent]
            }
        }

        let core = PassthroughCoreMock(
            messageReceiver: messageReciever
        )

        // Given
        let scope = RUMViewScope(
            isInitialView: .mockRandom(),
            parent: parent,
            dependencies: .mockWith(core: core),
            identity: mockView,
            path: "UIViewController",
            name: "ViewController",
            attributes: [:],
            customTimings: [:],
            startTime: Date(),
            serverTimeOffset: .zero
        )

        // When
        core.eventWriteContext { context, writer in
            XCTAssertTrue(
                scope.process(
                    command: RUMStartViewCommand.mockWith(identity: mockView),
                    context: context,
                    writer: writer
                )
            )
        }

        // Then
        let rumViewSent = try XCTUnwrap(core.events(ofType: RUMViewEvent.self).last, "It should send view event")
        DDAssertReflectionEqual(viewEvent, rumViewSent, "It must inject sent event to crash context")
    }

    // MARK: Cross-platform crashes

    func testGivenScopeWithViewUpdatesThrottler_whenReceivingCrossPlatformCrash_thenItSendsViewUpdateWithUpdatedCrashCount() throws {
        let commands: [(Date) -> RUMCommand] = [
            // receive resource:
            { date in RUMStartResourceCommand.mockWith(resourceKey: "resource", time: date) }, { date in RUMStopResourceCommand.mockWith(resourceKey: "resource", time: date) },
            // receive error:
            { date in RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: date, attributes: [CrossPlatformAttributes.errorIsCrash: true]) }
        ]
        let timeIntervalBetweenCommands = 1.0
        let simulationDuration = timeIntervalBetweenCommands * Double(commands.count)
        let samplingDuration = simulationDuration * 0.5 // at least half view updates should be skipped

        // Given
        let throttler = RUMViewUpdatesThrottler(viewUpdateThreshold: samplingDuration)
        let sampledWriter = FileWriterMock()
        let sampledScope: RUMViewScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(
                viewUpdatesThrottlerFactory: { throttler }
            )
        )

        // When
        func send(commands: [(Date) -> RUMCommand], to scope: RUMViewScope, writer: Writer) {
            var currentTime = scope.viewStartTime
            commands.forEach { command in
                currentTime.addTimeInterval(timeIntervalBetweenCommands)
                _ = scope.process(
                    command: command(currentTime),
                    context: context,
                    writer: writer
                )
            }
        }

        send(commands: commands, to: sampledScope, writer: sampledWriter)

        // Then
        let viewUpdatesInSampledScope = sampledWriter.events(ofType: RUMViewEvent.self)
        XCTAssertEqual(viewUpdatesInSampledScope.count, 2, "It should send the first event and the error")

        let actualLastUpdate = try XCTUnwrap(viewUpdatesInSampledScope.last)
        XCTAssertEqual(actualLastUpdate.view.crash?.count, 1, "It should contain a crash")
    }
}
