/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMSessionScopeTests: XCTestCase {
    private let parent = RUMApplicationScope(dependencies: .mockWith(rumApplicationID: "rum-123"))

    func testDefaultContext() {
        let scope: RUMSessionScope = .mockWith(parent: parent)

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertNotEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testContextWhenSessionIsRejectedBySampler() {
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(sessionSampler: .mockRejectAll())
       )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertEqual(scope.context.sessionID, .nullUUID)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenSessionExceedsMaxDuration_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(sessionSampler: .mockRandom())
        )

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)))
    }

    func testWhenSessionIsInactiveForCertainDuration_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(sessionSampler: .mockRandom())
        )

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by less than the session timeout duration:
        currentTime.addTimeInterval(0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime)))

        // Push time forward by the session timeout duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime)))
    }

    func testItManagesViewScopeLifecycle() {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
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

    func testGivenAppInBackgroundAndNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: true, // BET enabled
                appStateListener: AppStateListenerMock.mockAppInBackground(since: sessionStartTime) // app in background
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: true, canStartApplicationLaunchView: .mockRandom())
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, commandTime, "Background view should be started at command time")
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMOffViewEventsHandlingRule.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMOffViewEventsHandlingRule.Constants.backgroundViewURL)
    }

    func testGivenAppInBackgroundAndNoActiveViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: true, // BET enabled
                appStateListener: AppStateListenerMock.mockAppInBackground(since: sessionStartTime) // app in background
            )
        )

        var commandTime = sessionStartTime.addingTimeInterval(1)
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: commandTime, identity: "view"))
        _ = scope.process(command: RUMStartResourceCommand.mockAny())
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: commandTime.addingTimeInterval(0.5), identity: "view"))

        XCTAssertEqual(scope.viewScopes.count, 1, "There is one view scope...")
        XCTAssertFalse(scope.viewScopes[0].isActiveView, "... but the view is not active")

        // When
        commandTime = commandTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: true, canStartApplicationLaunchView: .mockRandom())
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 2, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[1].viewStartTime, commandTime, "Background view should be started at command time")
        XCTAssertEqual(scope.viewScopes[1].viewName, RUMOffViewEventsHandlingRule.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[1].viewPath, RUMOffViewEventsHandlingRule.Constants.backgroundViewURL)
    }

    func testGivenAppInBackgroundAndNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanNotStartBackgroundView_itDoesNotCreateBackgroundScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: true, // BET enabled
                appStateListener: AppStateListenerMock.mockAppInBackground(since: sessionStartTime) // app in background
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: false, canStartApplicationLaunchView: .mockRandom())
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    func testGivenAppInAnyStateAndNoViewScopeAndBackgroundEventsTrackingDisabled_whenReceivingAnyCommand_itDoesNotCreateBackgroundScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: false, // BET disabled
                appStateListener: AppStateListenerMock.mockRandom(since: sessionStartTime) // no matter of app state (if foreground or background)
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: .mockRandom(), canStartApplicationLaunchView: false)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    // MARK: - Application Launch Events Tracking

    func testGivenAppInForegroundAndInitialSessionWithNoViewTrackedBefore_whenCommandCanStartApplicationLaunchView_itCreatesAppLaunchScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: true, // initial session
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: .mockRandom(), // no matter of BET state
                appStateListener: AppStateListenerMock.mockAppInForeground(since: sessionStartTime) // app in foreground
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: .mockRandom(), canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start application launch view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, sessionStartTime, "Application launch view should start at session start time")
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL)
    }

    func testGivenAppInForegroundAndNotInitialSessionWithNoViewTrackedBefore_whenCommandCanStartApplicationLaunchView_itDoesNotCreateAppLaunchScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: false, // not initial session
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: .mockRandom(), // no matter of BET state
                appStateListener: AppStateListenerMock.mockAppInForeground(since: sessionStartTime) // app in foreground
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: .mockRandom(), canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    func testGivenAppInAnyStateAndAnySessionWithSomeViewsTrackedBefore_whenCommandCanStartApplicationLaunchView_itDoesNotCreateAppLaunchScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: .mockRandom(), // no matter of BET state
                appStateListener: AppStateListenerMock.mockRandom(since: sessionStartTime) // no matter of app state (if foreground or background)
            )
        )

        let commandsTime = sessionStartTime.addingTimeInterval(1)
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: commandsTime, identity: "view"))
        XCTAssertFalse(scope.viewScopes.isEmpty, "There is some view scope")
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: commandsTime.addingTimeInterval(1), identity: "view"))
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let command = RUMCommandMock(time: commandsTime.addingTimeInterval(2), canStartBackgroundView: false, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    // MARK: - Background Events x Application Launch Events Tracking

    func testGivenAppInForegroundAndBETEnabledAndInitialSession_whenCommandCanStartBothApplicationLaunchAndBackgroundViews_itCreatesAppLaunchScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: true, // initial session
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: true, // BET enabled
                appStateListener: AppStateListenerMock.mockAppInForeground(since: sessionStartTime) // app in foreground
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: true, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start application launch view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, sessionStartTime, "Application launch view should start at session start time")
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL)
    }

    func testGivenAppInBackgroundAndBETEnabled_whenCommandCanStartBothApplicationLaunchAndBackgroundViews_itCreatesBackgroundScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: true, // BET enabled
                appStateListener: AppStateListenerMock.mockAppInBackground(since: sessionStartTime) // app in background
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: true, canStartApplicationLaunchView: true)
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, commandTime, "Background view should be started at command time")
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMOffViewEventsHandlingRule.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMOffViewEventsHandlingRule.Constants.backgroundViewURL)
    }

    func testGivenAppInBackgroundAndBETDisabled_whenReceivingAnyCommand_itDoesNotCreateAnyScope() {
        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                backgroundEventTrackingEnabled: false, // BET disabled
                appStateListener: AppStateListenerMock.mockAppInBackground(since: sessionStartTime) // app in background
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "No views tracked before")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: .mockRandom(), canStartApplicationLaunchView: .mockRandom())
        XCTAssertTrue(scope.process(command: command))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope (event should be ignored)")
    }

    // MARK: - Sampling

    func testWhenSessionIsRejectedBySampler_itDoesNotCreateViewScopes() {
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(sessionSampler: .mockRejectAll())
        )

        XCTAssertEqual(scope.viewScopes.count, 0)
        XCTAssertTrue(
            scope.process(command: RUMStartViewCommand.mockWith(identity: mockView)),
            "Rejected session should be kept until it expires or reaches the timeout."
        )
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    // MARK: Integration with Crash Context

    func testWhenSessionScopeIsCreated_thenItUpdatesLastRUMSessionStateInCrashContext() throws {
        let rumSessionStateProvider = ValuePublisher<RUMSessionState?>(initialValue: nil)
        let randomIsInitialSession: Bool = .mockRandom()

        // When
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: randomIsInitialSession,
            parent: parent,
            dependencies: .mockWith(
                sessionSampler: .mockRandom(), // no matter if sampled or not
                crashContextIntegration: RUMWithCrashContextIntegration(
                    rumViewEventProvider: .mockRandom(),
                    rumSessionStateProvider: rumSessionStateProvider
                )
            )
        )

        // Then
        let rumSessionStateInjectedToCrashContext = try XCTUnwrap(rumSessionStateProvider.currentValue, "It must inject session state to crash context")
        let expectedSessionState = RUMSessionState(
            sessionUUID: scope.sessionUUID.rawValue,
            isInitialSession: randomIsInitialSession,
            hasTrackedAnyView: false
        )
        XCTAssertEqual(rumSessionStateInjectedToCrashContext, expectedSessionState, "It must inject expected session state to crash context")
    }

    func testWhenSessionScopeStartsAnyView_thenItUpdatesLastRUMSessionStateInCrashContext() throws {
        let rumSessionStateProvider = ValuePublisher<RUMSessionState?>(initialValue: nil)
        let randomIsInitialSession: Bool = .mockRandom()

        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: randomIsInitialSession,
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                crashContextIntegration: RUMWithCrashContextIntegration(
                    rumViewEventProvider: .mockRandom(),
                    rumSessionStateProvider: rumSessionStateProvider
                )
            )
        )

        // When
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: sessionStartTime))
        XCTAssertFalse(scope.viewScopes.isEmpty, "Session started some view")

        // Then
        let rumSessionStateInjectedToCrashContext = try XCTUnwrap(rumSessionStateProvider.currentValue, "It must inject session state to crash context")
        let expectedSessionState = RUMSessionState(
            sessionUUID: scope.sessionUUID.rawValue,
            isInitialSession: randomIsInitialSession,
            hasTrackedAnyView: true
        )
        XCTAssertEqual(rumSessionStateInjectedToCrashContext, expectedSessionState, "It must inject expected session state to crash context")
    }

    func testWhenSessionScopeHasNoActiveView_thenItUpdatesLastRUMViewEventInCrashContext() throws {
        let rumViewEventProvider = ValuePublisher<RUMViewEvent?>(initialValue: nil)

        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                crashContextIntegration: RUMWithCrashContextIntegration(
                    rumViewEventProvider: rumViewEventProvider,
                    rumSessionStateProvider: .mockAny()
                )
            )
        )

        // When
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: sessionStartTime, identity: mockView))

        // Then
        XCTAssertNotNil(rumViewEventProvider.currentValue, "Crash context must be include rum view event, because there is an active view")

        // When
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: sessionStartTime.addingTimeInterval(1), identity: mockView))

        // Then
        XCTAssertNil(rumViewEventProvider.currentValue, "Crash context must not include rum view event, because there is no active view")
    }

    // MARK: - Usage

    func testGivenSessionWithNoActiveScope_whenReceivingRUMCommandOtherThanKeepSessionAliveCommand_itLogsWarning() throws {
        func recordLogOnReceiving(command: RUMCommand) -> LogEvent? {
            // Given
            let scope: RUMSessionScope = .mockWith(
                parent: parent,
                startTime: Date()
            )
            XCTAssertEqual(scope.viewScopes.count, 0)

            let previousUserLogger = userLogger
            defer { userLogger = previousUserLogger }

            let logOutput = LogOutputMock()
            userLogger = .mockWith(logOutput: logOutput)

            // When
            _ = scope.process(command: command)

            // Then
            XCTAssertEqual(scope.viewScopes.count, 0)
            return logOutput.recordedLog
        }

        let randomCommand = RUMCommandMock(time: Date(), canStartBackgroundView: false, canStartApplicationLaunchView: false)
        let randomCommandLog = try XCTUnwrap(recordLogOnReceiving(command: randomCommand))
        XCTAssertEqual(randomCommandLog.status, .warn)
        XCTAssertEqual(
            randomCommandLog.message,
            """
            \(String(describing: randomCommand)) was detected, but no view is active. To track views automatically, try calling the
            DatadogConfiguration.Builder.trackUIKitRUMViews() method. You can also track views manually using
            the RumMonitor.startView() and RumMonitor.stopView() methods.
            """
        )

        let keepAliveCommand = RUMKeepSessionAliveCommand(time: Date(), attributes: [:])
        let keepAliveLog = recordLogOnReceiving(command: keepAliveCommand)
        XCTAssertNil(keepAliveLog, "It shouldn't log warning when receiving `RUMKeepSessionAliveCommand`")
    }
}
