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

    // MARK: - Background Events Tracking

    func testGivenNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: true
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMSessionScope.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMSessionScope.Constants.backgroundViewURL)
    }

    func testGivenNoActiveViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let currentTime = Date()
        let parent: RUMApplicationScope = .mockAny()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: true
        )
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: currentTime, identity: "view"))
        _ = scope.process(command: RUMStartResourceCommand.mockAny())
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: currentTime.addingTimeInterval(1), identity: "view"))

        XCTAssertEqual(scope.viewScopes.count, 1, "It has one view scope...")
        XCTAssertFalse(scope.viewScopes[0].isActiveView, "... but the view is not active")

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 2, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[1].viewStartTime, currentTime)
        XCTAssertEqual(scope.viewScopes[1].viewName, RUMSessionScope.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[1].viewPath, RUMSessionScope.Constants.backgroundViewURL)
    }

    func testGivenNoViewScopeAndBackgroundEventsTrackingDisabled_whenCommandCanStartBackgroundView_itDoesNotCreateBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: false
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It shoul not start any view scope")
    }

    func testGivenNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanNotStartBackgroundView_itDoesNotCreateBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: true
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: false)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    func testGivenNoViewScopeAndBackgroundEventsTrackingDisabled_whenCommandCanNotStartBackgroundView_itDoesNotCreateBackgroundScope() {
        // Given
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            samplingRate: 100,
            startTime: currentTime,
            backgroundEventTrackingEnabled: false
        )
        XCTAssertTrue(scope.viewScopes.isEmpty)

        // When
        let command = RUMCommandMock(time: currentTime, canStartBackgroundView: false)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    // MARK: - Sampling

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

    // MARK: - Usage

    func testWhenNoActiveViewScopes_itLogsWarning() {
        // Given
        let parent = RUMContextProviderMock()

        let scope = RUMSessionScope(parent: parent, dependencies: .mockAny(), samplingRate: 100, startTime: Date(), backgroundEventTrackingEnabled: .mockAny())
        XCTAssertEqual(scope.viewScopes.count, 0)

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let logOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: logOutput)

        let command = RUMCommandMock(time: Date(), canStartBackgroundView: false)

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
}
