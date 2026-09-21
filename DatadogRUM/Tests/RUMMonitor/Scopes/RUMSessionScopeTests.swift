/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal
@testable import DatadogRUM
@testable import TestUtilities

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
            dependencies: .mockWith(samplingRate: 0)
       )

        XCTAssertEqual(scope.context.rumApplicationID, "rum-123")
        XCTAssertFalse(scope.sampler.isSampled)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.context.activeViewPath)
        XCTAssertNil(scope.context.activeUserActionID)
    }

    func testWhenSessionExceedsMaxDuration_itGetsClosed() {
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom())
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
            dependencies: .mockWith(samplingRate: .mockRandom())
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
            dependencies: .mockWith(samplingRate: .mockRandom())
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
            dependencies: .mockWith(samplingRate: .mockRandom())
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
        let viewCache = ViewCache(dateProvider: SystemDateProvider(), ttl: ttl)

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
        XCTAssertEqual(viewCache.lastView(before: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds), firstViewID)

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
        XCTAssertEqual(viewCache.lastView(before: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds), firstViewID)
    }

    // MARK: - Background Events Tracking

    #if !os(macOS)
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
    #endif

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
            dependencies: .mockWith(samplingRate: 0)
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
        let randomIsReplayBeingRecorded: Bool = .mockRandom()
        let randomSampleRate: SampleRate = .mockRandom(min: 0, max: 100)

        // When
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: randomIsInitialSession,
            parent: parent,
            context: .mockWith(
                additionalContext: [
                    SessionReplayCoreContext.HasReplay(value: randomIsReplayBeingRecorded)
                ]
            ),
            dependencies: .mockWith(
                featureScope: featureScope,
                samplingRate: randomSampleRate,
                fatalErrorContext: fatalErrorContext
            )
        )

        // Then
        let expectedSessionState = RUMSessionState(
            sessionUUID: scope.sessionUUID.rawValue,
            isSampled: DeterministicSampler(
                uuid: scope.sessionUUID.rawValue,
                samplingRate: randomSampleRate
            ).sample(),
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
        let randomIsReplayBeingRecorded: Bool = .mockRandom()

        // Given
        let sessionStartTime = Date()
        let scope: RUMSessionScope = .mockWith(
            isInitialSession: randomIsInitialSession,
            parent: parent,
            startTime: sessionStartTime,
            context: .mockWith(
                additionalContext: [
                    SessionReplayCoreContext.HasReplay(value: randomIsReplayBeingRecorded)
                ]
            ),
            dependencies: .mockWith(
                featureScope: featureScope,
                fatalErrorContext: fatalErrorContext
            )
        )

        // When
        _ = scope.process(command: RUMStartViewCommand.mockWith(time: sessionStartTime), context: context, writer: writer)

        XCTAssertFalse(scope.viewScopes.isEmpty, "Session started some view")

        // Then
        let expectedSessionState = RUMSessionState(
            sessionUUID: scope.sessionUUID.rawValue,
            isSampled: true,
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
        let command: RUMStopSessionCommand = .mockWith(time: Date())
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
        let command = RUMApplicationStartCommand(time: Date(), globalAttributes: [:], attributes: [:])
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(scope.viewScopes.isEmpty)
        XCTAssertFalse(result)
    }

    // MARK: - Usage

    func testGivenSessionWithNoActiveScope_whenReceivingRUMCommand_itLogsWarning() throws {
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
            \(String(describing: randomCommand)) was detected, but no view is active. To track views automatically, configure
            `RUM.Configuration.uiKitViewsPredicate` or use `.trackRUMView()` modifier in SwiftUI. You can also track views manually
            with `RUMMonitor.shared().startView()` and `RUMMonitor.shared().stopView()`.
            """
        )
    }

    func testGivenSessionWithNoActiveScope_whenReceivingSilentCommand_itDoesNotLogWarning() throws {
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

        let silentCommands: [RUMCommand] = [
            RUMKeepSessionAliveCommand(time: Date(), attributes: [:]),
            RUMUpdatePerformanceMetric(metric: .flutterBuildTime, value: 1.0, time: Date(), attributes: [:])
        ]

        for command in silentCommands {
            let log = recordWarningOnReceiving(command: command)
            XCTAssertNil(log, "It shouldn't log warning when receiving silent command: \(command)")
        }
    }

    // MARK: - Feature Operation Integration Tests

    func testProcessesFeatureOperationCommand_DelegatesToManager() {
        // Given
        let command: RUMOperationStepVitalCommand = .mockAny()
        let scope: RUMSessionScope = .mockWith(parent: parent)

        // When
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - App launch metrics

    func testWhenSessionScopeReceivesTTIDCommand_itIsProcessedAccordingly() {
        // Given
        let command: RUMTimeToInitialDisplayCommand = .mockAny()
        let scope: RUMSessionScope = .mockWith(parent: parent)

        // When
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(result)
    }

    func testWhenSessionScopeReceivesTTFDCommand_itIsProcessedAccordingly() {
        // Given
        let command: RUMTimeToFullDisplayCommand = .mockAny()
        let scope: RUMSessionScope = .mockWith(parent: parent)

        // When
        let result = scope.process(command: command, context: context, writer: writer)

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - Timeseries collector lifecycle

    func testWhenSessionScopeIsCreated_itStartsTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()

        // When
        let _: RUMSessionScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // Then
        XCTAssertEqual(collector.startCallCount, 1)
        XCTAssertEqual(collector.stopCallCount, 0)
    }

    func testWhenSessionExpiresDueToMaxDuration_itStopsTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // When — push past the max session duration
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
        _ = scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer)

        // Then
        XCTAssertEqual(collector.stopCallCount, 1)
    }

    func testWhenSessionExpiresDueToInactivity_itStopsTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        var currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        _ = scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer)

        // When — push past the session inactivity timeout
        currentTime.addTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration)
        _ = scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer)

        // Then
        XCTAssertEqual(collector.stopCallCount, 1)
    }

    func testWhenSessionScopeStartsNewSession_itStartsCollectorWithCorrectSessionID() {
        // Given
        let collector = TimeseriesCollectorSpy()
        let applicationID = "test-app-id"

        // When
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            dependencies: .mockWith(
                rumApplicationID: applicationID,
                timeseriesCollector: collector
            )
        )

        // Then
        XCTAssertEqual(collector.startCallCount, 1)
        XCTAssertEqual(collector.lastStartedApplicationID, applicationID)
        XCTAssertNotNil(collector.lastStartedSessionID, "Session ID should be set")
        XCTAssertFalse(collector.lastStartedSessionID?.isEmpty ?? true)
        XCTAssertEqual(collector.lastStartedSessionType, .user)
    }

    func testWhenSessionIsNotSampled_itDoesNotStartTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()

        // When
        _ = RUMSessionScope.mockWith(
            parent: parent,
            dependencies: .mockWith(samplingRate: 0, timeseriesCollector: collector)
        )

        // Then
        XCTAssertEqual(collector.startCallCount, 0)
    }

    #if !os(macOS)
    func testWhenSessionIsCreatedInBackground_itStartsThenPausesTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        let sessionStartTime = Date()
        var context = self.context
        context.applicationStateHistory = .mockAppInBackground(since: sessionStartTime)

        // When
        _ = RUMSessionScope.mockWith(
            parent: parent,
            startTime: sessionStartTime,
            context: context,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // Then
        XCTAssertEqual(collector.startCallCount, 1)
        XCTAssertEqual(collector.pauseCallCount, 1)
    }
    #endif

    func testWhenAppEntersBackground_itPausesTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // When
        _ = scope.process(
            command: RUMHandleAppLifecycleEventCommand(time: currentTime, event: .didEnterBackground),
            context: context,
            writer: writer
        )

        // Then
        XCTAssertEqual(collector.pauseCallCount, 1)
        XCTAssertEqual(collector.resumeCallCount, 0)
    }

    func testWhenAppEntersForeground_itResumesTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        let currentTime = Date()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(timeseriesCollector: collector)
        )

        // When
        _ = scope.process(
            command: RUMHandleAppLifecycleEventCommand(time: currentTime, event: .willEnterForeground),
            context: context,
            writer: writer
        )

        // Then
        XCTAssertEqual(collector.resumeCallCount, 1)
        XCTAssertEqual(collector.pauseCallCount, 0)
    }

    // MARK: - View Cache Lifetime

    func testGivenLongLivedView_whenNextViewStarts_itRetainsDelayedContainerUntilInactiveTTL() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let inactiveTTL: TimeInterval = 10
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: inactiveTTL)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        let scope = makeSessionScope(
            viewCache: viewCache,
            startTime: start,
            context: sessionContext
        )

        let viewAID = try startView(
            in: scope,
            identity: ViewIdentifier("A"),
            at: start,
            dateProvider: dateProvider,
            context: sessionContext
        )
        let navigation = start.addingTimeInterval(100)
        let viewBID = try startView(
            in: scope,
            identity: ViewIdentifier("B"),
            at: navigation,
            dateProvider: dateProvider,
            context: sessionContext
        )
        viewCache.insert(
            id: "legacy-inactive",
            timestamp: milliseconds(start.addingTimeInterval(50)),
            hasReplay: true
        )

        dateProvider.now = navigation.addingTimeInterval(inactiveTTL)
        XCTAssertEqual(viewCache.lastView(before: milliseconds(navigation)), viewAID)

        let afterRetention = navigation.addingTimeInterval(inactiveTTL + 0.01)
        dateProvider.now = afterRetention
        XCTAssertNil(viewCache.lastView(before: milliseconds(navigation)))
        XCTAssertEqual(
            viewCache.lastView(before: milliseconds(navigation.addingTimeInterval(0.01))),
            viewBID
        )
    }

    func testGivenStoppedView_whenRetentionExpires_itReleasesCachedContainer() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let inactiveTTL: TimeInterval = 10
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: inactiveTTL)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        let scope = makeSessionScope(
            viewCache: viewCache,
            startTime: start,
            context: sessionContext
        )
        let viewAID = try startView(
            in: scope,
            identity: ViewIdentifier("A"),
            at: start,
            dateProvider: dateProvider,
            context: sessionContext
        )

        let resourceStart = start.addingTimeInterval(0.5)
        dateProvider.now = resourceStart
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(
                resourceKey: "retained-resource",
                time: resourceStart
            ),
            context: sessionContext,
            writer: writer
        )

        let stop = start.addingTimeInterval(1)
        dateProvider.now = stop
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(time: stop, identity: ViewIdentifier("A")),
            context: sessionContext,
            writer: writer
        )
        let laterCleanup = stop.addingTimeInterval(inactiveTTL - 0.01)
        dateProvider.now = laterCleanup
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(
                time: laterCleanup,
                identity: ViewIdentifier("A")
            ),
            context: sessionContext,
            writer: writer
        )

        XCTAssertEqual(viewCache.lastView(before: milliseconds(laterCleanup)), viewAID)
        let afterRetention = stop.addingTimeInterval(inactiveTTL + 0.01)
        dateProvider.now = afterRetention
        XCTAssertNil(viewCache.lastView(before: milliseconds(afterRetention)))
    }

    func testGivenStoppedSession_whenRetentionExpires_itReleasesCachedContainer() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let inactiveTTL: TimeInterval = 10
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: inactiveTTL)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        let scope = makeSessionScope(
            viewCache: viewCache,
            startTime: start,
            context: sessionContext
        )
        let viewAID = try startView(
            in: scope,
            identity: ViewIdentifier("A"),
            at: start,
            dateProvider: dateProvider,
            context: sessionContext
        )

        let stop = start.addingTimeInterval(1)
        dateProvider.now = stop
        XCTAssertFalse(
            scope.process(
                command: RUMStopSessionCommand.mockWith(time: stop),
                context: sessionContext,
                writer: writer
            )
        )

        let beforeRetention = stop.addingTimeInterval(inactiveTTL - 0.01)
        dateProvider.now = beforeRetention
        XCTAssertEqual(viewCache.lastView(before: milliseconds(beforeRetention)), viewAID)
        let afterRetention = stop.addingTimeInterval(inactiveTTL + 0.01)
        dateProvider.now = afterRetention
        XCTAssertNil(viewCache.lastView(before: milliseconds(afterRetention)))
    }

    func testGivenTimedOutSession_whenRetentionExpires_itReleasesCachedContainer() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let inactiveTTL: TimeInterval = 10
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: inactiveTTL)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        let scope = makeSessionScope(
            viewCache: viewCache,
            startTime: start,
            context: sessionContext
        )
        let viewAID = try startView(
            in: scope,
            identity: ViewIdentifier("A"),
            at: start,
            dateProvider: dateProvider,
            context: sessionContext
        )

        let timeout = start.addingTimeInterval(RUMSessionScope.Constants.sessionTimeoutDuration + 0.001)
        dateProvider.now = timeout
        XCTAssertFalse(
            scope.process(
                command: RUMCommandMock(time: timeout),
                context: sessionContext,
                writer: writer
            )
        )
        XCTAssertEqual(scope.endReason, .timeOut)

        let beforeRetention = timeout.addingTimeInterval(inactiveTTL - 0.01)
        dateProvider.now = beforeRetention
        XCTAssertEqual(viewCache.lastView(before: milliseconds(beforeRetention)), viewAID)
        let afterRetention = timeout.addingTimeInterval(inactiveTTL + 0.01)
        dateProvider.now = afterRetention
        XCTAssertNil(viewCache.lastView(before: milliseconds(afterRetention)))
    }

    func testGivenExpiredSession_whenRetentionExpires_itReleasesCachedContainer() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let inactiveTTL: TimeInterval = 10
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: inactiveTTL)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        let scope = makeSessionScope(
            viewCache: viewCache,
            startTime: start,
            context: sessionContext
        )
        let viewAID = try startView(
            in: scope,
            identity: ViewIdentifier("A"),
            at: start,
            dateProvider: dateProvider,
            context: sessionContext
        )

        let expiration = start.addingTimeInterval(RUMSessionScope.Constants.sessionMaxDuration + 0.001)
        let interactionInterval = RUMSessionScope.Constants.sessionTimeoutDuration - 1
        var interaction = start
        while interaction.addingTimeInterval(interactionInterval) < expiration {
            interaction = interaction.addingTimeInterval(interactionInterval)
            dateProvider.now = interaction
            XCTAssertTrue(
                scope.process(
                    command: RUMCommandMock(time: interaction, isUserInteraction: true),
                    context: sessionContext,
                    writer: writer
                )
            )
        }

        dateProvider.now = expiration
        XCTAssertFalse(
            scope.process(
                command: RUMCommandMock(time: expiration, isUserInteraction: true),
                context: sessionContext,
                writer: writer
            )
        )
        XCTAssertEqual(scope.endReason, .maxDuration)

        let beforeRetention = expiration.addingTimeInterval(inactiveTTL - 0.01)
        dateProvider.now = beforeRetention
        XCTAssertEqual(viewCache.lastView(before: milliseconds(beforeRetention)), viewAID)
        let afterRetention = expiration.addingTimeInterval(inactiveTTL + 0.01)
        dateProvider.now = afterRetention
        XCTAssertNil(viewCache.lastView(before: milliseconds(afterRetention)))
    }

    func testGivenReleasedSession_whenRetentionExpires_itReleasesCachedContainer() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let inactiveTTL: TimeInterval = 10
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: inactiveTTL)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        let release = start.addingTimeInterval(1)
        let viewAID: String
        weak var releasedScope: RUMSessionScope?

        do {
            let scope = makeSessionScope(
                viewCache: viewCache,
                startTime: start,
                context: sessionContext
            )
            releasedScope = scope
            viewAID = try startView(
                in: scope,
                identity: ViewIdentifier("A"),
                at: start,
                dateProvider: dateProvider,
                context: sessionContext
            )
            dateProvider.now = release
            XCTAssertEqual(viewCache.lastView(before: milliseconds(release)), viewAID)
        }

        XCTAssertNil(releasedScope)
        let beforeRetention = release.addingTimeInterval(inactiveTTL - 0.01)
        dateProvider.now = beforeRetention
        XCTAssertEqual(viewCache.lastView(before: milliseconds(beforeRetention)), viewAID)
        let afterRetention = release.addingTimeInterval(inactiveTTL + 0.01)
        dateProvider.now = afterRetention
        XCTAssertNil(viewCache.lastView(before: milliseconds(afterRetention)))
    }

    func testGivenRestoredSession_whenViewTransfers_itCachesFreshContainer() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: 10)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        var oldScope: RUMSessionScope? = makeSessionScope(
            viewCache: viewCache,
            startTime: start,
            context: sessionContext
        )
        let oldViewID = try startView(
            in: try XCTUnwrap(oldScope),
            identity: ViewIdentifier("A"),
            at: start,
            dateProvider: dateProvider,
            context: sessionContext
        )

        let restoration = start.addingTimeInterval(1)
        dateProvider.now = restoration
        let restoredScope = RUMSessionScope(
            from: try XCTUnwrap(oldScope),
            startTime: restoration,
            startPrecondition: .userAppLaunch,
            context: sessionContext,
            transferActiveView: true,
            applicationState: .mockAny()
        )
        let restoredViewID = try XCTUnwrap(restoredScope.viewScopes.last).viewUUID.toRUMDataFormat

        weak var releasedOldScope: RUMSessionScope? = oldScope
        let oldRelease = restoration.addingTimeInterval(0.5)
        dateProvider.now = oldRelease
        oldScope = nil

        XCTAssertNil(releasedOldScope)
        XCTAssertNotEqual(restoredViewID, oldViewID)
        let afterRetention = oldRelease.addingTimeInterval(10.01)
        dateProvider.now = afterRetention
        XCTAssertEqual(viewCache.lastView(before: milliseconds(afterRetention)), restoredViewID)
    }

    func testGivenSessionViewCache_whenCapacityIsExceeded_itPreservesNewestViews() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: 100, capacity: 2)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        let scope = makeSessionScope(
            viewCache: viewCache,
            startTime: start,
            context: sessionContext
        )

        let viewAID = try startView(
            in: scope,
            identity: ViewIdentifier("A"),
            at: start,
            dateProvider: dateProvider,
            context: sessionContext
        )
        let viewBStart = start.addingTimeInterval(1)
        let viewBID = try startView(
            in: scope,
            identity: ViewIdentifier("B"),
            at: viewBStart,
            dateProvider: dateProvider,
            context: sessionContext
        )
        let viewCStart = start.addingTimeInterval(2)
        let viewCID = try startView(
            in: scope,
            identity: ViewIdentifier("C"),
            at: viewCStart,
            dateProvider: dateProvider,
            context: sessionContext
        )

        XCTAssertNil(viewCache.lastView(before: milliseconds(viewBStart)))
        XCTAssertEqual(viewCache.lastView(before: milliseconds(viewCStart)), viewBID)
        XCTAssertEqual(
            viewCache.lastView(before: milliseconds(viewCStart.addingTimeInterval(0.001))),
            viewCID
        )
        XCTAssertNotEqual(viewAID, viewBID)
    }

    private func makeSessionScope(
        viewCache: ViewCache,
        startTime: Date,
        context: DatadogContext
    ) -> RUMSessionScope {
        .mockWith(
            parent: parent,
            startTime: startTime,
            context: context,
            dependencies: .mockWith(samplingRate: 100, viewCache: viewCache)
        )
    }

    private func startView(
        in scope: RUMSessionScope,
        identity: ViewIdentifier,
        at time: Date,
        dateProvider: DateProviderMock,
        context: DatadogContext
    ) throws -> String {
        dateProvider.now = time
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: time,
                identity: identity,
                name: "view",
                path: "view"
            ),
            context: context,
            writer: writer
        )
        return try XCTUnwrap(scope.viewScopes.last).viewUUID.toRUMDataFormat
    }

    private func milliseconds(_ date: Date) -> Int64 {
        date.timeIntervalSince1970.dd.toInt64Milliseconds
    }

    // MARK: - Resource Completion Ownership

    func testGivenRetainedResource_whenItSucceeds_itDoesNotCountInAnotherViewsAction() throws {
        let time = Date.mockDecember15th2019At10AMUTC()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: time, dependencies: .mockWith(samplingRate: 100, trackFrustrations: true))
        let h1 = ViewIdentifier("exp206-h1"), h2 = ViewIdentifier("exp206-h2")
        let resourceKey = "exp206-h1-success"

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: h1),
            context: context,
            writer: writer
        )
        let h1View = try XCTUnwrap(scope.viewScopes.last)
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.010), url: "https://example.com/h1-success"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.020), identity: h2),
            context: context,
            writer: writer
        )
        let h2View = try XCTUnwrap(scope.viewScopes.last)
        _ = scope.process(
            command: RUMStartUserActionCommand.mockWith(time: time.addingTimeInterval(0.030), actionType: resourceActionType, name: "H2 continuous"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.040), metrics: resourceMetrics(at: time)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.050),
                kind: .native,
                httpStatusCode: 200,
                size: 42
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(time: time.addingTimeInterval(0.060), actionType: resourceActionType),
            context: context,
            writer: writer
        )

        let resources = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertEqual(resources.count, 1)
        let resource = try XCTUnwrap(resources.first)
        XCTAssertEqual(resource.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(resource.view.id, h1View.viewUUID.toRUMDataFormat)
        XCTAssertEqual(resource.resource.encodedBodySize, 1_500)
        XCTAssertEqual(resource.resource.decodedBodySize, 2_048)
        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action.view.id, h2View.viewUUID.toRUMDataFormat)
        XCTAssertEqual(try XCTUnwrap(action.action.resource).count, 0)
        XCTAssertEqual(try XCTUnwrap(action.action.error).count, 0)
        XCTAssertNil(action.action.frustration)
    }

    func testGivenRetainedResource_whenItFails_itDoesNotFrustrateAnotherViewsAction() throws {
        let time = Date.mockDecember15th2019At10AMUTC()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: time, dependencies: .mockWith(samplingRate: 100, trackFrustrations: true))
        let h1 = ViewIdentifier("exp206-h1-error"), h2 = ViewIdentifier("exp206-h2-error")
        let resourceKey = "exp206-h1-error"

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: h1),
            context: context,
            writer: writer
        )
        let h1View = try XCTUnwrap(scope.viewScopes.last)
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.010), url: "https://example.com/h1-error"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.020), identity: h2),
            context: context,
            writer: writer
        )
        let h2View = try XCTUnwrap(scope.viewScopes.last)
        _ = scope.process(
            command: RUMStartUserActionCommand.mockWith(time: time.addingTimeInterval(0.030), actionType: resourceActionType, name: "H2 continuous"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.040), metrics: resourceMetrics(at: time)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.050),
                message: "H1 error",
                type: "EXP206",
                source: .network,
                httpStatusCode: 500
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(time: time.addingTimeInterval(0.060), actionType: resourceActionType),
            context: context,
            writer: writer
        )

        let errors = writer.events(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errors.count, 1)
        let error = try XCTUnwrap(errors.first)
        XCTAssertEqual(error.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(error.view.id, h1View.viewUUID.toRUMDataFormat)
        XCTAssertEqual(error.error.resource?.url, "https://example.com/h1-error")
        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action.view.id, h2View.viewUUID.toRUMDataFormat)
        XCTAssertEqual(try XCTUnwrap(action.action.resource).count, 0)
        XCTAssertEqual(try XCTUnwrap(action.action.error).count, 0)
        XCTAssertNil(action.action.frustration)
    }

    func testGivenForeignResourceCompletion_whenActionExpires_itPreservesClockDrivenExpiration() throws {
        let time = Date(timeIntervalSinceReferenceDate: 0)
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: time, dependencies: .mockWith(samplingRate: 100))
        let resourceKey = "exp206-expiring-completion"
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("h1")),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.010)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.020), identity: ViewIdentifier("h2")),
            context: context,
            writer: writer
        )
        let actionStart = time.addingTimeInterval(0.030)
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: actionStart, actionType: resourceActionType, name: "H2 discrete"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: actionStart.addingTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration + 0.001),
                kind: .native
            ),
            context: context,
            writer: writer
        )

        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertLessThanOrEqual(abs(try XCTUnwrap(action.action.loadingTime) - RUMUserActionScope.Constants.discreteActionTimeoutDuration.dd.toInt64Nanoseconds), 1)
        XCTAssertEqual(try XCTUnwrap(action.action.resource).count, 0)
    }

    func testGivenForeignResourceMetrics_whenActionExpires_itPreservesClockDrivenExpiration() throws {
        let time = Date(timeIntervalSinceReferenceDate: 0)
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: time, dependencies: .mockWith(samplingRate: 100))
        let resourceKey = "exp206-expiring-metrics"
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("h1")),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.010)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time.addingTimeInterval(0.020), identity: ViewIdentifier("h2")),
            context: context,
            writer: writer
        )
        let actionStart = time.addingTimeInterval(0.030)
        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(time: actionStart, actionType: resourceActionType, name: "H2 discrete"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(
                resourceKey: resourceKey,
                time: actionStart.addingTimeInterval(RUMUserActionScope.Constants.discreteActionTimeoutDuration + 0.001),
                metrics: resourceMetrics(at: time)
            ),
            context: context,
            writer: writer
        )

        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertLessThanOrEqual(abs(try XCTUnwrap(action.action.loadingTime) - RUMUserActionScope.Constants.discreteActionTimeoutDuration.dd.toInt64Nanoseconds), 1)
        XCTAssertEqual(try XCTUnwrap(action.action.resource).count, 0)
    }

    func testGivenSameViewResource_whenItSucceeds_itCountsInCurrentAction() throws {
        let time = Date.mockDecember15th2019At10AMUTC()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: time, dependencies: .mockWith(samplingRate: 100))
        let resourceKey = "exp206-same-success"
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("same")),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartUserActionCommand.mockWith(time: time.addingTimeInterval(0.010), actionType: resourceActionType),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.020)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.030), metrics: resourceMetrics(at: time)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.040), kind: .native),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(time: time.addingTimeInterval(0.050), actionType: resourceActionType),
            context: context,
            writer: writer
        )
        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(try XCTUnwrap(actions.first).action.resource?.count, 1)
    }

    func testGivenSameViewResource_whenItFails_itCountsAndFrustratesCurrentAction() throws {
        let time = Date.mockDecember15th2019At10AMUTC()
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: time, dependencies: .mockWith(samplingRate: 100, trackFrustrations: true))
        let resourceKey = "exp206-same-error"
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("same")),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartUserActionCommand.mockWith(time: time.addingTimeInterval(0.010), actionType: resourceActionType),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.020)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(resourceKey: resourceKey, time: time.addingTimeInterval(0.030), metrics: resourceMetrics(at: time)),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.040),
                message: "same error",
                type: "EXP206",
                source: .network,
                httpStatusCode: 500
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(time: time.addingTimeInterval(0.050), actionType: resourceActionType),
            context: context,
            writer: writer
        )
        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(try XCTUnwrap(action.action.error).count, 1)
        #if os(macOS)
        XCTAssertEqual(action.action.frustration?.type, [.errorClick])
        #else
        XCTAssertEqual(action.action.frustration?.type, [.errorTap])
        #endif
    }

    func testGivenSameViewResponseAndError_whenResourceCompletes_itPreservesActionErrorSignal() throws {
        let time = Date.mockDecember15th2019At10AMUTC()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: time,
            dependencies: .mockWith(samplingRate: 100, trackFrustrations: true)
        )
        let resourceKey = "same-view-response-and-error"
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(time: time, identity: ViewIdentifier("same")),
            context: context,
            writer: writer
        )
        let view = try XCTUnwrap(scope.viewScopes.last)
        _ = scope.process(
            command: RUMStartUserActionCommand.mockWith(
                time: time.addingTimeInterval(0.010),
                actionType: resourceActionType,
                name: "Search"
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.020),
                url: "https://example.com/same-view-response-and-error"
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMAddResourceMetricsCommand.mockWith(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.030),
                metrics: resourceMetrics(at: time)
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.040),
                kind: .native,
                httpStatusCode: 200,
                size: 42
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceWithErrorCommand.mockWithErrorMessage(
                resourceKey: resourceKey,
                time: time.addingTimeInterval(0.050),
                message: "response and error",
                type: "NetworkError",
                source: .network,
                httpStatusCode: 200
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopUserActionCommand.mockWith(
                time: time.addingTimeInterval(0.060),
                actionType: resourceActionType
            ),
            context: context,
            writer: writer
        )

        let resources = writer.events(ofType: RUMResourceEvent.self)
        XCTAssertEqual(resources.count, 1)
        let resource = try XCTUnwrap(resources.first)
        XCTAssertEqual(resource.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(resource.view.id, view.viewUUID.toRUMDataFormat)
        XCTAssertEqual(resource.resource.encodedBodySize, 1_500)
        XCTAssertEqual(resource.resource.decodedBodySize, 2_048)
        XCTAssertTrue(writer.events(ofType: RUMErrorEvent.self).isEmpty)

        let actions = writer.events(ofType: RUMActionEvent.self)
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertEqual(action.session.id, scope.context.sessionID.toRUMDataFormat)
        XCTAssertEqual(action.view.id, view.viewUUID.toRUMDataFormat)
        XCTAssertEqual(try XCTUnwrap(action.action.resource).count, 1)
        XCTAssertEqual(try XCTUnwrap(action.action.error).count, 1)
        #if os(macOS)
        XCTAssertEqual(action.action.frustration?.type, [.errorClick])
        #else
        XCTAssertEqual(action.action.frustration?.type, [.errorTap])
        #endif
    }

    private var resourceActionType: RUMActionType {
        #if os(macOS)
        .click
        #else
        .tap
        #endif
    }

    private func resourceMetrics(at time: Date) -> ResourceMetrics {
        .mockWith(
            fetch: .init(start: time.addingTimeInterval(0.010), end: time.addingTimeInterval(0.020)),
            dns: .init(start: time.addingTimeInterval(0.011), end: time.addingTimeInterval(0.012)),
            responseBodySize: (encoded: 1_500, decoded: 2_048)
        )
    }
}

// MARK: - Test Helpers

private class TimeseriesCollectorSpy: TimeseriesCollecting {
    weak var activeContextReader: RUMActiveContextReader?
    var startCallCount = 0
    var pauseCallCount = 0
    var resumeCallCount = 0
    var stopCallCount = 0
    var lastStartedSessionID: String?
    var lastStartedApplicationID: String?
    var lastStartedSessionType: RUMSessionType?
    var lastStoppedSessionID: String?
    var lastPausedSessionID: String?
    var lastResumedSessionID: String?

    func start(sessionID: String, applicationID: String, sessionType: RUMSessionType) {
        startCallCount += 1
        lastStartedSessionID = sessionID
        lastStartedApplicationID = applicationID
        lastStartedSessionType = sessionType
    }

    func pause(sessionID: String) {
        pauseCallCount += 1
        lastPausedSessionID = sessionID
    }

    func resume(sessionID: String) {
        resumeCallCount += 1
        lastResumedSessionID = sessionID
    }

    func stop(sessionID: String) {
        stopCallCount += 1
        lastStoppedSessionID = sessionID
    }

    var noteActivityCallCount = 0
    var lastActivitySessionID: String?
    var lastActivityTime: Date?

    func noteActivity(sessionID: String, at time: Date) {
        noteActivityCallCount += 1
        lastActivitySessionID = sessionID
        lastActivityTime = time
    }

    var flushCallCount = 0

    func flush() {
        flushCallCount += 1
    }
}

extension RUMSessionScopeTests {
    func testGivenAutomaticUnownedCompletion_itDoesNotMutateCurrentAction() throws {
        let fixture = E03ResourceScopeFixture()
        fixture.startView("current"); fixture.startAction("current")
        fixture.send(try fixture.automaticCompletion(error: false))
        fixture.send(try fixture.automaticCompletion(error: true))
        fixture.stopAction()
        try fixture.assertAction("current", resources: 0, errors: 0)
        XCTAssertTrue(fixture.resources.isEmpty)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testGivenResourceStartedBeforeReplacementAction_itCountsOnlyCurrentOwningAction() throws {
        let fixture = E03ResourceScopeFixture()
        let completion = try fixture.automaticCompletion(error: true)
        let key = try XCTUnwrap(completion as? RUMResourceCommand).resourceKey
        fixture.startView("owner"); fixture.startResource(key)
        fixture.startAction("first"); fixture.stopAction()
        fixture.startAction("replacement"); fixture.send(completion); fixture.stopAction()
        try fixture.assertAction("first", resources: 0, errors: 0)
        try fixture.assertAction("replacement", resources: 0, errors: 1)
        XCTAssertEqual(fixture.errors.count, 1)
    }

    func testGivenUnknownManualCompletions_itPreservesLegacyActionCounts() throws {
        let fixture = E03ResourceScopeFixture()
        fixture.startView("manual"); fixture.startAction("manual")
        fixture.stopResource("unknown"); fixture.stopResource("unknown")
        fixture.failResource("unknown"); fixture.stopAction()
        try fixture.assertAction("manual", resources: 2, errors: 1)
        XCTAssertTrue(fixture.resources.isEmpty)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testGivenReusedManualKey_itCompletesCurrentTrackedResource() throws {
        let fixture = E03ResourceScopeFixture()
        fixture.startView("old"); fixture.startResource("reused"); fixture.stopResource("reused")
        let old = try XCTUnwrap(fixture.resources.first).view.id
        fixture.startView("new"); fixture.startAction("new"); fixture.startResource("reused")
        fixture.failResource("reused"); fixture.stopAction()
        XCTAssertEqual(fixture.resources.count, 1)
        XCTAssertEqual(fixture.errors.count, 1)
        XCTAssertNotEqual(try XCTUnwrap(fixture.errors.first).view.id, old)
        try fixture.assertAction("new", resources: 0, errors: 1)
    }

    func testGivenAmbiguousAutomaticKey_itSettlesKnownOwnersWithoutMutatingForeignAction() throws {
        let fixture = E03ResourceScopeFixture()
        let completion = try fixture.automaticCompletion(error: false)
        let key = try XCTUnwrap(completion as? RUMResourceCommand).resourceKey
        fixture.startView("one"); fixture.startResource(key)
        fixture.startView("two"); fixture.startResource(key)
        fixture.startView("foreign"); fixture.startAction("foreign")
        fixture.send(completion); fixture.stopAction()
        try fixture.assertAction("foreign", resources: 0, errors: 0)
        XCTAssertEqual(fixture.resources.count, 2)
        XCTAssertEqual(Set(fixture.resources.map { $0.view.id }).count, 2)
        XCTAssertTrue(fixture.errors.isEmpty)
        XCTAssertEqual(fixture.session?.viewScopes.count, 1)
        XCTAssertTrue(fixture.session?.viewScopes.allSatisfy { $0.resourceScopes.isEmpty } == true)
    }

    func testGivenMultipleManualOwners_itPreservesOwnersAndIgnoresForeignAction() throws {
        let fixture = E03ResourceScopeFixture()
        fixture.startView("one"); fixture.startResource("shared")
        fixture.startView("two"); fixture.startResource("shared")
        fixture.startView("foreign"); fixture.startAction("foreign")
        fixture.stopResource("shared"); fixture.stopAction()
        XCTAssertEqual(fixture.resources.count, 2)
        XCTAssertEqual(Set(fixture.resources.map { $0.view.id }).count, 2)
        try fixture.assertAction("foreign", resources: 0, errors: 0)
    }
}

final class E03ResourceScopeFixture {
    let application: RUMApplicationScope
    let session: RUMSessionScope?
    let writer = FileWriterMock()
    let context: DatadogContext
    var time = Date.mockDecember15th2019At10AMUTC()
    var resources: [RUMResourceEvent] { writer.events(ofType: RUMResourceEvent.self) }
    var errors: [RUMErrorEvent] { writer.events(ofType: RUMErrorEvent.self) }
    private var actionType: RUMActionType {
        #if os(macOS)
        return .click
        #else
        return .tap
        #endif
    }

    init(applicationScope: Bool = false) {
        let dependencies = RUMScopeDependencies.mockWith(samplingRate: 100, trackFrustrations: true)
        context = .mockWith(sdkInitDate: time, launchInfo: .mockWith(launchReason: .userLaunch))
        application = RUMApplicationScope(dependencies: dependencies)
        session = applicationScope ? nil : .mockWith(parent: application, startTime: time, dependencies: dependencies)
        if applicationScope { send(RUMSDKInitCommand(time: time, globalAttributes: [:])) }
    }

    func send(_ incoming: RUMCommand) {
        var command = incoming
        command.time = time
        _ = (session as RUMScope? ?? application).process(command: command, context: context, writer: writer)
        time.addTimeInterval(0.01)
    }
    func startView(_ key: String) { send(RUMStartViewCommand.mockWith(identity: ViewIdentifier(key))) }
    func startAction(_ name: String) { send(RUMStartUserActionCommand.mockWith(actionType: actionType, name: name)) }
    func stopAction() { send(RUMStopUserActionCommand.mockWith(actionType: actionType)) }
    func startResource(_ key: String) { send(RUMStartResourceCommand.mockWith(resourceKey: key, url: "https://example.com/transfer")) }
    func stopResource(_ key: String) { send(RUMStopResourceCommand.mockWith(resourceKey: key, kind: .native, httpStatusCode: 200)) }
    func failResource(_ key: String) { send(RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: key, source: .network, httpStatusCode: 200)) }

    func automaticCompletion(error: Bool) throws -> RUMCommand {
        let subscriber = RUMCommandSubscriberMock()
        let handler = URLSessionRUMResourcesHandler(dateProvider: RelativeDateProvider(using: time), rumAttributesProvider: nil, distributedTracing: nil, headerProcessor: nil, disallowList: nil, telemetry: NOPTelemetry())
        handler.publish(to: subscriber)
        let interception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: false, trackingMode: .automatic)
        interception.register(response: .mockResponseWith(statusCode: 200), error: error ? URLError(.networkConnectionLost) : nil)
        handler.interceptionDidComplete(interception: interception)
        return try XCTUnwrap(subscriber.lastReceivedCommand)
    }

    func assertAction(_ name: String, resources: Int64, errors: Int64, file: StaticString = #filePath, line: UInt = #line) throws {
        let actions = writer.events(ofType: RUMActionEvent.self).filter { $0.action.target?.name == name }
        XCTAssertEqual(actions.count, 1, file: file, line: line)
        let action = try XCTUnwrap(actions.first, file: file, line: line)
        XCTAssertEqual(action.action.resource?.count, resources, file: file, line: line)
        XCTAssertEqual(action.action.error?.count, errors, file: file, line: line)
        XCTAssertEqual(action.action.frustration != nil, errors > 0, file: file, line: line)
    }
}
