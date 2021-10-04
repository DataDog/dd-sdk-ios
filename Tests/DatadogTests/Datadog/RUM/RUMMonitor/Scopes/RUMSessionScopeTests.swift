/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMSessionScopeTests: XCTestCase {
    // MARK: - Unit Tests

    func testDefaultContext() {
        let parent: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: .mockAny(), backgroundEventTrackingEnabled: .mockAny())

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertNotEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenSessionIsSampled() {
        let parent: RUMApplicationScope = .mockWith(rumApplicationID: "rum-123")
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 0, startTime: .mockAny(), backgroundEventTrackingEnabled: .mockAny())

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenSessionExceedsMaxDuration_itGetsClosed() {
        var currentTime = Date()
        let parent = RUMContextProviderMock()
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 50, startTime: currentTime, backgroundEventTrackingEnabled: .mockAny())

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)))
    }

    func testWhenSessionIsInactiveForCertainDuration_itGetsClosed() {
        var currentTime = Date()
        let parent = RUMContextProviderMock()
        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 50, startTime: currentTime, backgroundEventTrackingEnabled: .mockAny())

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

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: .mockAny())
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

    func testWhenNoViewScope_andReceivedStartResourceCommand_itCreatesNewViewScope() {
        let parent = RUMContextProviderMock()
        let currentTime = Date()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: true)

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        _ = scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1", time: currentTime))

        XCTAssertEqual(scope.viewScopes.count, 1)
        XCTAssertNil(logOutput.recordedLog?.message)
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMViewScope.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMViewScope.Constants.backgroundViewURL)
    }

    func testWhenNoViewScope_andReceivedStartActionCommand_itCreatesNewViewScope() {
        let parent = RUMContextProviderMock()
        let currentTime = Date()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: true)

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        _ = scope.process(command: RUMStartUserActionCommand.mockWith(time: currentTime))

        XCTAssertEqual(scope.viewScopes.count, 1)
        XCTAssertNil(logOutput.recordedLog?.message)
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMViewScope.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMViewScope.Constants.backgroundViewURL)
    }

    func testWhenNoViewScope_andReceivedAddUserActionCommand_itCreatesNewViewScope() {
        let parent = RUMContextProviderMock()
        let currentTime = Date()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: true)

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        _ = scope.process(command: RUMAddUserActionCommand.mockWith(time: currentTime))

        XCTAssertEqual(scope.viewScopes.count, 1)
        XCTAssertNil(logOutput.recordedLog?.message)
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMViewScope.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMViewScope.Constants.backgroundViewURL)
    }

    func testWhenNoViewScope_andReceivedStartResourceCommand_andBackgroundDisabled_itDoesNotCreateNewViewScope() {
        let parent = RUMContextProviderMock()
        let currentTime = Date()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: false)

        _ = scope.process(command: RUMStartResourceCommand.mockWith(resourceKey: "/resource/1", time: currentTime))

        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testWhenNoViewScope_andReceivedStartActionCommand_andBackgroundDisabled_itDoesNotCreateNewViewScope() {
        let parent = RUMContextProviderMock()
        let currentTime = Date()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: false)

        _ = scope.process(command: RUMStartUserActionCommand.mockWith(time: currentTime))

        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testWhenNoViewScope_andReceivedAddUserActionCommand_andBackgroundDisabled_itDoesNotCreateNewViewScope() {
        let parent = RUMContextProviderMock()
        let currentTime = Date()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: false)

        _ = scope.process(command: RUMAddUserActionCommand.mockWith(time: currentTime))

        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testWhenActiveViewScope_andReceivingStartCommand_itDoesNotCreateNewViewScope() {
        let parent = RUMContextProviderMock()
        let currentTime = Date()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: .mockAny())
        _ = scope.process(command: generateRandomNotValidStartCommand())
        _ = scope.process(command: RUMAddUserActionCommand.mockWith(time: currentTime))
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testWhenNoActiveViewScope_andReceivingNotValidStartCommand_itDoesNotCreateNewViewScope() {
        let parent = RUMContextProviderMock()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: .mockAny())
        _ = scope.process(command: generateRandomNotValidStartCommand())
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testWhenSessionIsSampled_itDoesNotCreateViewScopes() {
        let parent = RUMContextProviderMock()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 0, startTime: Date(), backgroundEventTrackingEnabled: .mockAny())
        XCTAssertEqual(scope.viewScopes.count, 0)
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView)),
            "Sampled session should be kept until it expires or reaches the timeout."
        )
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testWhenNoActiveViewScopes_itLogsWarning() {
        // Given
        let parent = RUMContextProviderMock()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: .mockAny())
        XCTAssertEqual(scope.viewScopes.count, 0)

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        let command = generateRandomNotValidStartCommand()

        // When
        _ = scope.process(command: command)

        // Then
        XCTAssertEqual(scope.viewScopes.count, 0)
        XCTAssertEqual(
            logOutput.recordedLog?.message,
            """
            \(String(describing: command)) was detected, but no view is active. To track views automatically, try calling the
            DatadogConfiguration.Builder.trackUIKitRUMViews() method. You can also track views manually using
            the RumMonitor.startView() and RumMonitor.stopView() methods.
            """
        )
    }

    // MARK: - Private

    private func generateRandomValidStartCommand() -> RUMCommand {
       return [RUMStartUserActionCommand.mockAny(), RUMStartResourceCommand.mockAny(), RUMAddUserActionCommand.mockAny()].randomElement()!
    }

    private func generateRandomNotValidStartCommand() -> RUMCommand {
        return [RUMStopViewCommand.mockAny(), RUMStopResourceCommand.mockAny(), RUMStopUserActionCommand.mockAny(), RUMAddCurrentViewErrorCommand.mockWithErrorObject()].randomElement()!
    }
}
