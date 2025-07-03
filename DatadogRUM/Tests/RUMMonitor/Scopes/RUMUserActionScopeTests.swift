/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import TestUtilities
@testable import DatadogRUM

class RUMUserActionScopeTests: XCTestCase {
    let context: DatadogContext = .mockWith(
        service: "test-service",
        version: "test-version",
        buildNumber: "test-build",
        buildId: .mockRandom(),
        device: .mockWith(name: "device-name"),
        os: .mockWith(name: "device-os")
    )

    let writer = FileWriterMock()

    private let parent = RUMContextProviderMock(
        context: .mockWith(
            rumApplicationID: "rum-123",
            sessionID: .mockRandom(),
            activeViewID: .mockRandom(),
            activeViewPath: "FooViewController",
            activeViewName: "FooViewName",
            activeUserActionID: .mockRandom()
        )
    )

    func testDefaultContext() {
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .swipe,
            isContinuous: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, parent.context.rumApplicationID)
        XCTAssertEqual(scope.context.sessionID, parent.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, try XCTUnwrap(parent.context.activeViewID))
        XCTAssertEqual(scope.context.activeViewPath, try XCTUnwrap(parent.context.activeViewPath))
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(parent.context.activeUserActionID))
    }

    func testGivenActiveUserAction_whenViewIsStopped_itSendsUserActionEvent() throws {
        let hasReplay: Bool = .mockRandom()
        var context = self.context
        context.set(additionalContext: SessionReplayCoreContext.HasReplay(value: hasReplay))

        let scope = RUMViewScope.mockWith(
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            attributes: [:],
            startTime: Date()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        let mockUserActionCmd = RUMAddUserActionCommand.mockAny()
        XCTAssertTrue(
            scope.process(
                command: mockUserActionCmd,
                context: context,
                writer: writer
            )
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        let recordedActionEvents = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(recordedActionEvents.count, 1)
        let recordedAction = try XCTUnwrap(recordedActionEvents.last)
        XCTAssertEqual(recordedAction.action.type.rawValue, String(describing: mockUserActionCmd.actionType))
        XCTAssertEqual(recordedAction.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(recordedAction.session.hasReplay, hasReplay)
        XCTAssertEqual(recordedAction.source, .ios)
        XCTAssertEqual(recordedAction.service, "test-service")
        XCTAssertEqual(recordedAction.version, "test-version")
        XCTAssertEqual(recordedAction.buildVersion, "test-build")
        XCTAssertEqual(recordedAction.buildId, context.buildId)
        XCTAssertEqual(recordedAction.device?.name, "device-name")
        XCTAssertEqual(recordedAction.os?.name, "device-os")
    }

    func testGivenActiveUserAction_whenNewViewStart_itSendsUserActionEvent() throws {
        let scope = RUMViewScope.mockWith(
            parent: parent,
            dependencies: .mockAny(),
            identity: .mockViewIdentifier(),
            attributes: [:],
            startTime: Date()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )
        let mockUserActionCmd = RUMAddUserActionCommand.mockAny()
        XCTAssertTrue(
            scope.process(
                command: mockUserActionCmd,
                context: context,
                writer: writer
            )
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStartViewCommand.mockAny(),
                context: context,
                writer: writer
            )
        )

        let recordedActionEvents = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(recordedActionEvents.count, 1)
        let recordedAction = try XCTUnwrap(recordedActionEvents.last)
        XCTAssertEqual(recordedAction.action.type.rawValue, String(describing: mockUserActionCmd.actionType))
        XCTAssertEqual(recordedAction.dd.session?.plan, .plan1, "All RUM events should use RUM Lite plan")
        XCTAssertEqual(recordedAction.source, .ios)
        XCTAssertEqual(recordedAction.service, "test-service")
        XCTAssertEqual(recordedAction.version, "test-version")
        XCTAssertEqual(recordedAction.buildVersion, "test-build")
        XCTAssertEqual(recordedAction.buildId, context.buildId)
        XCTAssertEqual(recordedAction.device?.name, "device-name")
        XCTAssertEqual(recordedAction.os?.name, "device-os")
    }

    func testGivenCustomSource_whenActionIsSent_itSendsCustomSource() throws {
        let source = String.mockAnySource()
        let customContext: DatadogContext = .mockWith(source: source)

        let scope = RUMViewScope.mockWith(
            parent: parent,
            identity: .mockViewIdentifier(),
            startTime: Date()
        )
        XCTAssertTrue(
            scope.process(
                command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: customContext,
                writer: writer
            )
        )

        let mockUserActionCmd = RUMAddUserActionCommand.mockAny()
        XCTAssertTrue(
            scope.process(
                command: mockUserActionCmd,
                context: customContext,
                writer: writer
            )
        )
        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: customContext,
                writer: writer
            )
        )

        let recordedActionEvents = writer.events(ofType: RUMActionEvent.self)
        let recordedAction = try XCTUnwrap(recordedActionEvents.last)
        XCTAssertEqual(recordedAction.source, .init(rawValue: source))
    }

    // MARK: - Continuous User Action

    func testWhenContinuousUserActionEnds_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .swipe,
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand(
                    time: currentTime,
                    globalAttributes: [:],
                    attributes: ["foo": "bar"],
                    actionType: .swipe,
                    name: nil
                ),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, parent.context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.action.id, scope.actionUUID.toRUMDataFormat)
        XCTAssertEqual(event.action.type, .swipe)
        XCTAssertEqual(event.action.loadingTime, 1_000_000_000)
        XCTAssertEqual(event.action.resource?.count, 0)
        XCTAssertEqual(event.action.error?.count, 0)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
    }

    func testWhenContinuousUserActionEndsInCiTest_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let fakeCiTestId: String = .mockRandom()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            dependencies: .mockWith(ciTest: .init(testExecutionId: fakeCiTestId)),
            actionType: .swipe,
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand(
                    time: currentTime,
                    globalAttributes: [:],
                    attributes: ["foo": "bar"],
                    actionType: .swipe,
                    name: nil
                ),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .ciTest)
        XCTAssertEqual(event.view.id, parent.context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.action.id, scope.actionUUID.toRUMDataFormat)
        XCTAssertEqual(event.action.type, .swipe)
        XCTAssertEqual(event.action.loadingTime, 1_000_000_000)
        XCTAssertEqual(event.action.resource?.count, 0)
        XCTAssertEqual(event.action.error?.count, 0)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.ciTest?.testExecutionId, fakeCiTestId)
    }

    func testWhenContinuousUserActionEndsInSyntheticsTest_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let fakeSyntheticsTestId: String = .mockRandom()
        let fakeSyntheticsResultId: String = .mockRandom()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            dependencies: .mockWith(syntheticsTest: .init(RUMSyntheticsTest(injected: nil, resultId: fakeSyntheticsResultId, testId: fakeSyntheticsTestId))),
            actionType: .swipe,
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand(
                    time: currentTime,
                    globalAttributes: [:],
                    attributes: ["foo": "bar"],
                    actionType: .swipe,
                    name: nil
                ),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .synthetics)
        XCTAssertEqual(event.view.id, parent.context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.action.id, scope.actionUUID.toRUMDataFormat)
        XCTAssertEqual(event.action.type, .swipe)
        XCTAssertEqual(event.action.loadingTime, 1_000_000_000)
        XCTAssertEqual(event.action.resource?.count, 0)
        XCTAssertEqual(event.action.error?.count, 0)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.synthetics?.testId, fakeSyntheticsTestId)
        XCTAssertEqual(event.synthetics?.resultId, fakeSyntheticsResultId)
    }

    func testWhenContinuousUserActionEndsWithSessionTypeOverride() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let fakeSyntheticsTestId: String = .mockRandom()
        let fakeSyntheticsResultId: String = .mockRandom()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            dependencies: .mockWith(
                syntheticsTest: .init(RUMSyntheticsTest(injected: nil, resultId: fakeSyntheticsResultId, testId: fakeSyntheticsTestId)),
                sessionType: .user
            ),
            actionType: .swipe,
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
                ),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toInt64Milliseconds)
        XCTAssertEqual(event.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(event.session.type, .user)
        XCTAssertEqual(event.view.id, parent.context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(event.view.url, "FooViewController")
        XCTAssertEqual(event.view.name, "FooViewName")
        XCTAssertEqual(event.action.id, scope.actionUUID.toRUMDataFormat)
        XCTAssertEqual(event.action.type, .swipe)
        XCTAssertEqual(event.action.loadingTime, 1_000_000_000)
        XCTAssertEqual(event.action.resource?.count, 0)
        XCTAssertEqual(event.action.error?.count, 0)
        XCTAssertEqual(event.context?.contextInfo as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.source, .ios)
        XCTAssertEqual(event.service, "test-service")
        XCTAssertEqual(event.version, "test-version")
        XCTAssertEqual(event.buildVersion, "test-build")
        XCTAssertEqual(event.buildId, context.buildId)
        XCTAssertEqual(event.device?.name, "device-name")
        XCTAssertEqual(event.os?.name, "device-os")
        XCTAssertEqual(event.synthetics?.testId, fakeSyntheticsTestId)
        XCTAssertEqual(event.synthetics?.resultId, fakeSyntheticsResultId)
    }

    func testWhenContinuousUserActionExpires_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .swipe,

            startTime: currentTime,
            isContinuous: true
        )

        let expirationInterval = RUMUserActionScope.Constants.continuousActionMaxDuration

        currentTime = .mockDecember15th2019At10AMUTC(addingTimeInterval: expirationInterval * 0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMCommandMock(time: currentTime),
                context: context,
                writer: writer
            ),
            "Continuous User Action should not expire after \(expirationInterval * 0.5)s"
        )

        currentTime = .mockDecember15th2019At10AMUTC(addingTimeInterval: expirationInterval * 2.0)
        XCTAssertFalse(
            scope.process(
                command: RUMCommandMock(time: currentTime),
                context: context,
                writer: writer
            ),
            "Continuous User Action should expire after \(expirationInterval)s"
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.action.loadingTime, 10_000_000_000, "Loading time should not exceed expirationInterval")
    }

    func testWhileContinuousUserActionIsActive_itTracksCompletedResources() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .scroll,
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1", time: currentTime),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2", time: currentTime),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1", time: currentTime),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorObject(resourceKey: "/resource/2", time: currentTime),
                context: context,
                writer: writer
            )
        )

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand.mockWith(time: currentTime, actionType: .scroll),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(event.action.resource?.count, 1, "User Action should track first successful Resource")
        XCTAssertEqual(event.action.error?.count, 1, "User Action should track second Resource failure as Error")
    }

    func testWhileContinuousUserActionIsActive_itCountsViewErrors() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .scroll,
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand.mockWith(time: currentTime, actionType: .scroll),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(event.action.error?.count, 1)
    }

    func testWhenContinuousUserActionStopsWithName_itChangesItsName() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .scroll,
            startTime: currentTime,
            isContinuous: true
        )

        currentTime.addTimeInterval(0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMCommandMock(),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(1)
        let differentName = String.mockRandom()
        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand.mockWith(time: currentTime, actionType: .scroll, name: differentName),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(event.action.target?.name, differentName)
    }

    // MARK: - Discrete User Action

    func testWhenDiscreteUserActionTimesOut_itSendsActionEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .swipe,
            startTime: currentTime,
            isContinuous: false
        )

        let timeOutInterval = RUMUserActionScope.Constants.discreteActionTimeoutDuration

        currentTime = .mockDecember15th2019At10AMUTC(addingTimeInterval: timeOutInterval * 0.5)
        XCTAssertTrue(
            scope.process(
                command: RUMCommandMock(time: currentTime),
                context: context,
                writer: writer
            ),
            "Discrete User Action should not time out after \(timeOutInterval * 0.5)s"
        )

        currentTime.addTimeInterval(timeOutInterval)
        XCTAssertFalse(
            scope.process(
                command: RUMCommandMock(time: currentTime),
                context: context,
                writer: writer
            ),
            "Discrete User Action should time out after \(timeOutInterval)s"
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        let nanosecondsInSecond: Double = 1_000_000_000
        let actionLoadingTimeInSeconds = Double(try XCTUnwrap(event.action.loadingTime)) / nanosecondsInSecond
        XCTAssertEqual(actionLoadingTimeInSeconds, RUMUserActionScope.Constants.discreteActionTimeoutDuration, accuracy: 0.1)
    }

    func testWhileDiscreteUserActionIsActive_itDoesNotComplete_untilAllTrackedResourcesAreCompleted() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .scroll,
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(0.05)

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1", time: currentTime),
                context: context,
                writer: writer
            )
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/2", time: currentTime),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceCommand.mockWith(resourceKey: "/resource/1", time: currentTime),
                context: context,
                writer: writer
            ),
            "Discrete User Action should not yet complete as it still has 1 pending Resource"
        )

        XCTAssertTrue(
            scope.process(
                command: RUMStopResourceWithErrorCommand.mockWithErrorObject(resourceKey: "/resource/2", time: currentTime),
                context: context,
                writer: writer
            ),
            "Discrete User Action should not yet complete as it haven't reached the time out duration"
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(
                command: RUMCommandMock(time: currentTime),
                context: context,
                writer: writer
            ),
            "Discrete User Action should complete as it has no more pending Resources and it reached the timeout duration"
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(event.action.resource?.count, 1, "User Action should track first successful Resource")
        XCTAssertEqual(event.action.error?.count, 1, "User Action should track second Resource failure as Error")
    }

    func testWhileDiscreteUserActionIsActive_itCountsViewErrors() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .scroll,
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(0.05)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: currentTime),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(
                command: RUMCommandMock(time: currentTime),
                context: context,
                writer: writer
            ),
            "Discrete User Action should complete as it reached the timeout duration"
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(event.action.error?.count, 1)
    }

    // MARK: - Long task actions

    func testWhileDiscreteUserActionIsActive_itCountsLongTasks() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .scroll,
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(0.05)

        XCTAssertTrue(
            scope.process(
                command: RUMAddLongTaskCommand(time: currentTime, attributes: [:], duration: 1.0),
                context: context,
                writer: writer
            )
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration)

        XCTAssertFalse(
            scope.process(
                command: RUMCommandMock(time: currentTime),
                context: context,
                writer: writer
            ),
            "Discrete User Action should complete as it reached the timeout duration"
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(event.action.longTask?.count, 1)
    }

    // MARK: - Events sending callbacks

    func testGivenUserActionScopeWithEventSentCallback_whenSuccessfullySendingEvent_thenCallbackIsCalled() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        var callbackCalled = false
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .tap,
            startTime: currentTime,
            isContinuous: false,
            onActionEventSent: { _ in
                callbackCalled = true
            }
        )

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand(
                    time: currentTime,
                    globalAttributes: [:],
                    attributes: ["foo": "bar"],
                    actionType: .tap,
                    name: nil
                ),
                context: context,
                writer: writer
            )
        )

        XCTAssertNotNil(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertTrue(callbackCalled)
    }

    func testGivenUserActionScopeWithEventSentCallback_whenBypassingSendingEvent_thenCallbackIsNotCalled() {
        // swiftlint:disable trailing_closure
        let eventBuilder = RUMEventBuilder(
            eventsMapper: .mockWith(
                actionEventMapper: { event in
                    nil
                }
            )
        )

        let dependencies: RUMScopeDependencies = .mockWith(eventBuilder: eventBuilder)

        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        var callbackCalled = false
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            dependencies: dependencies,
            actionType: .tap,
            startTime: currentTime,
            isContinuous: false,
            onActionEventSent: { _ in
                callbackCalled = true
            }
        )
        // swiftlint:enable trailing_closure

        XCTAssertFalse(
            scope.process(
                command: RUMStopUserActionCommand(
                    time: currentTime,
                    globalAttributes: [:],
                    attributes: ["foo": "bar"],
                    actionType: .tap,
                    name: nil
                ),
                context: context,
                writer: writer
            )
        )

        XCTAssertNil(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertFalse(callbackCalled)
    }

    // MARK: - Actions with Frustrations

    func testGivenTapUserActionWithError_itWritesErrorTapFrustration() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .tap,
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration * 0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorObject(time: currentTime),
                context: context,
                writer: writer
            )
        )

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertEqual(event.action.frustration?.type.first, .errorTap)
    }

    func testGivenDisabledFrustration_whenTapUserActionWithError_itDoesNotWriteFrustration() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            dependencies: .mockWith(
                trackFrustrations: false
            ),
            actionType: .tap,
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration * 0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorObject(time: currentTime),
                context: context,
                writer: writer
            )
        )

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertNil(event.action.frustration)
    }

    func testGivenNotDiscreteUserActionWithError_itDoesNotWriteFrustration() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .scroll,
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration * 0.5)

        XCTAssertTrue(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorObject(time: currentTime),
                context: context,
                writer: writer
            )
        )

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertNil(event.action.frustration)
    }

    func testGivenTimedoutTapUserActionWithError_itDoesNotWriteFrustration() throws {
        var currentTime = Date()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            actionType: .tap,
            startTime: currentTime,
            isContinuous: false
        )

        currentTime.addTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration * 1.5)

        XCTAssertFalse(
            scope.process(
                command: RUMAddCurrentViewErrorCommand.mockWithErrorObject(time: currentTime),
                context: context,
                writer: writer
            )
        )

        XCTAssertFalse(
            scope.process(
                command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()),
                context: context,
                writer: writer
            )
        )

        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first)
        XCTAssertNil(event.action.frustration)
    }

    // MARK: - Updating Interaction To Next View Metric

    func testWhenActionEventIsSent_itTrackActionInINVMetric() throws {
        let actionStartTime: Date = .mockDecember15th2019At10AMUTC()
        let actionName: String = .mockRandom()
        let actionType: RUMActionType = .tap

        // Given
        let metric = INVMetricMock()
        let scope = RUMUserActionScope.mockWith(
            parent: parent,
            name: actionName,
            actionType: actionType,
            startTime: actionStartTime,
            interactionToNextViewMetric: metric
        )

        // When (action is sent)
        _ = scope.process(
            command: RUMCommandMock(time: actionStartTime + 1),
            context: context,
            writer: writer
        )
        XCTAssertFalse(writer.events(ofType: RUMActionEvent.self).isEmpty)

        // Then
        let trackedAction = try XCTUnwrap(metric.trackedActions.first)
        XCTAssertEqual(trackedAction.startTime, actionStartTime)
        XCTAssertEqual(trackedAction.endTime, actionStartTime + RUMUserActionScope.Constants.discreteActionTimeoutDuration)
        XCTAssertEqual(trackedAction.actionName, actionName)
        XCTAssertEqual(trackedAction.actionType, actionType)
        XCTAssertEqual(trackedAction.viewID, parent.context.activeViewID)
        XCTAssertEqual(metric.trackedActions.count, 1)
    }
}
