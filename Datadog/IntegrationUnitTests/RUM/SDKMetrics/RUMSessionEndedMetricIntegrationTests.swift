/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import TestUtilities
@testable import DatadogRUM
@testable import DatadogInternal
@testable import DatadogCore

class RUMSessionEndedMetricIntegrationTests: XCTestCase {
    private let dateProvider = DateProviderMock()
    private let monotonicClock = MonotonicClockMock()
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy()
        core.context = .mockWith(
            sdkInitDate: dateProvider.now,
            launchInfo: .mockWith(processLaunchDate: dateProvider.now),
            applicationStateHistory: .mockAppInForeground(since: dateProvider.now)
        )
        rumConfig = RUM.Configuration(applicationID: .mockAny())
        rumConfig.telemetrySampleRate = .maxSampleRate
        rumConfig.sessionEndedSampleRate = .maxSampleRate
        rumConfig.dateProvider = dateProvider
        rumConfig.monotonicClock = monotonicClock
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        rumConfig = nil
    }

    // MARK: - Conditions For Sending The Metric

    func testWhenSessionEndsWithStopAPI() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        // When
        monitor.stopSession()

        // Then
        let event = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        XCTAssertEqual(event.application?.id, rumConfig.applicationID, "It must report `application.id` even though the session no longer exists")
        let metricAttributes = try XCTUnwrap(event.attributes)
        XCTAssertTrue(metricAttributes.wasStopped)
    }

    func testWhenSessionEndsDueToInactivityTimeout() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key1", name: "View1")

        // When
        advanceTime(by: RUMSessionScope.Constants.sessionTimeoutDuration + 1.seconds)
        monitor.startView(key: "key2", name: "View2")

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertFalse(metricAttributes.wasStopped)
    }

    func testWhenSessionReachesMaxDuration() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        // When
        let deadline = dateProvider.now + RUMSessionScope.Constants.sessionMaxDuration * 1.5
        while dateProvider.now < deadline {
            monitor.addAction(type: .custom, name: "action")
            advanceTime(by: RUMSessionScope.Constants.sessionTimeoutDuration - 1.seconds)
        }

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertFalse(metricAttributes.wasStopped)
    }

    func testWhenSDKInitializationIsDelayed_sessionLifetimeUsesReceiptTime() throws {
        let contextQueue = DispatchQueue(label: "test.rum.delayed-initialization")
        try replaceCore(contextQueue: contextQueue)
        let commandDate = dateProvider.now
        let monotonicStartTime = monotonicClock.elapsedTime
        let delay = RUMSessionScope.Constants.sessionMaxDuration + 1.seconds

        // Hold the real context queue so initialization and the first view remain pending.
        let monitor: RUMMonitorProtocol
        contextQueue.suspend()
        do {
            defer { contextQueue.resume() }
            RUM.enable(with: rumConfig, in: core)
            monitor = RUMMonitor.shared(in: core)
            monitor.startView(key: "first", name: "First")
            advanceTime(by: delay)
        }

        // The queued view still belongs to the original session and retains its event timestamp.
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(core.waitAndReturnRUMEventMatchers())
            .takeSingle()
        let firstView = try XCTUnwrap(session.views.first { $0.name == "First" })
        XCTAssertEqual(firstView.viewEvents.first?.date, commandDate.timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertNil(core.waitAndReturnSessionEndedMetricEvent())
        let expiryReader = try XCTUnwrap(monitor as? Monitor)
        XCTAssertEqual(expiryReader.applicationScope.activeSession?.sessionStart, monotonicStartTime)
        XCTAssertTrue(expiryReader.isSessionExpired(sessionID: session.sessionID))

        // A view issued at the current clock reading starts a new session.
        monitor.startView(key: "second", name: "Second")
        let (_, renewedSession) = try RUMSessionMatcher
            .groupMatchersBySessions(core.waitAndReturnRUMEventMatchers())
            .takeTwo()
        XCTAssertNotEqual(renewedSession.sessionID, session.sessionID)
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        XCTAssertEqual(metric.session?.id, session.sessionID)
        XCTAssertEqual(metric.attributes?.wasStopped, false)
    }

    func testWhenInteractionIsQueuedBeforeTimeout_butProcessedAfterTimeout_itKeepsSession() throws {
        let contextQueue = DispatchQueue(label: "test.rum.delayed-interaction")
        try replaceCore(contextQueue: contextQueue)
        RUM.enable(with: rumConfig, in: core)
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "first", name: "First")
        let initialSession = try RUMSessionMatcher
            .groupMatchersBySessions(core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        advanceTime(by: RUMSessionScope.Constants.sessionTimeoutDuration - 1.seconds)
        let commandDate = dateProvider.now
        contextQueue.suspend()
        do {
            defer { contextQueue.resume() }
            monitor.addAction(type: .custom, name: "queued interaction")
            advanceTime(by: 2.seconds)
        }

        let action = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMActionEvent.self).first)
        XCTAssertEqual(action.session.id, initialSession.sessionID)
        XCTAssertEqual(action.date, commandDate.timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertNil(core.waitAndReturnSessionEndedMetricEvent())

        // Inactivity refreshes at receipt, including the two seconds spent waiting in the queue.
        let expiryReader = try XCTUnwrap(monitor as? Monitor)
        advanceTime(by: RUMSessionScope.Constants.sessionTimeoutDuration - 3.seconds)
        XCTAssertFalse(expiryReader.isSessionExpired(sessionID: action.session.id))
        advanceTime(by: 1.seconds)
        XCTAssertTrue(expiryReader.isSessionExpired(sessionID: action.session.id))
    }

    func testWhenResourceCompletionIsQueuedBeforeTimeout_butProcessedAfterTimeout_itKeepsResource() throws {
        try assertResourceSurvivesDelayedCompletion(sessionLimit: RUMSessionScope.Constants.sessionTimeoutDuration)
    }

    func testWhenResourceCompletionIsQueuedBeforeMaxDuration_butProcessedAfterMaxDuration_itKeepsResource() throws {
        try assertResourceSurvivesDelayedCompletion(sessionLimit: RUMSessionScope.Constants.sessionMaxDuration)
    }

    func testWhenResourceStartAndCompletionAreQueuedBeforeTimeout_itKeepsResourceInOriginalSession() throws {
        try assertResourceSurvivesDelayedCompletion(
            sessionLimit: RUMSessionScope.Constants.sessionTimeoutDuration,
            queueResourceStart: true
        )
    }

    func testWhenSessionIsNotSampled_thenMetricIsNotSent() throws {
        rumConfig.sessionSampleRate = 0
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        // When
        monitor.stopSession()

        // Then
        // Telemetry (e.g. API usage) is sampled independently of the RUM session, so it is excluded.
        let events = try core.waitAndReturnEventsData(ofFeature: RUMFeature.name, timeout: .now() + 0.5)
            .map { try RUMEventMatcher.fromJSONObjectData($0) }
            .filter { try $0.eventType() != "telemetry" }
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Reporting Session Attributes

    func testReportingSessionInformation() throws {
        var currentSessionID: String?
        rumConfig.trackBackgroundEvents = .mockRandom()
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")
        monitor.currentSessionID { currentSessionID = $0 }
        monitor.stopView(key: "key")

        // When
        monitor.stopSession()

        // Then
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        let expectedSessionID = try XCTUnwrap(currentSessionID)
        XCTAssertEqual(metric.session?.id, expectedSessionID)
        XCTAssertEqual(metric.attributes?.hasBackgroundEventsTrackingEnabled, rumConfig.trackBackgroundEvents)
    }

    func testTrackingSessionDuration() throws {
        let startTime = dateProvider.now
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        dateProvider.now += 5.seconds
        monitor.startView(key: "key1", name: "View1")
        dateProvider.now += 5.seconds
        monitor.startView(key: "key2", name: "View2")
        dateProvider.now += 5.seconds
        monitor.startView(key: "key3", name: "View3")
        dateProvider.now += 5.seconds
        monitor.stopView(key: "key3")

        // When
        monitor.stopSession()

        // Then
        let expectedDuration = dateProvider.now.timeIntervalSince(startTime)
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        DDAssertEqual(metricAttributes.duration?.nanosecondsToSeconds, expectedDuration, accuracy: 0.1)
    }

    func testTrackingViewsCount() throws {
        rumConfig.trackBackgroundEvents = true // enable tracking "Background" view
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        (0..<3).forEach { _ in
            // Simulate app in foreground:
            core.context = .mockWith(applicationStateHistory: .mockAppInForeground(since: dateProvider.now))

            // Track 2 distinct views:
            dateProvider.now += 5.seconds
            monitor.startView(key: "key1", name: "View1")
            dateProvider.now += 5.seconds
            monitor.startView(key: "key2", name: "View2")
            dateProvider.now += 5.seconds
            monitor.stopView(key: "key2")

            // Simulate app in background:
            core.context = .mockWith(applicationStateHistory: .mockAppInBackground(since: dateProvider.now))

            // Track resource without view:
            dateProvider.now += 1.seconds
            monitor.startResource(resourceKey: "resource", url: .mockAny())
            dateProvider.now += 1.seconds
            monitor.stopResource(resourceKey: "resource", response: .mockAny())
        }

        // When
        monitor.stopSession()

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertEqual(metricAttributes.viewsCount.total, 10)
        XCTAssertEqual(metricAttributes.viewsCount.applicationLaunch, 1)
        XCTAssertEqual(metricAttributes.viewsCount.background, 3)
        XCTAssertEqual(metricAttributes.viewsCount.byInstrumentation, ["manual": 6])
        XCTAssertEqual(metricAttributes.viewsCount.withHasReplay, 0)
    }

    func testTrackingSDKErrors() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        core.flush()
        (0..<9).forEach { _ in core.telemetry.error(id: "id1", message: .mockAny(), kind: "kind1", stack: .mockAny()) }
        (0..<8).forEach { _ in core.telemetry.error(id: "id2", message: .mockAny(), kind: "kind2", stack: .mockAny()) }
        (0..<7).forEach { _ in core.telemetry.error(id: "id3", message: .mockAny(), kind: "kind3", stack: .mockAny()) }
        (0..<6).forEach { _ in core.telemetry.error(id: "id4", message: .mockAny(), kind: "kind4", stack: .mockAny()) }
        (0..<5).forEach { _ in core.telemetry.error(id: "id5", message: .mockAny(), kind: "kind5", stack: .mockAny()) }
        (0..<4).forEach { _ in core.telemetry.error(id: "id6", message: .mockAny(), kind: "kind6", stack: .mockAny()) }
        core.flush()

        // When
        monitor.stopSession()

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertEqual(metricAttributes.sdkErrorsCount.total, 39, "It should count all SDK errors")
        XCTAssertEqual(
            metricAttributes.sdkErrorsCount.byKind,
            ["kind1": 9, "kind2": 8, "kind3": 7, "kind4": 6, "kind5": 5],
            "It should report TOP 5 error kinds"
        )
    }

    func testTrackingNTPOffset() throws {
        let offsetAtStart: TimeInterval = .mockRandom(min: -10, max: 10)
        let offsetAtEnd: TimeInterval = .mockRandom(min: -10, max: 10)

        core.context.serverTimeOffset = offsetAtStart
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        // When
        core.context.serverTimeOffset = offsetAtEnd
        monitor.stopSession()

        // Then
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        XCTAssertEqual(metric.attributes?.ntpOffset.atStart, offsetAtStart.dd.toInt64Milliseconds)
        XCTAssertEqual(metric.attributes?.ntpOffset.atEnd, offsetAtEnd.dd.toInt64Milliseconds)
    }

    func testTrackingNoViewEventsCount() throws {
        let expectedCount: Int = .mockRandom(min: 1, max: 5)
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")
        monitor.stopView(key: "key") // no active view

        // When
        (0..<expectedCount).forEach { _ in
            monitor.addAction(type: .tap, name: .mockAny())
            monitor.startResource(resourceKey: .mockAny(), url: .mockAny())
            monitor.addError(message: .mockAny())
            monitor._internal?.addLongTask(at: Date(), duration: 1)
        }
        monitor.stopSession()

        // Then
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        XCTAssertEqual(metric.attributes?.noViewEventsCount.actions, expectedCount)
        XCTAssertEqual(metric.attributes?.noViewEventsCount.resources, expectedCount)
        XCTAssertEqual(metric.attributes?.noViewEventsCount.errors, expectedCount)
        XCTAssertEqual(metric.attributes?.noViewEventsCount.longTasks, expectedCount)
    }

    func testTrackingLaunchInfo() throws {
        let launchDate = Date()
        let sdkInitDate = launchDate + 0.6
        core.context = .mockWith(
            sdkInitDate: sdkInitDate,
            launchInfo: .mockWith(
                launchReason: .prewarming,
                processLaunchDate: launchDate,
                didBecomeActiveDate: launchDate.addingTimeInterval(1.2),
                raw: .init(taskPolicyRole: "mock_task_policy", isPrewarmed: true)
            ),
            applicationStateHistory: .mockWith(initialState: .background, date: sdkInitDate)
        )
        rumConfig.bundle = .mockWith(UIApplicationSceneManifest: NSObject())

        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")
        monitor.stopView(key: "key")

        // When
        monitor.stopSession()

        // Then
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        XCTAssertEqual(metric.attributes?.launchInfo.launchReason, "prewarming")
        XCTAssertEqual(metric.attributes?.launchInfo.prewarmed, true)
        XCTAssertEqual(metric.attributes?.launchInfo.appStateAtSdkInit, "background")
        XCTAssertEqual(metric.attributes?.launchInfo.taskRole, "mock_task_policy")
        XCTAssertEqual(metric.attributes?.launchInfo.timeToDidBecomeActive, 1_200)
        XCTAssertEqual(metric.attributes?.launchInfo.timeToSdkInit, 600)
        XCTAssertEqual(metric.attributes?.launchInfo.hasScenesLifecycle, true)
    }

    func testTrackingLifecycleInfo() throws {
        let launchDate = dateProvider.now
        let sdkInitDate = launchDate + 0.6
        core.context = .mockWith(
            sdkInitDate: sdkInitDate,
            launchInfo: .mockWith(processLaunchDate: launchDate),
            applicationStateHistory: .mockWith(
                initialState: .background,
                date: launchDate,
                transitions: [(.active, sdkInitDate + 0.1)]
            )
        )

        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        dateProvider.now += 0.5
        monitor.startView(key: "key", name: "View")
        dateProvider.now += 0.5
        monitor.stopView(key: "key")

        // When
        monitor.stopSession()

        // Then
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        XCTAssertEqual(metric.attributes?.lifecycleInfo?.timeToSessionStart, 0)
        XCTAssertEqual(metric.attributes?.lifecycleInfo?.sessionsCount, 0)
        XCTAssertEqual(metric.attributes?.lifecycleInfo?.appStateAtSessionStart, "background")
        XCTAssertEqual(metric.attributes?.lifecycleInfo?.appStateAtSessionEnd, "active")
        XCTAssertEqual(metric.attributes?.lifecycleInfo?.foregroundCoverage, 0.3)
    }
}

