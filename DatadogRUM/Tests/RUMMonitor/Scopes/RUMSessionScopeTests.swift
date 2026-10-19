/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
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
        let currentTime = Date()
        let clock = MonotonicClockMock(elapsedTime: 123)
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom(), monotonicClock: clock)
        )

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Keep interacting while only elapsed time advances, so inactivity cannot end the session.
        let sessionEnd = clock.elapsedTime + RUMSessionScope.Constants.sessionMaxDuration
        while clock.elapsedTime + RUMSessionScope.Constants.sessionTimeoutDuration - 1 < sessionEnd {
            clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration - 1)
            XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime, isUserInteraction: true), context: context, writer: writer))
        }
        clock.advance(by: sessionEnd - clock.elapsedTime)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
        XCTAssertEqual(scope.endReason, .maxDuration)
        XCTAssertEqual(scope.sessionStartTime, currentTime)
    }

    func testWhenSessionIsInactiveForCertainDuration_itGetsClosed() {
        let currentTime = Date()
        let clock = MonotonicClockMock(elapsedTime: 123)
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom(), monotonicClock: clock)
        )

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Push time forward by less than the session timeout duration:
        clock.advance(by: 0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))

        // Reach the exact timeout boundary without changing the command date.
        clock.advance(by: 0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)

        XCTAssertFalse(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
        XCTAssertEqual(scope.endReason, .timeOut)
    }

    func testWhenCommandIsProcessedAfterTimeout_itUsesCapturedReceiptTime() {
        let clock = MonotonicClockMock()
        let scope = RUMSessionScope.mockWith(dependencies: .mockWith(monotonicClock: clock))
        let beforeTimeout = RUMSessionScope.Constants.sessionTimeoutDuration - 1
        clock.advance(by: beforeTimeout + 2)

        XCTAssertTrue(scope.process(command: RUMCommandMock(), monotonicTime: beforeTimeout, context: context, writer: writer))
        XCTAssertFalse(scope.process(command: RUMCommandMock(), monotonicTime: beforeTimeout + 2, context: context, writer: writer))
        XCTAssertEqual(scope.endReason, .timeOut)
    }

    func testWhenOlderInteractionIsProcessed_itDoesNotMoveInactivityBackwards() {
        let scope = RUMSessionScope.mockWith()
        _ = scope.process(command: RUMCommandMock(isUserInteraction: true), monotonicTime: 10, context: context, writer: writer)
        _ = scope.process(command: RUMCommandMock(isUserInteraction: true), monotonicTime: 9, context: context, writer: writer)

        XCTAssertEqual(scope.lastInteraction, 10)
        let beforeTimeout = 10 + RUMSessionScope.Constants.sessionTimeoutDuration - 1
        XCTAssertTrue(scope.process(command: RUMCommandMock(), monotonicTime: beforeTimeout, context: context, writer: writer))
        XCTAssertFalse(scope.process(command: RUMCommandMock(), monotonicTime: beforeTimeout + 1, context: context, writer: writer))
    }

    func testWhenSessionReceivesInteractiveEvent_itStaysAlive() {
        var currentTime = Date()
        let clock = MonotonicClockMock()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom(), monotonicClock: clock)
        )

        for _ in 0...10 {
            // Push time forward by less than the session timeout duration:
            advance(&currentTime, clock, by: 0.5 * RUMSessionScope.Constants.sessionTimeoutDuration)
            XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime, isUserInteraction: true), context: context, writer: writer))
        }

        XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer))
    }

    func testWhenSessionReceivesNonInteractiveEvent_itGetsClosed() {
        var currentTime = Date()
        let clock = MonotonicClockMock()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(samplingRate: .mockRandom(), monotonicClock: clock)
        )

        for _ in 0...8 {
            // Push time forward by less than the session timeout duration:
            advance(&currentTime, clock, by: 0.1 * RUMSessionScope.Constants.sessionTimeoutDuration)
            XCTAssertTrue(scope.process(command: RUMCommandMock(time: currentTime, isUserInteraction: false), context: context, writer: writer))
        }

        advance(&currentTime, clock, by: 0.1 * RUMSessionScope.Constants.sessionTimeoutDuration)
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

    func testGivenSingleSceneH1HasPendingResource_whenNavigatingThroughDetailToH2_itKeepsOccurrencesIsolated() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let homeIdentity = ViewIdentifier("home")
        let detailIdentity = ViewIdentifier("detail")
        let resourceKey = "h1-resource"

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                attributes: ["occurrence": "home-1"],
                identity: homeIdentity,
                name: "Home"
            ),
            context: context,
            writer: writer
        )
        let firstHome = try XCTUnwrap(scope.viewScopes.first(where: \.isActiveView))
        let firstHomeViewID = firstHome.viewUUID

        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(identity: homeIdentity),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(identity: detailIdentity, name: "Detail"),
            context: context,
            writer: writer
        )
        let detailViewID = try XCTUnwrap(scope.viewScopes.first(where: \.isActiveView)?.viewUUID)
        XCTAssertNotEqual(firstHomeViewID, detailViewID)

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                attributes: ["occurrence": "home-2"],
                identity: homeIdentity,
                name: "Home"
            ),
            context: context,
            writer: writer
        )
        let returnedHome = try XCTUnwrap(scope.viewScopes.first(where: \.isActiveView))

        // A later start belongs only to the new Home occurrence.
        XCTAssertEqual(firstHome.attributes["occurrence"] as? String, "home-1")
        XCTAssertEqual(returnedHome.attributes["occurrence"] as? String, "home-2")
        XCTAssertNotEqual(firstHome.viewUUID, returnedHome.viewUUID)
        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 1)

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "h2-action"
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey),
            context: context,
            writer: writer
        )

        let resource = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        XCTAssertEqual(resource.view.id, firstHomeViewID.toRUMDataFormat)
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(action.view.id, returnedHome.viewUUID.toRUMDataFormat)
        XCTAssertTrue(scope.viewScopes.first(where: \.isActiveView) === returnedHome)
        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 1)
    }

    func testGivenInactiveH1AndActiveH2_whenH2Stops_itDoesNotMutateH1() throws {
        let scope: RUMSessionScope = .mockWith(parent: parent, startTime: Date())
        let homeIdentity = ViewIdentifier("home")
        let detailIdentity = ViewIdentifier("detail")
        let resourceKey = "h1-resource"

        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                attributes: ["occurrence": "home-1"],
                identity: homeIdentity,
                name: "Home"
            ),
            context: context,
            writer: writer
        )
        let firstHome = try XCTUnwrap(scope.viewScopes.first(where: \.isActiveView))
        let firstHomeViewID = firstHome.viewUUID
        _ = scope.process(
            command: RUMStartResourceCommand.mockWith(resourceKey: resourceKey),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(identity: homeIdentity),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(identity: detailIdentity, name: "Detail"),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                attributes: [:],
                identity: homeIdentity,
                name: "Home"
            ),
            context: context,
            writer: writer
        )
        let secondHome = try XCTUnwrap(scope.viewScopes.first(where: \.isActiveView))
        XCTAssertEqual(firstHome.attributes["occurrence"] as? String, "home-1")

        _ = scope.process(
            command: RUMAddUserActionCommand.mockWith(
                actionType: .custom,
                name: "h2-action"
            ),
            context: context,
            writer: writer
        )
        _ = scope.process(
            command: RUMStopViewCommand.mockWith(
                attributes: ["occurrence": "late-stop"],
                identity: homeIdentity
            ),
            context: context,
            writer: writer
        )

        // The active H2 legitimately receives the stop attributes; inactive H1 must not.
        XCTAssertEqual(firstHome.attributes["occurrence"] as? String, "home-1")
        XCTAssertEqual(secondHome.attributes["occurrence"] as? String, "late-stop")
        XCTAssertFalse(secondHome.isActiveView)
        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 0)
        let action = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(action.view.id, secondHome.viewUUID.toRUMDataFormat)

        _ = scope.process(
            command: RUMStopResourceCommand.mockWith(resourceKey: resourceKey),
            context: context,
            writer: writer
        )
        let resource = try XCTUnwrap(writer.events(ofType: RUMResourceEvent.self).last)
        XCTAssertEqual(resource.view.id, firstHomeViewID.toRUMDataFormat)
        XCTAssertEqual(scope.viewScopes.filter(\.isActiveView).count, 0)
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
        let clock = MonotonicClockMock()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(monotonicClock: clock, timeseriesCollector: collector)
        )

        // When — push past the max session duration
        advance(&currentTime, clock, by: RUMSessionScope.Constants.sessionMaxDuration)
        _ = scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer)

        // Then
        XCTAssertEqual(collector.stopCallCount, 1)
    }

    func testWhenSessionExpiresDueToInactivity_itStopsTimeseriesCollector() {
        // Given
        let collector = TimeseriesCollectorSpy()
        var currentTime = Date()
        let clock = MonotonicClockMock()
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: currentTime,
            dependencies: .mockWith(monotonicClock: clock, timeseriesCollector: collector)
        )

        _ = scope.process(command: RUMCommandMock(time: currentTime), context: context, writer: writer)

        // When — push past the session inactivity timeout
        advance(&currentTime, clock, by: RUMSessionScope.Constants.sessionTimeoutDuration)
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
            context: sessionContext,
            dateProvider: dateProvider
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
            context: sessionContext,
            dateProvider: dateProvider
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
            context: sessionContext,
            dateProvider: dateProvider
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
            context: sessionContext,
            dateProvider: dateProvider
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
            context: sessionContext,
            dateProvider: dateProvider
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
                context: sessionContext,
                dateProvider: dateProvider
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
            context: sessionContext,
            dateProvider: dateProvider
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
            monotonicStartTime: dateProvider.now.timeIntervalSinceReferenceDate,
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
            context: sessionContext,
            dateProvider: dateProvider
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

    /// Advances both the simulated wall clock (what `RUMCommand.time` carries) and the session clock
    /// (what bounds session lifetime), as real elapsed time would move both.
    private func advance(_ currentTime: inout Date, _ clock: MonotonicClockMock, by interval: TimeInterval) {
        currentTime.addTimeInterval(interval)
        clock.advance(by: interval)
    }

    private func makeSessionScope(
        viewCache: ViewCache,
        startTime: Date,
        context: DatadogContext,
        dateProvider: DateProvider
    ) -> RUMSessionScope {
        .mockWith(
            parent: parent,
            startTime: startTime,
            context: context,
            dependencies: .mockWith(
                samplingRate: 100,
                viewCache: viewCache,
                monotonicClock: DateProviderMonotonicClock(dateProvider: dateProvider)
            )
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
        let h1 = ViewIdentifier("previous-view"), h2 = ViewIdentifier("current-view")
        let resourceKey = "previous-view-success"

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
        let h1 = ViewIdentifier("previous-view-error"), h2 = ViewIdentifier("current-error-view")
        let resourceKey = "previous-view-error"

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
                type: "TestResourceError",
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
        let resourceKey = "completion-after-action-expiry"
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
        let resourceKey = "metrics-after-action-expiry"
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
        let resourceKey = "same-view-success"
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
        let resourceKey = "same-view-error"
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
                type: "TestResourceError",
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

    func noteActivity(sessionID: String) {
        noteActivityCallCount += 1
        lastActivitySessionID = sessionID
    }

    var flushCallCount = 0

    func flush() {
        flushCallCount += 1
    }
}

extension RUMSessionScopeTests {
    func testGivenAutomaticUnownedCompletion_itDoesNotMutateCurrentAction() throws {
        let fixture = RUMResourceCompletionFixture()
        fixture.startView("current")
        fixture.startAction("current")
        fixture.send(try fixture.automaticCompletion(error: false))
        fixture.send(try fixture.automaticCompletion(error: true))
        fixture.stopAction()
        try fixture.assertAction("current", resources: 0, errors: 0)
        XCTAssertTrue(fixture.resources.isEmpty)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testGivenResourceStartedBeforeReplacementAction_itCountsOnlyCurrentOwningAction() throws {
        let fixture = RUMResourceCompletionFixture()
        let completion = try fixture.automaticCompletion(error: true)
        let key = try XCTUnwrap(completion as? RUMResourceCommand).resourceKey
        fixture.startView("owner")
        fixture.startResource(key)
        fixture.startAction("first")
        fixture.stopAction()
        fixture.startAction("replacement")
        fixture.send(completion)
        fixture.stopAction()
        try fixture.assertAction("first", resources: 0, errors: 0)
        try fixture.assertAction("replacement", resources: 0, errors: 1)
        XCTAssertEqual(fixture.errors.count, 1)
    }

    func testGivenUnknownManualCompletions_itPreservesLegacyActionCounts() throws {
        let fixture = RUMResourceCompletionFixture()
        fixture.startView("manual")
        fixture.startAction("manual")
        fixture.stopResource("unknown")
        fixture.stopResource("unknown")
        fixture.failResource("unknown")
        fixture.stopAction()
        try fixture.assertAction("manual", resources: 2, errors: 1)
        XCTAssertTrue(fixture.resources.isEmpty)
        XCTAssertTrue(fixture.errors.isEmpty)
    }

    func testGivenTimedOutSessionResource_whenItSucceeds_itDoesNotCountInNewSessionAction() throws {
        try assertExpiredSessionCompletion(by: .timeOut, error: false)
    }

    func testGivenTimedOutSessionResource_whenItFails_itDoesNotFrustrateNewSessionAction() throws {
        try assertExpiredSessionCompletion(by: .timeOut, error: true)
    }

    func testGivenMaxDurationSessionResource_whenItSucceeds_itDoesNotCountInNewSessionAction() throws {
        try assertExpiredSessionCompletion(by: .maxDuration, error: false)
    }

    func testGivenMaxDurationSessionResource_whenItFails_itDoesNotFrustrateNewSessionAction() throws {
        try assertExpiredSessionCompletion(by: .maxDuration, error: true)
    }

    func testGivenReusedExpiredSessionResourceKey_whenBothResourcesComplete_itCountsOneResourceInNewSessionAction() throws {
        try assertReusedExpiredSessionResourceKey(startExpiresSession: false)
    }

    func testGivenReusingStartExpiresSession_whenBothResourcesComplete_itCountsOneResourceInNewSessionAction() throws {
        try assertReusedExpiredSessionResourceKey(startExpiresSession: true)
    }

    func testGivenCompletionExpiresSession_whenKeyIsStoppedAgain_itPreservesLegacyActionCounts() throws {
        let fixture = RUMResourceCompletionFixture(applicationScope: true)
        fixture.startView("expired")
        fixture.startResource("late")
        fixture.expireSession(by: .timeOut)
        // The expired Resource's completion ends its session, so the key no longer refers to it.
        fixture.stopResource("late")
        fixture.startView("current")
        fixture.startAction("current")
        fixture.stopResource("late")
        fixture.stopAction()
        try fixture.assertAction("current", resources: 1, errors: 0)
        XCTAssertTrue(fixture.resources.isEmpty)
    }

    private func assertReusedExpiredSessionResourceKey(
        startExpiresSession: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let fixture = RUMResourceCompletionFixture(applicationScope: true)
        fixture.startView("expired")
        fixture.startResource("reused")
        fixture.expireSession(by: .timeOut)
        if !startExpiresSession {
            fixture.startView("current")
        }
        // When the start expires the session, the new session restarts the last view to track it.
        fixture.startResource("reused")
        fixture.startAction("current")
        // One stop completes the expired Resource. Only the stop owned by a tracked view counts.
        fixture.stopResource("reused")
        fixture.stopResource("reused")
        fixture.stopAction()
        try fixture.assertAction("current", resources: 1, errors: 0, file: file, line: line)
        XCTAssertEqual(fixture.resources.count, 1, file: file, line: line)
    }

    private func assertExpiredSessionCompletion(
        by reason: RUMSessionScope.EndReason,
        error: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let fixture = RUMResourceCompletionFixture(applicationScope: true)
        fixture.startView("expired")
        fixture.startResource("late")
        fixture.expireSession(by: reason)
        fixture.startView("current")
        fixture.startAction("current")
        error ? fixture.failResource("late") : fixture.stopResource("late")
        fixture.stopAction()
        try fixture.assertAction("current", resources: 0, errors: 0, file: file, line: line)
        XCTAssertTrue(fixture.resources.isEmpty, file: file, line: line)
        XCTAssertTrue(fixture.errors.isEmpty, file: file, line: line)
    }

    func testGivenReusedManualKey_itCompletesCurrentTrackedResource() throws {
        let fixture = RUMResourceCompletionFixture()
        fixture.startView("old")
        fixture.startResource("reused")
        fixture.stopResource("reused")
        let old = try XCTUnwrap(fixture.resources.first).view.id
        fixture.startView("new")
        fixture.startAction("new")
        fixture.startResource("reused")
        fixture.failResource("reused")
        fixture.stopAction()
        XCTAssertEqual(fixture.resources.count, 1)
        XCTAssertEqual(fixture.errors.count, 1)
        XCTAssertNotEqual(try XCTUnwrap(fixture.errors.first).view.id, old)
        try fixture.assertAction("new", resources: 0, errors: 1)
    }

    func testGivenAmbiguousAutomaticKey_itSettlesKnownOwnersWithoutMutatingForeignAction() throws {
        let fixture = RUMResourceCompletionFixture()
        let completion = try fixture.automaticCompletion(error: false)
        let key = try XCTUnwrap(completion as? RUMResourceCommand).resourceKey
        fixture.startView("one")
        fixture.startResource(key)
        fixture.startView("two")
        fixture.startResource(key)
        fixture.startView("foreign")
        fixture.startAction("foreign")
        fixture.send(completion)
        fixture.stopAction()
        try fixture.assertAction("foreign", resources: 0, errors: 0)
        XCTAssertEqual(fixture.resources.count, 2)
        XCTAssertEqual(Set(fixture.resources.map { $0.view.id }).count, 2)
        XCTAssertTrue(fixture.errors.isEmpty)
        XCTAssertEqual(fixture.session?.viewScopes.count, 1)
        XCTAssertTrue(fixture.session?.viewScopes.allSatisfy { $0.resourceScopes.isEmpty } == true)
    }

    func testGivenMultipleManualOwners_itPreservesOwnersAndIgnoresForeignAction() throws {
        let fixture = RUMResourceCompletionFixture()
        fixture.startView("one")
        fixture.startResource("shared")
        fixture.startView("two")
        fixture.startResource("shared")
        fixture.startView("foreign")
        fixture.startAction("foreign")
        fixture.stopResource("shared")
        fixture.stopAction()
        XCTAssertEqual(fixture.resources.count, 2)
        XCTAssertEqual(Set(fixture.resources.map { $0.view.id }).count, 2)
        try fixture.assertAction("foreign", resources: 0, errors: 0)
    }
}

final class RUMResourceCompletionFixture {
    let application: RUMApplicationScope
    let session: RUMSessionScope?
    let writer = FileWriterMock()
    let context: DatadogContext
    private let monotonicClock = MonotonicClockMock()
    /// Advances the injected monotonic clock by the same interval as this simulated wall clock.
    var time = Date.mockDecember15th2019At10AMUTC() {
        didSet { monotonicClock.advance(by: time.timeIntervalSince(oldValue)) }
    }
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
        let dependencies = RUMScopeDependencies.mockWith(samplingRate: 100, trackFrustrations: true, monotonicClock: monotonicClock)
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

    /// Advances time so that the next command ends the session for `reason`.
    func expireSession(by reason: RUMSessionScope.EndReason) {
        let timeout = RUMSessionScope.Constants.sessionTimeoutDuration
        switch reason {
        case .timeOut:
            time.addTimeInterval(timeout)
        case .maxDuration:
            let expiration = time.addingTimeInterval(RUMSessionScope.Constants.sessionMaxDuration)
            // Interactions keep the session from timing out before it reaches its max duration.
            while expiration.timeIntervalSince(time) > timeout / 2 {
                time.addTimeInterval(timeout / 2)
                startAction("keep-alive")
                stopAction()
            }
            time = expiration
        case .stopAPI:
            XCTFail("Stopped sessions are not expired; send `RUMStopSessionCommand` instead")
        }
    }

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

extension RUMSessionScopeTests {
    private var sceneATarget: RUMCommandTarget { .scene(RUMSceneIdentifier(rawValue: "scene-a")) }
    private var sceneBTarget: RUMCommandTarget { .scene(RUMSceneIdentifier(rawValue: "scene-b")) }
    private var routingStart: Date { Date(timeIntervalSince1970: 1_600_000_000) }

    private func sceneSession(enabled: Bool = true, capacity: Int = 30, dateProvider: DateProviderMock? = nil) -> RUMSessionScope {
        let cache = ViewCache(dateProvider: dateProvider ?? DateProviderMock(now: routingStart), capacity: capacity, isMultiSceneTrackingEnabled: enabled)
        return .mockWith(
            isInitialSession: false,
            parent: parent,
            startTime: routingStart,
            dependencies: .mockWith(viewCache: cache, featureFlags: [.multiSceneTracking: enabled])
        )
    }

    private func route(_ command: RUMCommand, through scope: RUMSessionScope) {
        _ = scope.process(command: command, monotonicTime: command.time.timeIntervalSince(routingStart), context: context, writer: writer)
    }

    @discardableResult
    private func startOwnedView(_ scope: RUMSessionScope, target: RUMCommandTarget, key: String, after seconds: TimeInterval = 0) -> RUMViewScope? {
        let command = RUMStartViewCommand(
            time: routingStart.addingTimeInterval(seconds),
            identity: ViewIdentifier(key),
            name: key,
            path: key,
            globalAttributes: [:],
            attributes: [:],
            instrumentationType: .manual,
            target: target
        )
        route(command, through: scope)
        return scope.viewScopes.last(where: { $0.isActiveView && $0.viewName == key })
    }

    private func startOwnedResource(_ scope: RUMSessionScope, target: RUMCommandTarget, key: String, after seconds: TimeInterval = 0) {
        var command = RUMStartResourceCommand.mockWith(resourceKey: key, time: routingStart.addingTimeInterval(seconds))
        command.target = target
        route(command, through: scope)
    }

    private func startOwnedAction(_ scope: RUMSessionScope, target: RUMCommandTarget, after seconds: TimeInterval = 0) {
        var command = RUMStartUserActionCommand.mockWith(time: routingStart.addingTimeInterval(seconds), name: "owned-action")
        command.target = target
        route(command, through: scope)
    }

    func testMultiSceneStart_keepsPeerViewAndSameSceneOccurrencesSeparate() throws {
        for cachedTarget in [false, true] {
            let scope = sceneSession(capacity: 2)
            let firstA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "same"))
            startOwnedResource(scope, target: sceneATarget, key: "retained")
            let peer = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "same", after: 1))
            let target: RUMCommandTarget = cachedTarget ? .view(firstA.viewUUID) : sceneATarget
            let nextA = try XCTUnwrap(startOwnedView(scope, target: target, key: "same", after: 2))
            XCTAssertFalse(firstA.isActiveView)
            XCTAssertTrue(peer.isActiveView)
            XCTAssertTrue(nextA.isActiveView)
            XCTAssertNotEqual(firstA.viewUUID, nextA.viewUUID)
            XCTAssertEqual(scope.viewScopes.filter { $0.isActiveView }.count, 2)
            XCTAssertEqual(nextA.sceneIdentifier, firstA.sceneIdentifier)
            XCTAssertNotEqual(firstA.sceneIdentifier, peer.sceneIdentifier)
            XCTAssertEqual(scope.dependencies.viewCache.ownership(forViewID: firstA.viewUUID.toRUMDataFormat), .unknown)
            var stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(3), identity: ViewIdentifier("same"))
            stop.target = .view(nextA.viewUUID)
            route(stop, through: scope)
            XCTAssertFalse(nextA.isActiveView)
            XCTAssertTrue(peer.isActiveView)
        }
    }

    func testMultiSceneStop_withSameKey_stopsOnlyOwnedScene() throws {
        let scope = sceneSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "same"))
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "same", after: 1))
        var stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(2), identity: ViewIdentifier("same"))
        stop.target = sceneATarget
        route(stop, through: scope)
        XCTAssertFalse(viewA.isActiveView)
        XCTAssertTrue(viewB.isActiveView)
        XCTAssertEqual(scope.context.activeViewID, viewB.viewUUID)
    }

    func testMultiSceneViewMutations_updateOnlySelectedOwner() throws {
        let scope = sceneSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 1))
        var mutation = RUMAddViewAttributesCommand.mockWith(time: routingStart.addingTimeInterval(2), attributes: ["owner": "a"])
        mutation.target = sceneATarget
        route(mutation, through: scope)
        XCTAssertEqual(viewA.attributes["owner"] as? String, "a")
        XCTAssertNil(viewB.attributes["owner"])
        var timing = RUMAddViewTimingCommand.mockWith(time: routingStart.addingTimeInterval(3), timingName: "owned")
        timing.target = .view(viewA.viewUUID)
        route(timing, through: scope)
        XCTAssertNotNil(viewA.customTimings["owned"])
        XCTAssertNil(viewB.customTimings["owned"])
    }

    func testMultiSceneActionAndError_updateOnlySelectedOwner() throws {
        let scope = sceneSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 1))
        startOwnedAction(scope, target: sceneATarget, after: 2)
        XCTAssertNotNil(viewA.userActionScope)
        XCTAssertNil(viewB.userActionScope)
        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingStart.addingTimeInterval(3), message: "owned-error")
        error.target = sceneATarget
        error.userActionTarget = .captured(nil)
        route(error, through: scope)
        let events = writer.events(ofType: RUMErrorEvent.self)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.view.id, viewA.viewUUID.toRUMDataFormat)
        XCTAssertNil(events.first?.action)
        var stop = RUMStopUserActionCommand.mockWith(time: routingStart.addingTimeInterval(4))
        stop.target = .view(viewA.viewUUID)
        route(stop, through: scope)
        XCTAssertEqual(writer.events(ofType: RUMActionEvent.self).first?.action.error?.count, 0)
    }

    func testMultiSceneLegacyCommands_followLastInteractedRepresentative() throws {
        let scope = sceneSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 1))
        var action = RUMAddUserActionCommand.mockWith(time: routingStart.addingTimeInterval(2), actionType: .custom, name: "select-a")
        action.target = sceneATarget
        route(action, through: scope)
        XCTAssertEqual(scope.context.activeViewID, viewA.viewUUID)
        route(RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingStart.addingTimeInterval(3)), through: scope)
        XCTAssertEqual(writer.events(ofType: RUMErrorEvent.self).last?.view.id, viewA.viewUUID.toRUMDataFormat)
        XCTAssertTrue(viewB.isActiveView)
        XCTAssertEqual(scope.dependencies.viewCache.ownership(forViewID: viewB.viewUUID.toRUMDataFormat), .scene(RUMSceneIdentifier(rawValue: "scene-b")))
    }

    func testMultiSceneUnknownDirectTarget_doesNotBorrowPeer() {
        let scope = sceneSession()
        startOwnedView(scope, target: sceneATarget, key: "a")
        startOwnedView(scope, target: sceneBTarget, key: "b", after: 1)
        for target: RUMCommandTarget in [.none, .scene(RUMSceneIdentifier(rawValue: "missing")), .view(DefaultRUMUUIDGenerator().generateUnique())] {
            var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingStart.addingTimeInterval(2))
            error.target = target
            route(error, through: scope)
        }
        XCTAssertTrue(writer.events(ofType: RUMErrorEvent.self).isEmpty)
        XCTAssertEqual(scope.viewScopes.filter { $0.isActiveView }.count, 2)
    }

    func testMultiSceneInvalidOptionalOverride_preservesInferredOwner() throws {
        let scope = sceneSession()
        let oldA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "old-a"))
        let nextA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "next-a", after: 1))
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 2))
        for id in [DefaultRUMUUIDGenerator().generateUnique(), oldA.viewUUID] {
            var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingStart.addingTimeInterval(3))
            error.target = sceneBTarget
            error.explicitTarget = .view(id)
            route(error, through: scope)
            XCTAssertEqual(writer.events(ofType: RUMErrorEvent.self).last?.view.id, viewB.viewUUID.toRUMDataFormat)
        }
        XCTAssertFalse(writer.events(ofType: RUMErrorEvent.self).contains { $0.view.id == nextA.viewUUID.toRUMDataFormat })
        var valid = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingStart.addingTimeInterval(4))
        valid.target = sceneBTarget
        valid.explicitTarget = .view(nextA.viewUUID)
        route(valid, through: scope)
        XCTAssertEqual(writer.events(ofType: RUMErrorEvent.self).last?.view.id, nextA.viewUUID.toRUMDataFormat)
    }

    func testMultiSceneHistoricalViewTarget_usesKnownSceneWithoutPeerFallback() throws {
        let dateProvider = DateProviderMock(now: routingStart)
        let scope = sceneSession(dateProvider: dateProvider)
        let oldA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "old-a"))
        let newA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "new-a", after: 1))
        startOwnedView(scope, target: sceneBTarget, key: "b", after: 2)
        var error = RUMAddCurrentViewErrorCommand.mockWithErrorMessage(time: routingStart.addingTimeInterval(3))
        error.target = .view(oldA.viewUUID)
        route(error, through: scope)
        XCTAssertEqual(writer.events(ofType: RUMErrorEvent.self).last?.view.id, newA.viewUUID.toRUMDataFormat)
        let count = writer.events(ofType: RUMErrorEvent.self).count
        dateProvider.now = routingStart.addingTimeInterval(181)
        error.time = routingStart.addingTimeInterval(182)
        route(error, through: scope)
        XCTAssertEqual(scope.dependencies.viewCache.ownership(forViewID: oldA.viewUUID.toRUMDataFormat), .unknown)
        XCTAssertEqual(writer.events(ofType: RUMErrorEvent.self).count, count)
    }

    func testMultiSceneResourceCompletion_preservesCapturedOwnerAcrossPeerNavigation() throws {
        let scope = sceneSession()
        let oldA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        startOwnedResource(scope, target: sceneATarget, key: "request")
        let peer = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 1))
        startOwnedView(scope, target: sceneATarget, key: "next-a", after: 2)
        var stop = RUMStopResourceCommand.mockWith(resourceKey: "request", time: routingStart.addingTimeInterval(3))
        stop.isAutomatic = true
        stop.ownership = .views([oldA.viewUUID])
        stop.target = .view(peer.viewUUID)
        route(stop, through: scope)
        XCTAssertEqual(writer.events(ofType: RUMResourceEvent.self).last?.view.id, oldA.viewUUID.toRUMDataFormat)
        XCTAssertTrue(oldA.resourceScopes.isEmpty)
        XCTAssertTrue(peer.resourceScopes.isEmpty)
    }

    func testMultiSceneAmbiguousResourceCompletion_settlesAllCapturedOwnersOnly() throws {
        let scope = sceneSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        startOwnedResource(scope, target: sceneATarget, key: "shared")
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 1))
        startOwnedResource(scope, target: sceneBTarget, key: "shared", after: 1)
        route(RUMStopResourceCommand.mockWith(resourceKey: "shared", time: routingStart.addingTimeInterval(2)), through: scope)
        XCTAssertEqual(Set(writer.events(ofType: RUMResourceEvent.self).map { $0.view.id }), Set([viewA.viewUUID.toRUMDataFormat, viewB.viewUUID.toRUMDataFormat]))
        XCTAssertTrue(viewA.resourceScopes.isEmpty)
        XCTAssertTrue(viewB.resourceScopes.isEmpty)
    }

    func testMultiSceneUnknownAutomaticCompletion_doesNotMutateRepresentativeAction() {
        let scope = sceneSession()
        startOwnedView(scope, target: sceneATarget, key: "a")
        startOwnedAction(scope, target: sceneATarget)
        var stop = RUMStopResourceCommand.mockWith(resourceKey: "missing", time: routingStart.addingTimeInterval(1))
        stop.isAutomatic = true
        route(stop, through: scope)
        var end = RUMStopUserActionCommand.mockWith(time: routingStart.addingTimeInterval(2))
        end.target = sceneATarget
        route(end, through: scope)
        XCTAssertEqual(writer.events(ofType: RUMActionEvent.self).last?.action.resource?.count, 0)
        XCTAssertTrue(writer.events(ofType: RUMResourceEvent.self).isEmpty)
    }

    func testMultiSceneUnknownManualCompletion_preservesLegacyActionCounts() {
        let scope = sceneSession()
        startOwnedView(scope, target: sceneATarget, key: "a")
        startOwnedAction(scope, target: sceneATarget)
        route(RUMStopResourceWithErrorCommand.mockWithErrorMessage(resourceKey: "missing", time: routingStart.addingTimeInterval(1)), through: scope)
        var end = RUMStopUserActionCommand.mockWith(time: routingStart.addingTimeInterval(2))
        end.target = sceneATarget
        route(end, through: scope)
        XCTAssertEqual(writer.events(ofType: RUMActionEvent.self).last?.action.error?.count, 1)
        XCTAssertEqual(writer.events(ofType: RUMActionEvent.self).last?.action.resource?.count, 0)
    }

    func testMultiSceneForeignWork_expiresPeerActionWithoutCopyingAttributes() throws {
        let scope = sceneSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        startOwnedAction(scope, target: sceneATarget)
        startOwnedView(scope, target: sceneBTarget, key: "b", after: 1)
        var command = RUMAddUserActionCommand.mockWith(time: routingStart.addingTimeInterval(11), attributes: ["foreign": "b"], actionType: .custom, name: "peer")
        command.target = sceneBTarget
        route(command, through: scope)
        XCTAssertNil(viewA.userActionScope)
        let event = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).first(where: { $0.view.id == viewA.viewUUID.toRUMDataFormat }))
        XCTAssertNil(event.context?.contextInfo["foreign"])
        XCTAssertEqual(event.action.target?.name, "owned-action")
    }

    func testMultiSceneNavigation_keepsInteractionMetricHistoryInOwnedScene() {
        var metrics: [INVMetricMock] = []
        let scope = sceneSession()
        let dependencies = scope.dependencies.replacing(interactionToNextViewMetricFactory: {
            let metric = INVMetricMock()
            metrics.append(metric)
            return metric
        })
        let routed = RUMSessionScope.mockWith(isInitialSession: false, parent: parent, startTime: routingStart, dependencies: dependencies)
        startOwnedView(routed, target: sceneATarget, key: "a")
        startOwnedView(routed, target: sceneBTarget, key: "b", after: 1)
        startOwnedView(routed, target: sceneATarget, key: "next-a", after: 2)
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics.first?.trackedViewStarts.map { $0.viewName }, ["a", "next-a"])
        XCTAssertEqual(metrics.last?.trackedViewStarts.map { $0.viewName }, ["b"])
    }

    func testDefaultMode_sceneTargetsPreserveLegacyDispatchAndExpiry() throws {
        let scope = sceneSession(enabled: false)
        let old = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        startOwnedResource(scope, target: sceneATarget, key: "retained")
        let current = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 1))
        startOwnedAction(scope, target: sceneBTarget, after: 2)
        XCTAssertNotNil(current.userActionScope)
        XCTAssertFalse(old.isActiveView)
        XCTAssertTrue(current.isActiveView)
        XCTAssertNil(old.sceneIdentifier)
        XCTAssertNil(current.sceneIdentifier)
        var completion = RUMStopResourceCommand.mockWith(resourceKey: "retained", time: routingStart.addingTimeInterval(13))
        completion.isAutomatic = true
        completion.ownership = .views([old.viewUUID])
        completion.attributes = ["foreign": "retained-owner"]
        route(completion, through: scope)
        XCTAssertNil(current.userActionScope)
        XCTAssertNil(current.attributes["foreign"])
        let expired = try XCTUnwrap(writer.events(ofType: RUMActionEvent.self).last)
        XCTAssertEqual(expired.view.id, current.viewUUID.toRUMDataFormat)
        XCTAssertEqual(expired.action.resource?.count, 0)
        var action = RUMAddUserActionCommand.mockWith(time: routingStart.addingTimeInterval(14), actionType: .custom, name: "legacy")
        action.target = .scene(RUMSceneIdentifier(rawValue: "missing"))
        route(action, through: scope)
        XCTAssertEqual(writer.events(ofType: RUMActionEvent.self).last?.view.id, current.viewUUID.toRUMDataFormat)
    }
}

