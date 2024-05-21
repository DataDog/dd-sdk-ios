/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class RUMSessionScopeTests: XCTestCase {
    let context: DatadogContext = .mockAny()
    let writer = FileWriterMock()

    private lazy var parent = RUMApplicationScope(
        dependencies: .mockWith(rumApplicationID: "rum-123")
    )

    func testDefaultContext() {
        let scope: RUMSessionScope = .mockWith(parent: parent)

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertNotEqual(scope.context.sessionID, .nullUUID)
        XCTAssertTrue(scope.context.isSessionActive)
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

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Push time forward by the max session duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testWhenSessionIsInactiveForCertainDuration_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(sessionSampler: .mockRandom())
        )

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Push time forward by less than the session timeout duration:
        currentTime.addTimeInterval(0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Push time forward by the session timeout duration:
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testWhenSessionReceivesInteractiveEvent_itStaysAlive() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(sessionSampler: .mockRandom())
        )

        for _ in 0...10 {
            // Push time forward by less than the session timeout duration:
            currentTime.addTimeInterval(0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)
            XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime, isUserInteraction: true), context: context, writer: writer))
        }

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testWhenSessionReceivesNonInteractiveEvent_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(sessionSampler: .mockRandom())
        )

        for _ in 0...8 {
            // Push time forward by less than the session timeout duration:
            currentTime.addTimeInterval(0.1 * RUMSessionScope.Constants.sessionTimeoutDuration)
            XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime, isUserInteraction: false), context: context, writer: writer))
        }

        currentTime.addTimeInterval(0.1 * RUMSessionScope.Constants.sessionTimeoutDuration)
        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testItManagesViewScopeLifecycle() {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        XCTAssertEqual(scope.viewScopes.count, 0)

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        XCTAssertEqual(scope.viewScopes.count, 1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        XCTAssertEqual(scope.viewScopes.count, 0)

        _ = scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        XCTAssertEqual(scope.viewScopes.count, 1)
        _ = scope.process(command: RUMStopViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer)
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    func testWhenViewStarts_itUpdatesTheViewCache() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let ttl: TimeInterval = .mockRandom(min: 2, max: 10)
        let viewCache = ViewCache(ttl: ttl)

        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: dateProvider.now,
            dependencies: .mockWith(viewCache: viewCache)
        )

        // When - starting a view
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: dateProvider.now,
                attributes: ["foo": "bar 2"],
                identity: .mockRandomString()
            ),
            context: context,
            writer: writer
        )

        dateProvider.advance(bySeconds: 1)

        // Then - the view is added to the cache
        let firstViewID = try XCTUnwrap(scope.viewScopes.first?.context.activeViewID?.toRUMDataFormat)
        XCTAssertEqual(viewCache.lastView(before: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds), firstViewID)

        // When - updating the view
        dateProvider.advance(bySeconds: ttl)

        _ = scope.process(
            command: RUMStopViewCommand.mockWith(
                time: dateProvider.now
            ),
            context: context,
            writer: writer
        )

        // Then - it updates the timestamp in cache
        XCTAssertEqual(viewCache.lastView(before: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds), firstViewID)
    }

    // MARK: - Background Events Tracking

    func testGivenAppInBackgroundAndNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockAppInBackground(since: sessionStartTime) // app in background

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: true // BET enabled
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: true)
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 1, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[0].viewStartTime, commandTime, "Background view should be started at command time")
        XCTAssertEqual(scope.viewScopes[0].viewName, RUMOffViewEventsHandlingRule.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[0].viewPath, RUMOffViewEventsHandlingRule.Constants.backgroundViewURL)
    }

    func testGivenAppInBackgroundAndNoActiveViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanStartBackgroundView_itCreatesBackgroundScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockAppInBackground(since: sessionStartTime) // app in background

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: true // BET enabled
            )
        )

        var commandTime = sessionStartTime.addingTimeInterval(1)
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: commandTime, identity: ViewIdentifier("view")), context: context, writer: writer)
        _ = scope.process(command: RUMStartResourceCommand.mockAny(), context: context, writer: writer)
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: commandTime.addingTimeInterval(0.5), identity: ViewIdentifier("view")), context: context, writer: writer)

        XCTAssertEqual(scope.viewScopes.count, 1, "There is one view scope...")
        XCTAssertFalse(scope.viewScopes[0].isActiveView, "... but the view is not active")

        // When
        commandTime = commandTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: true)
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertEqual(scope.viewScopes.count, 2, "It should start background view scope")
        XCTAssertEqual(scope.viewScopes[1].viewStartTime, commandTime, "Background view should be started at command time")
        XCTAssertEqual(scope.viewScopes[1].viewName, RUMOffViewEventsHandlingRule.Constants.backgroundViewName)
        XCTAssertEqual(scope.viewScopes[1].viewPath, RUMOffViewEventsHandlingRule.Constants.backgroundViewURL)
    }

    func testGivenAppInBackgroundAndNoViewScopeAndBackgroundEventsTrackingEnabled_whenCommandCanNotStartBackgroundView_itDoesNotCreateBackgroundScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockAppInBackground(since: sessionStartTime) // app in background

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: true // BET enabled
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: false)
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    func testGivenAppInAnyStateAndNoViewScopeAndBackgroundEventsTrackingDisabled_whenReceivingAnyCommand_itDoesNotCreateBackgroundScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockRandom(since: sessionStartTime) // no matter of app state (if foreground or background)

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: .mockRandom(), // no matter if initial session or not
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: false // BET disabled
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: .mockRandom())
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
    }

    // MARK: - Application Launch Events Tracking

    func testGivenAppInForegroundAndNotInitialSessionWithNoViewTrackedBefore_itDoesNotCreateAppLaunchScope() {
        // Given
        let sessionStartTime = Date()

        var context = self.context
        context.applicationStateHistory = .mockAppInForeground(since: sessionStartTime) // app in foreground

        let scope: RUMSessionScope = .mockWith(
            isInitialSession: false, // not initial session
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                trackBackgroundEvents: .mockRandom() // no matter of BET state
            )
        )
        XCTAssertTrue(scope.viewScopes.isEmpty, "There is no view scope")

        // When
        let commandTime = sessionStartTime.addingTimeInterval(1)
        let command = RUMCommandMock(time: commandTime, canStartBackgroundView: .mockRandom())
        XCTAssertTrue(scope.process(command: command, context: context, writer: writer))

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty, "It should not start any view scope")
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
            scope.process(command: RUMStartViewCommand.mockWith(identity: .mockViewIdentifier()), context: context, writer: writer),
            "Rejected session should be kept until it expires or reaches the timeout."
        )
        XCTAssertEqual(scope.viewScopes.count, 0)
    }

    // MARK: - Updating Fatal Error Context

    func testWhenSessionScopeIsCreated_itUpdatesFatalErrorContextWithSessionState() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()
        let randomIsInitialSession: Bool = .mockRandom()
        let randomIsReplayBeingRecorded: Bool? = .mockRandom()

        // When
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: randomIsInitialSession,
            parent: parent,
            dependencies: .mockWith(
                featureScope: featureScope,
                sessionSampler: Bool.random() ? .mockKeepAll() : .mockRejectAll(), // no matter if sampled or not,
                fatalErrorContext: fatalErrorContext
            ),
            hasReplay: randomIsReplayBeingRecorded
        )

        // Then
        let expectedSessionState = RUMSessionState(
            sessionUUID: scope.sessionUUID.rawValue,
            isInitialSession: randomIsInitialSession,
            hasTrackedAnyView: false,
            didStartWithReplay: randomIsReplayBeingRecorded
        )
        let actualSessionState = try XCTUnwrap(fatalErrorContext.sessionState)
        XCTAssertEqual(actualSessionState, expectedSessionState)
    }

    func testWhenSessionScopeStartsAnyView_itUpdatesFatalErrorContextWithSessionState() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()
        let randomIsInitialSession: Bool = .mockRandom()
        let randomIsReplayBeingRecorded: Bool? = .mockRandom()

        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: randomIsInitialSession,
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                featureScope: featureScope,
                fatalErrorContext: fatalErrorContext
            ),
            hasReplay: randomIsReplayBeingRecorded
        )

        // When
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: sessionStartTime), context: context, writer: writer)

        XCTAssertFalse(scope.viewScopes.isEmpty, "Session started some view")

        // Then
        let expectedSessionState = RUMSessionState(
            sessionUUID: scope.sessionUUID.rawValue,
            isInitialSession: randomIsInitialSession,
            hasTrackedAnyView: true,
            didStartWithReplay: randomIsReplayBeingRecorded
        )
        let actualSessionState = try XCTUnwrap(fatalErrorContext.sessionState)
        XCTAssertEqual(actualSessionState, expectedSessionState)
    }

    func testWhenSessionScopeHasNoActiveView_itUpdatesFatalErrorContextWithView() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()

        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: sessionStartTime,
            dependencies: .mockWith(
                featureScope: featureScope,
                fatalErrorContext: fatalErrorContext
            )
        )

        // When
        let command = RUMStartViewCommand.mockWith(time: sessionStartTime, identity: .mockViewIdentifier(), name: "ActiveView")
        _ = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertEqual(fatalErrorContext.view?.view.name, "ActiveView")

        // When
        _ = scope.process(command: RUMStopViewCommand.mockWith(time: sessionStartTime.addingTimeInterval(1), identity: .mockViewIdentifier()), context: context, writer: writer)

        // Then
        XCTAssertNil(fatalErrorContext.view)
    }

    func testWhenSessionEnds_itUpdatesFatalErrorContextWithView() throws {
        let featureScope = FeatureScopeMock()
        let fatalErrorContext = FatalErrorContextNotifierMock()

        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date(),
            dependencies: .mockWith(
                featureScope: featureScope,
                fatalErrorContext: fatalErrorContext
            )
        )

        let command = RUMStartViewCommand.mockWith(time: Date(), identity: .mockViewIdentifier(), name: "ActiveView")

        // When
        _ = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertEqual(fatalErrorContext.view?.view.name, "ActiveView")

        // When
        _ = scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer)

        // Then
        XCTAssertNil(fatalErrorContext.view)
    }

    // MARK: - Stopping Sessions

    func testGivenActiveSession_whenStopSessionEvent_itSetsSessionActiveFalse() {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )

        // When
        let command = RUMStopSessionCommand.mockWith(time: Date())

        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertFalse(scope.isActive)
        XCTAssertFalse(result)
    }

    func testGivenStoppedSession_itUpdatesContext() {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer)

        // When
        let context = scope.context

        XCTAssertFalse(context.isSessionActive)
    }

    func testGivenActiveSessionWithActiveView_whenStopSessionEvent_itStopsTheActiveView() throws {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: Date()), context: context, writer: writer)
        let view = try XCTUnwrap(scope.viewScopes.first)

        // When
        let command = RUMStopSessionCommand.mockWith(time: Date())

        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertFalse(view.isActiveView)
        XCTAssertFalse(result)
    }

    func testWhenSessionScopeHasViewsWithPendingResources_whenStopSession_itKeepsTheScope() throws {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        XCTAssertTrue(scope.process(command: RUMStartViewCommand.mockWith(time: Date()), context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMStartResourceCommand.mockWith(time: Date()), context: context, writer: writer))
        let view = try XCTUnwrap(scope.viewScopes.first)

        // When
        let command = RUMStopSessionCommand(time: Date())
        let keep = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertFalse(scope.isActive)
        XCTAssertFalse(view.isActiveView)
        XCTAssertTrue(keep, "The scope should be kept because it has pending events")
    }

    func testWhenSessionScopeHasViewsWithPendingResources_itClosesTheScopeWhenResourcesFinish() throws {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: Date()), context: context, writer: writer)
        let startResourceCommand = RUMStartResourceCommand.mockWith(time: Date())
        XCTAssertTrue(scope.process(command: startResourceCommand, context: context, writer: writer))
        XCTAssertTrue(scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer))

        // When
        let command = RUMStopResourceCommand.mockWith(resourceKey: startResourceCommand.resourceKey, time: Date())
        let keep = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertFalse(scope.isActive)
        XCTAssertFalse(keep, "The scope should be closed")
    }

    func testWhenScopeEnded_itDoesNotStartNewViews() throws {
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer)

        // When
        let command = RUMStartViewCommand.mockWith(time: Date())
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty)
        XCTAssertFalse(result)
    }

    func testWhenScopeEnded_itDoesNotCreateAnApplicationLaunchView() {
        // Note - This should happen because the application context should prevent against
        // it, but just in case
        // Given
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: Date()
        )
        _ = scope.process(command: RUMStopSessionCommand.mockWith(time: Date()), context: context, writer: writer)

        // When
        let command = RUMApplicationStartCommand(time: Date(), attributes: [:])
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty)
        XCTAssertFalse(result)
    }

    // MARK: - Usage

    func testGivenSessionWithNoActiveScope_whenReceivingRUMCommandOtherThanKeepSessionAliveCommand_itLogsWarning() throws {
        func recordWarningOnReceiving(command: RUMCommand) -> String? {
            // Given
            let scope: RUMSessionScope = .mockWith(
                parent: parent,
                startTime: Date()
            )
            XCTAssertEqual(scope.viewScopes.count, 0)

            let dd = DD.mockWith(logger: CoreLoggerMock())
            defer { dd.reset() }

            // When
            _ = scope.process(command: command, context: context, writer: writer)

            // Then
            XCTAssertEqual(scope.viewScopes.count, 0)
            return dd.logger.warnLog?.message
        }

        let randomCommand = RUMCommandMock(time: Date(), canStartBackgroundView: false)
        let randomCommandLog = try XCTUnwrap(recordWarningOnReceiving(command: randomCommand))
        XCTAssertEqual(
            randomCommandLog,
            """
            \(String(describing: randomCommand)) was detected, but no view is active. To track views automatically, try calling the
            DatadogConfiguration.Builder.trackUIKitRUMViews() method. You can also track views manually using
            the RumMonitor.startView() and RumMonitor.stopView() methods.
            """
        )

        let keepAliveCommand = RUMKeepSessionAliveCommand(time: Date(), attributes: [:])
        let keepAliveLog = recordWarningOnReceiving(command: keepAliveCommand)
        XCTAssertNil(keepAliveLog, "It shouldn't log warning when receiving `RUMKeepSessionAliveCommand`")
    }
}