// MARK: - Helpers

private extension RUMSessionEndedMetricIntegrationTests {
    /// Uses the real Core with an isolated context queue that the test can suspend to hold pending commands.
    func replaceCore(contextQueue: DispatchQueue) throws {
        let context = core.context
        try core.flushAndTearDown()
        core = DatadogCoreProxy(core: DatadogCore(
            directory: temporaryCoreDirectory,
            dateProvider: SystemDateProvider(),
            initialConsent: context.trackingConsent,
            performance: .mockAny(),
            httpClient: HTTPClientMock(),
            encryption: nil,
            contextProvider: DatadogContextProvider(context: context, queue: contextQueue),
            applicationVersion: context.version,
            maxBatchesPerUpload: 1,
            backgroundTasksEnabled: false
        ))
    }

    /// Delays resource commands across a session boundary while retaining their original issue times.
    func assertResourceSurvivesDelayedCompletion(sessionLimit: TimeInterval, queueResourceStart: Bool = false) throws {
        let contextQueue = DispatchQueue(label: "test.rum.delayed-resource")
        try replaceCore(contextQueue: contextQueue)
        RUM.enable(with: rumConfig, in: core)
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "first", name: "First")
        let initialSession = try RUMSessionMatcher
            .groupMatchersBySessions(core.waitAndReturnRUMEventMatchers())
            .takeSingle()
        let originalView = try XCTUnwrap(initialSession.views.first { $0.name == "First" })