extension RUMSessionScopeTests {
    private func representativeSession(
        enabled: Bool = true,
        viewUpdates: Bool = false,
        watchdogState: WatchdogTerminationMonitor.State = .started
    ) -> (scope: RUMSessionScope, feature: FeatureScopeMock) {
        let feature = FeatureScopeMock()
        let manager = AppStateManager(featureScope: feature, processId: UUID(), syntheticsEnvironment: false)
        let watchdog = WatchdogTerminationMonitor(
            appStateManager: manager,
            checker: WatchdogTerminationChecker(appStateManager: manager, featureScope: feature),
            storage: nil,
            feature: feature,
            reporter: WatchdogTerminationReporterMock(didSend: XCTestExpectation(description: "watchdog report"))
        )
        watchdog.currentState = watchdogState
        let cache = ViewCache(dateProvider: DateProviderMock(now: routingStart), isMultiSceneTrackingEnabled: enabled)
        let dependencies = RUMScopeDependencies.mockWith(
            trackBackgroundEvents: false,
            viewCache: cache,
            watchdogTermination: watchdog,
            featureFlags: [.multiSceneTracking: enabled, .viewUpdates: viewUpdates]
        )
        let scope = RUMSessionScope.mockWith(
            isInitialSession: false,
            parent: parent,
            startTime: routingStart,
            dependencies: dependencies
        )
        return (scope, feature)
    }