        // Keep interacting before the maximum-duration boundary, without extending that limit.
        let resourceStart = sessionLimit - 2.seconds
        if sessionLimit == RUMSessionScope.Constants.sessionMaxDuration {
            let interactionInterval = RUMSessionScope.Constants.sessionTimeoutDuration - 1.seconds
            while monotonicClock.elapsedTime + interactionInterval < resourceStart {
                advanceTime(by: interactionInterval)
                monitor.addAction(type: .custom, name: "keep session active")
            }
        }
        advanceTime(by: resourceStart - monotonicClock.elapsedTime)
        let resourceDate = dateProvider.now
        if !queueResourceStart {
            monitor.startResource(resourceKey: "resource", url: URL(string: "https://example.com/resource")!)
            core.flush()
        }

        contextQueue.suspend()
        do {
            defer { contextQueue.resume() }
            if queueResourceStart {
                monitor.startResource(resourceKey: "resource", url: URL(string: "https://example.com/resource")!)
            }
            advanceTime(by: 1.seconds)
            monitor.stopResource(resourceKey: "resource", statusCode: 200, kind: .native)
            advanceTime(by: 2.seconds)
        }

        let resources = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMResourceEvent.self)
        XCTAssertEqual(resources.count, 1)
        let resource = try XCTUnwrap(resources.first)
        XCTAssertEqual(resource.session.id, initialSession.sessionID)
        XCTAssertEqual(resource.view.id, originalView.viewID)
        XCTAssertEqual(resource.date, resourceDate.timeIntervalSince1970.dd.toInt64Milliseconds)
        XCTAssertEqual(resource.resource.duration, 1.seconds.dd.toInt64Nanoseconds)
        XCTAssertNil(core.waitAndReturnSessionEndedMetricEvent())

        // A subsequent command issued after the boundary still renews the session.
        monitor.addAction(type: .custom, name: "after session expiry")
        let action = try XCTUnwrap(core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: RUMActionEvent.self).last)
        XCTAssertNotEqual(action.session.id, initialSession.sessionID)
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        XCTAssertEqual(metric.session?.id, initialSession.sessionID)
    }

    /// Advances both mocked clocks; commands retain the elapsed-time reading captured at receipt.
    func advanceTime(by interval: TimeInterval) {
        monotonicClock.advance(by: interval)
        dateProvider.now.addTimeInterval(interval)
    }
}

private extension DatadogCoreProxy {
    func waitAndReturnSessionEndedMetricEvent() -> TelemetryDebugEvent? {
        let events = waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        return events.first(where: { $0.telemetry.message == "[Mobile Metric] \(SessionEndedMetric.Constants.name)" })
    }
}

private extension TelemetryDebugEvent {
    var attributes: SessionEndedMetric.Attributes? {
        return telemetry.telemetryInfo[SessionEndedMetric.Constants.rseKey] as? SessionEndedMetric.Attributes
    }
}

private extension Int64 {
    var nanosecondsToSeconds: TimeInterval { TimeInterval.ddFromNanoseconds(self) }
}