    private func watchdogView(in feature: FeatureScopeMock) -> RUMViewEvent? {
        var result: RUMViewEvent?
        feature.rumDataStore.value(forKey: .watchdogRUMViewEvent) { (event: RUMViewEvent?) in result = event }
        return result
    }

    private func fullSnapshot(_ event: RUMViewEvent?) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(XCTUnwrap(event))
    }

    func testMultiSceneFatalContext_foreignResourceCompletionPreservesFullRepresentativeSnapshot() throws {
        let (scope, feature) = representativeSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        startOwnedResource(scope, target: sceneATarget, key: "resource-a")
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 1))
        let before = try fullSnapshot(scope.dependencies.fatalErrorContext.view)
        var completion = RUMStopResourceCommand.mockWith(resourceKey: "resource-a", time: routingStart.addingTimeInterval(2))
        completion.target = sceneATarget
        route(completion, through: scope)
        XCTAssertEqual(scope.context.activeViewID, viewB.viewUUID)
        XCTAssertEqual(try fullSnapshot(scope.dependencies.fatalErrorContext.view), before)
        XCTAssertEqual(try fullSnapshot(watchdogView(in: feature)), before)
        XCTAssertEqual(writer.events(ofType: RUMResourceEvent.self).last?.view.id, viewA.viewUUID.toRUMDataFormat)
    }

    func testMultiSceneFatalContext_interactionSelectsFullOwnedSnapshot() throws {
        let (scope, feature) = representativeSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        _ = startOwnedView(scope, target: sceneBTarget, key: "b", after: 1)
        startOwnedAction(scope, target: sceneATarget, after: 2)
        XCTAssertEqual(scope.context.activeViewID, viewA.viewUUID)
        XCTAssertEqual(scope.dependencies.fatalErrorContext.view?.view.id, viewA.viewUUID.toRUMDataFormat)
        XCTAssertEqual(try fullSnapshot(watchdogView(in: feature)), try fullSnapshot(scope.dependencies.fatalErrorContext.view))
    }

    func testMultiSceneFatalContext_stoppingRepresentativeRestoresPeerThenClearsAll() throws {
        let (scope, feature) = representativeSession()
        let viewA = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "a"))
        let peer = try fullSnapshot(scope.dependencies.fatalErrorContext.view)
        _ = startOwnedView(scope, target: sceneBTarget, key: "b", after: 1)
        var stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(2), identity: ViewIdentifier("b"))
        stop.target = sceneBTarget
        route(stop, through: scope)
        XCTAssertEqual(scope.context.activeViewID, viewA.viewUUID)
        XCTAssertEqual(try fullSnapshot(scope.dependencies.fatalErrorContext.view), peer)
        XCTAssertEqual(try fullSnapshot(watchdogView(in: feature)), peer)
        stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(3), identity: ViewIdentifier("a"))
        stop.target = sceneATarget
        route(stop, through: scope)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.dependencies.fatalErrorContext.view)
        XCTAssertNil(watchdogView(in: feature))
    }

    func testMultiSceneFatalContext_retainedStoppedRepresentativeCannotOverwritePeerOrRestoreClearedSnapshot() throws {
        for keepPeerActive in [true, false] {
            let (scope, feature) = representativeSession()
            let peer = try XCTUnwrap(startOwnedView(scope, target: sceneATarget, key: "peer"))
            let peerSnapshot = try fullSnapshot(scope.dependencies.fatalErrorContext.view)
            let owner = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "owner", after: 1))
            startOwnedResource(scope, target: sceneBTarget, key: "pending-owner-resource", after: 2)
            var stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(3), identity: ViewIdentifier("owner"))
            stop.target = sceneBTarget
            route(stop, through: scope)
            XCTAssertTrue(scope.viewScopes.contains { $0 === owner })
            XCTAssertFalse(owner.isActiveView)
            XCTAssertEqual(scope.context.activeViewID, peer.viewUUID)
            XCTAssertEqual(try fullSnapshot(scope.dependencies.fatalErrorContext.view), peerSnapshot)
            XCTAssertEqual(try fullSnapshot(watchdogView(in: feature)), peerSnapshot)
            if !keepPeerActive {
                stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(4), identity: ViewIdentifier("peer"))
                stop.target = sceneATarget
                route(stop, through: scope)
                XCTAssertNil(scope.context.activeViewID)
                XCTAssertNil(scope.dependencies.fatalErrorContext.view)
                XCTAssertNil(watchdogView(in: feature))
            }
            var completion = RUMStopResourceCommand.mockWith(resourceKey: "pending-owner-resource", time: routingStart.addingTimeInterval(5))
            completion.target = sceneBTarget
            route(completion, through: scope)
            XCTAssertEqual(writer.events(ofType: RUMResourceEvent.self).last?.view.id, owner.viewUUID.toRUMDataFormat)
            if keepPeerActive {
                XCTAssertEqual(scope.context.activeViewID, peer.viewUUID)
                XCTAssertEqual(try fullSnapshot(scope.dependencies.fatalErrorContext.view), peerSnapshot)
                XCTAssertEqual(try fullSnapshot(watchdogView(in: feature)), peerSnapshot)
            } else {
                XCTAssertNil(scope.context.activeViewID)
                XCTAssertNil(scope.dependencies.fatalErrorContext.view)
                XCTAssertNil(watchdogView(in: feature))
            }
        }
    }

    func testMultiSceneFatalContext_invalidMappedOwnerCannotBorrowPeerSnapshot() throws {
        let (scope, feature) = representativeSession()
        _ = startOwnedView(scope, target: sceneATarget, key: "a")
        let peerEvent = try XCTUnwrap(scope.dependencies.fatalErrorContext.view)
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 1))
        scope.recordMappedViewEvent(peerEvent, for: viewB.viewUUID)
        var unrelated = RUMStopResourceCommand.mockWith(resourceKey: "absent", time: routingStart.addingTimeInterval(2))
        unrelated.target = sceneBTarget
        route(unrelated, through: scope)
        XCTAssertEqual(scope.context.activeViewID, viewB.viewUUID)
        XCTAssertNil(scope.dependencies.fatalErrorContext.view)
        XCTAssertNil(watchdogView(in: feature))
    }

    func testMultiSceneFatalContext_watchdogRetriesDeferredSnapshotAndClearAfterReadiness() throws {
        for stopBeforeReadiness in [false, true] {
            let (scope, feature) = representativeSession(watchdogState: .starting)
            let previous: RUMViewEvent = .mockRandom()
            feature.rumDataStore.setValue(previous, forKey: .watchdogRUMViewEvent)
            _ = startOwnedView(scope, target: sceneATarget, key: "a")
            let current = try fullSnapshot(scope.dependencies.fatalErrorContext.view)
            if stopBeforeReadiness {
                var stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(1), identity: ViewIdentifier("a"))
                stop.target = sceneATarget
                route(stop, through: scope)
                XCTAssertNil(scope.dependencies.fatalErrorContext.view)
            }
            XCTAssertEqual(try fullSnapshot(watchdogView(in: feature)), try fullSnapshot(previous))
            scope.dependencies.watchdogTermination?.currentState = .started
            var unrelated = RUMStopResourceCommand.mockWith(resourceKey: "absent", time: routingStart.addingTimeInterval(2))
            unrelated.target = sceneATarget
            route(unrelated, through: scope)
            if stopBeforeReadiness {
                XCTAssertNil(watchdogView(in: feature))
            } else {
                XCTAssertEqual(try fullSnapshot(watchdogView(in: feature)), current)
            }
        }
    }

    func testMultiSceneFatalContext_viewDeltaRetainsFullRepresentativeSnapshot() throws {
        let (scope, feature) = representativeSession(viewUpdates: true)
        _ = startOwnedView(scope, target: sceneATarget, key: "a")
        startOwnedResource(scope, target: sceneATarget, key: "resource-a", after: 1)
        let viewB = try XCTUnwrap(startOwnedView(scope, target: sceneBTarget, key: "b", after: 2))
        startOwnedResource(scope, target: sceneBTarget, key: "resource-b", after: 3)
        var completion = RUMStopResourceCommand.mockWith(resourceKey: "resource-b", time: routingStart.addingTimeInterval(4))
        completion.target = sceneBTarget
        route(completion, through: scope)
        XCTAssertTrue(writer.events(ofType: RUMViewUpdateEvent.self).contains { $0.view.id == viewB.viewUUID.toRUMDataFormat })
        XCTAssertEqual(scope.dependencies.fatalErrorContext.view?.view.resource.count, 1)
        let before = try fullSnapshot(scope.dependencies.fatalErrorContext.view)
        completion = RUMStopResourceCommand.mockWith(resourceKey: "resource-a", time: routingStart.addingTimeInterval(5))
        completion.target = sceneATarget
        route(completion, through: scope)
        XCTAssertEqual(try fullSnapshot(scope.dependencies.fatalErrorContext.view), before)
        XCTAssertEqual(try fullSnapshot(watchdogView(in: feature)), before)
    }

    func testMultiSceneFatalContext_stoppedSessionClearsRepresentativeWithPendingResource() throws {
        let (scope, feature) = representativeSession()
        _ = startOwnedView(scope, target: sceneATarget, key: "a")
        startOwnedResource(scope, target: sceneATarget, key: "pending")
        _ = startOwnedView(scope, target: sceneBTarget, key: "b", after: 1)
        route(RUMStopSessionCommand.mockWith(time: routingStart.addingTimeInterval(2)), through: scope)
        XCTAssertFalse(scope.viewScopes.isEmpty)
        XCTAssertNil(scope.context.activeViewID)
        XCTAssertNil(scope.dependencies.fatalErrorContext.view)
        XCTAssertNil(watchdogView(in: feature))
    }

    func testDefaultModeFatalContext_lateResourcesKeepActiveViewAndCannotReviveStoppedContext() throws {
        let flagModes: [RUM.Configuration.FeatureFlags] = [.defaults, [.multiSceneTracking: false]]
        for flags in flagModes {
            let (seed, feature) = representativeSession(enabled: false)
            let scope = RUMSessionScope.mockWith(
                isInitialSession: false,
                parent: parent,
                startTime: routingStart,
                dependencies: seed.dependencies.replacing(featureFlags: flags)
            )
            XCTAssertFalse(scope.dependencies.isMultiSceneTrackingEnabled)
            let owner = try XCTUnwrap(startOwnedView(scope, target: .none, key: "owner"))
            startOwnedResource(scope, target: .none, key: "first-resource", after: 1)
            startOwnedResource(scope, target: .none, key: "late-resource", after: 2)
            let active = try XCTUnwrap(startOwnedView(scope, target: .none, key: "active", after: 3))
            XCTAssertFalse(owner.isActiveView)
            XCTAssertTrue(scope.viewScopes.contains { $0 === owner })
            let activeSnapshot = try fullSnapshot(scope.dependencies.fatalErrorContext.view)
            var completion = RUMStopResourceCommand.mockWith(resourceKey: "first-resource", time: routingStart.addingTimeInterval(4))
            completion.target = .none
            route(completion, through: scope)
            XCTAssertEqual(writer.events(ofType: RUMResourceEvent.self).last?.view.id, owner.viewUUID.toRUMDataFormat)
            XCTAssertEqual(scope.context.activeViewID, active.viewUUID)
            XCTAssertEqual(try fullSnapshot(scope.dependencies.fatalErrorContext.view), activeSnapshot)
            var stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(5), identity: ViewIdentifier("active"))
            stop.target = .none
            route(stop, through: scope)
            XCTAssertNil(scope.dependencies.fatalErrorContext.view)
            completion = RUMStopResourceCommand.mockWith(resourceKey: "late-resource", time: routingStart.addingTimeInterval(6))
            completion.target = .none
            route(completion, through: scope)
            XCTAssertEqual(writer.events(ofType: RUMResourceEvent.self).last?.view.id, owner.viewUUID.toRUMDataFormat)
            XCTAssertNil(scope.context.activeViewID)
            XCTAssertNil(scope.dependencies.fatalErrorContext.view)
            XCTAssertEqual(watchdogView(in: feature)?.view.id, owner.viewUUID.toRUMDataFormat)
            XCTAssertEqual(watchdogView(in: feature)?.view.isActive, false)
            XCTAssertEqual(watchdogView(in: feature)?.view.resource.count, 2)
        }
    }

    func testDefaultModeFatalContext_keepsLegacyWatchdogFinalViewAfterStop() throws {
        let (scope, feature) = representativeSession(enabled: false)
        let view = try XCTUnwrap(startOwnedView(scope, target: .none, key: "legacy"))
        var stop = RUMStopViewCommand.mockWith(time: routingStart.addingTimeInterval(1), identity: ViewIdentifier("legacy"))
        stop.target = .none
        route(stop, through: scope)
        XCTAssertNil(scope.dependencies.fatalErrorContext.view)
        XCTAssertEqual(watchdogView(in: feature)?.view.id, view.viewUUID.toRUMDataFormat)
        XCTAssertEqual(watchdogView(in: feature)?.view.isActive, false)
    }
}

extension RUMSessionScopeTests {
    func testPreparedResource_committedExpiryReleasesWithOriginalSession() throws {
        let featureScope = ResourcePreparationOwnerScope()
        let clock = MonotonicClockMock()
        let dependencies = RUMScopeDependencies.mockWith(
            featureScope: featureScope,
            trackBackgroundEvents: false,
            featureFlags: [.multiSceneTracking: true, .viewUpdates: false],
            monotonicClock: clock
        )
        guard dependencies.isMultiSceneTrackingEnabled else { throw XCTSkip("Requires enabled scene tracking") }
        var retained: RUMSessionScope? = .mockWith(isInitialSession: false, parent: parent, startTime: routingStart, dependencies: dependencies)
        weak var releasedSession = retained
        weak var releasedView: RUMViewScope?
        weak var releasedResource: RUMResourceScope?
        do {
            let session = try XCTUnwrap(retained)
            _ = startOwnedView(session, target: sceneATarget, key: "original")
            let viewID = try XCTUnwrap(session.viewScopes.last?.viewUUID)
            releasedView = session.viewScopes.last
            let identity = RUMResourcePreparationIdentity(owner: featureScope.owner, resourceID: UUID(), sessionID: session.sessionUUID, viewID: viewID)
            _ = session.processResourcePreparation(.init(identity: identity, operation: .reserve, time: routingStart), monotonicTime: 0, context: context, writer: writer)
            let spare = RUMResourcePreparationIdentity(owner: featureScope.owner, resourceID: UUID(), sessionID: session.sessionUUID, viewID: viewID)
            _ = session.processResourcePreparation(.init(identity: spare, operation: .reserve, time: routingStart), monotonicTime: 0, context: context, writer: writer)
            let removal = try XCTUnwrap(session.processResourcePreparation(.init(identity: spare, operation: .abandon, time: routingStart), monotonicTime: 0, context: context, writer: writer))
            XCTAssertTrue(removal.keepAlive)
            XCTAssertFalse(removal.publishesContext, "Nonfinal removal is only bookkeeping")
            let start = RUMStartResourceCommand.mockWith(resourceKey: identity.resourceKey, time: routingStart)
            XCTAssertNotNil(session.processResourcePreparation(.init(identity: identity, operation: .commit(start), time: routingStart), monotonicTime: 0, context: context, writer: writer))
            releasedResource = session.viewScopes.last?.resourceScopes[identity.resourceKey]
            XCTAssertNotNil(releasedResource)
            let before = writer.events(ofType: RUMViewEvent.self).count
            clock.advance(by: RUMSessionScope.Constants.sessionTimeoutDuration + 1)
            let terminal = RUMStopResourceCommand.mockWith(resourceKey: identity.resourceKey, time: routingStart)
            XCTAssertNil(session.processResourcePreparation(.init(identity: identity, operation: .resource(terminal), time: routingStart), monotonicTime: clock.elapsedTime, context: context, writer: writer))
            XCTAssertNil(session.endReason, "Captured rejection cannot run generic session expiry")
            XCTAssertNotNil(session.viewScopes.last?.resourceScopes[identity.resourceKey], "Committed expiry retains declared deferred cleanup")
            XCTAssertTrue(writer.events(ofType: RUMResourceEvent.self).isEmpty)
            XCTAssertEqual(writer.events(ofType: RUMViewEvent.self).count, before)
        }
        retained = nil
        XCTAssertNil(releasedSession)
        XCTAssertNil(releasedView)
        XCTAssertNil(releasedResource)
    }

    func testUnusedResourcePreparation_preservesLegacyTrackingAndState() throws {
        for flags in [RUM.Configuration.FeatureFlags.defaults, [.multiSceneTracking: false]] {
            let featureScope = ResourcePreparationOwnerScope()
            let dependencies = RUMScopeDependencies.mockWith(featureScope: featureScope, trackBackgroundEvents: false, featureFlags: flags)
            let session = RUMSessionScope.mockWith(isInitialSession: false, parent: parent, startTime: routingStart, dependencies: dependencies)
            _ = startOwnedView(session, target: .processRepresentative, key: "legacy")
            let view = try XCTUnwrap(session.viewScopes.last)
            XCTAssertFalse(view is RUMPreparedResourceViewScope)
            XCTAssertFalse(view.hasPendingResourcePreparations)
            XCTAssertFalse(view.reserveResourcePreparation("unused"))
            startOwnedResource(session, target: .processRepresentative, key: "request")
            route(RUMStopResourceCommand.mockWith(resourceKey: "request", time: routingStart.addingTimeInterval(1)), through: session)
            XCTAssertNil(view.resourceScopes["request"])
            XCTAssertEqual(writer.events(ofType: RUMResourceEvent.self).filter { $0.view.id == view.viewUUID.toRUMDataFormat }.count, 1)
            XCTAssertEqual(featureScope.ownerReads, 0, "The unused path must not acquire an On lifetime")
        }
    }
}

private final class ResourcePreparationOwnerScope: FeatureScope, RUMContextHandoffOwnerProviding, @unchecked Sendable {
    let owner = RUMContextHandoff.Owner()
    private let base = FeatureScopeMock()
    private(set) var ownerReads = 0
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { ownerReads += 1; return owner }
    var dataStore: DataStore { base.dataStore }
    var telemetry: Telemetry { base.telemetry }
    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) { base.eventWriteContext(bypassConsent: bypassConsent, block) }
    func context(_ block: @escaping (DatadogContext) -> Void) { base.context(block) }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { base.set(context: context) }
    func set(anonymousId: String?) { base.set(anonymousId: anonymousId) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { base.send(message: message, else: fallback) }
}
