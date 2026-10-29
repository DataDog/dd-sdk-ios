/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

final class WatchdogTerminationMonitorTests: XCTestCase {
    let featureScope = FeatureScopeMock()

    // swiftlint:disable implicitly_unwrapped_optional
    var sut: WatchdogTerminationMonitor!
    var reporter: WatchdogTerminationReporterMock!
    // swiftlint:enable implicitly_unwrapped_optional

    func testApplicationWasInForeground_WatchdogTermination() throws {
        let didSend = self.expectation(description: "Watchdog termination was reported")

        // app starts - use a controlled queue so we can flush its state transitions
        let firstSessionQueue = DispatchQueue(label: "com.datadoghq.tests.first-session")
        given(
            isSimulator: false,
            isDebugging: false,
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            vendorId: "foo",
            processId: UUID(),
            didCrash: false,
            didSend: didSend,
            queue: firstSessionQueue
        )

        // RUM view update before start, this must wait for the previous-launch check
        let viewEvent1: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent1)

        // monitor reveives the launch report
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        // Finish checking the previous launch before updating the current view.
        firstSessionQueue.sync {}

        // RUM view update after start
        let viewEvent2: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent2)

        // watchdog termination happens here which causes app launch
        given(
            isSimulator: false,
            isDebugging: false,
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            vendorId: "foo",
            processId: UUID(),
            didCrash: false,
            didSend: didSend
        )

        // RUM view update before start, this must wait for the previous-launch check
        let viewEvent3: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent3)

        // monitor reveives the launch report
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        waitForExpectations(timeout: 1)
        XCTAssertEqual(reporter.sendParams?.viewEvent.view.id, viewEvent2.view.id)
    }

    func testGivenSessionWasStopped_whenWatchdogTerminationOccurs_itIsNotReported() throws {
        let didSend = self.expectation(description: "Watchdog termination was reported")
        didSend.isInverted = true

        // app starts
        let firstSessionQueue = DispatchQueue(label: "com.datadoghq.tests.first-session")
        givenDefaultApp(didSend: didSend, queue: firstSessionQueue)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        firstSessionQueue.sync {}

        // RUM view is tracked, then the session is stopped
        let sessionID: UUID = .mockRandom()
        sut.update(viewEvent: .mockRandomWith(sessionID: sessionID))
        sut.sessionDidStop(sessionID: sessionID.uuidString.lowercased())
        sut.update(viewEvent: .mockRandomWith(sessionID: sessionID)) // the last update of the stopped view

        // watchdog termination happens here which causes app launch
        givenDefaultApp(didSend: didSend)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        waitForExpectations(timeout: 0.5)
        XCTAssertNil(reporter.sendParams, "A Watchdog Termination after `stopSession()` must not be reported in the stopped session")
    }

    func testGivenSessionWasStopped_whenViewOfAnotherSessionIsTracked_itReportsWatchdogTerminationInThatView() throws {
        let didSend = self.expectation(description: "Watchdog termination was reported")

        // app starts
        let firstSessionQueue = DispatchQueue(label: "com.datadoghq.tests.first-session")
        givenDefaultApp(didSend: didSend, queue: firstSessionQueue)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        firstSessionQueue.sync {}

        // RUM session is stopped, then tracking resumes in a new session
        let stoppedSessionID: UUID = .mockRandom()
        sut.update(viewEvent: .mockRandomWith(sessionID: stoppedSessionID))
        sut.sessionDidStop(sessionID: stoppedSessionID.uuidString.lowercased())
        let resumedView: RUMViewEvent = .mockRandomWith(sessionID: .mockRandom())
        sut.update(viewEvent: resumedView)
        sut.update(viewEvent: .mockRandomWith(sessionID: stoppedSessionID)) // a late update of the stopped view

        // watchdog termination happens here which causes app launch
        givenDefaultApp(didSend: didSend)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        waitForExpectations(timeout: 1)
        XCTAssertEqual(reporter.sendParams?.viewEvent.view.id, resumedView.view.id)
    }

    func testGivenTwoSessionsWereStopped_whenLateViewUpdateOfTheFirstOneArrives_itIsNotSaved() throws {
        let didSend = self.expectation(description: "Watchdog termination was reported")
        didSend.isInverted = true

        // app starts
        let firstSessionQueue = DispatchQueue(label: "com.datadoghq.tests.first-session")
        givenDefaultApp(didSend: didSend, queue: firstSessionQueue)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        firstSessionQueue.sync {}

        // A session is stopped while its view waits for a resource, then a second session is tracked and stopped
        let firstSessionID: UUID = .mockRandom()
        let secondSessionID: UUID = .mockRandom()
        sut.update(viewEvent: .mockRandomWith(sessionID: firstSessionID))
        sut.sessionDidStop(sessionID: firstSessionID.uuidString.lowercased())
        sut.update(viewEvent: .mockRandomWith(sessionID: secondSessionID))
        sut.sessionDidStop(sessionID: secondSessionID.uuidString.lowercased())
        sut.update(viewEvent: .mockRandomWith(sessionID: firstSessionID)) // the resource completes in the first session

        // watchdog termination happens here which causes app launch
        givenDefaultApp(didSend: didSend)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        waitForExpectations(timeout: 0.5)
        XCTAssertNil(reporter.sendParams, "A late view update of a stopped session must not resume reporting")
    }

    func testGivenSessionWasStoppedInPreviousProcess_whenViewIsTracked_itReportsWatchdogTerminationInThatView() throws {
        let didSend = self.expectation(description: "Watchdog termination was reported")

        // the previous process stopped the session
        featureScope.rumDataStore.setValue(Optional<RUMViewEvent>.none, forKey: .watchdogRUMViewEvent)

        // app starts
        let firstSessionQueue = DispatchQueue(label: "com.datadoghq.tests.first-session")
        givenDefaultApp(didSend: didSend, queue: firstSessionQueue)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        firstSessionQueue.sync {}

        // RUM view is tracked
        let viewEvent: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent)

        // watchdog termination happens here which causes app launch
        givenDefaultApp(didSend: didSend)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        waitForExpectations(timeout: 1)
        XCTAssertEqual(reporter.sendParams?.viewEvent.view.id, viewEvent.view.id)
    }

    func testGivenSessionWasStoppedWhileMonitorStarts_whenWatchdogTerminationOccurs_itIsNotReported() throws {
        let didSend = self.expectation(description: "Watchdog termination was reported")
        didSend.isInverted = true

        // the previous process saved a view
        featureScope.rumDataStore.setValue(RUMViewEvent.mockRandom(), forKey: .watchdogRUMViewEvent)

        // app starts, and the monitor is still starting when the session is stopped
        let firstSessionQueue = DispatchQueue(label: "com.datadoghq.tests.first-session")
        givenDefaultApp(didSend: didSend, queue: firstSessionQueue)
        firstSessionQueue.suspend()
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        XCTAssertEqual(sut.currentState, .starting)
        let sessionID: UUID = .mockRandom()
        sut.update(viewEvent: .mockRandomWith(sessionID: sessionID))
        sut.sessionDidStop(sessionID: sessionID.uuidString.lowercased())
        firstSessionQueue.resume()
        firstSessionQueue.sync {}
        XCTAssertEqual(sut.currentState, .started)

        // watchdog termination happens here which causes app launch
        givenDefaultApp(didSend: didSend)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        waitForExpectations(timeout: 0.5)
        XCTAssertNil(reporter.sendParams, "A stop received while the monitor starts must be saved once it has started")
    }

    func testGivenSessionWasStoppedInPreviousProcess_whenViewIsTrackedWhileMonitorStarts_itReportsWatchdogTerminationInThatView() throws {
        let didSend = self.expectation(description: "Watchdog termination was reported")

        // the previous process stopped the session
        featureScope.rumDataStore.setValue(Optional<RUMViewEvent>.none, forKey: .watchdogRUMViewEvent)

        // app starts, and the monitor is still starting when a view is tracked
        let firstSessionQueue = DispatchQueue(label: "com.datadoghq.tests.first-session")
        givenDefaultApp(didSend: didSend, queue: firstSessionQueue)
        firstSessionQueue.suspend()
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        XCTAssertEqual(sut.currentState, .starting)
        let viewEvent: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent)
        firstSessionQueue.resume()
        firstSessionQueue.sync {}
        XCTAssertEqual(sut.currentState, .started)

        // watchdog termination happens here which causes app launch
        givenDefaultApp(didSend: didSend)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        waitForExpectations(timeout: 1)
        XCTAssertEqual(reporter.sendParams?.viewEvent.view.id, viewEvent.view.id, "A view tracked while the monitor starts must be saved once it has started")
    }

    func testGivenResumedViewDuringStartup_whenStoppedSessionUpdates_itPreservesTheResumedView() throws {
        // Given
        let queue = DispatchQueue(label: "com.datadoghq.tests.startup")
        givenDefaultApp(didSend: XCTestExpectation(description: "No watchdog report expected"), queue: queue)
        queue.suspend()
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        let stoppedSessionID: UUID = .mockRandom()
        sut.sessionDidStop(sessionID: stoppedSessionID.uuidString.lowercased())
        let resumedView: RUMViewEvent = .mockRandomWith(sessionID: .mockRandom())
        sut.update(viewEvent: resumedView)

        // When
        sut.update(viewEvent: .mockRandomWith(sessionID: stoppedSessionID))
        queue.resume()
        queue.sync {}

        // Then
        var savedView: RUMViewEvent?
        featureScope.rumDataStore.value(forKey: .watchdogRUMViewEvent) { savedView = $0 }
        let view = try XCTUnwrap(savedView)
        XCTAssertEqual(view.view.id, resumedView.view.id)
    }

    func testGivenManyStoppedSessions_whenOldestSessionUpdates_itDoesNotResumeTracking() throws {
        // Given
        givenDefaultApp(didSend: XCTestExpectation(description: "No watchdog report expected"))
        sut.currentState = .started
        let sessions: [UUID] = (0..<20).map { _ in .mockRandom() }
        for sessionID in sessions {
            sut.update(viewEvent: .mockRandomWith(sessionID: sessionID))
            sut.sessionDidStop(sessionID: sessionID.uuidString.lowercased())
        }
        let oldestSessionID = try XCTUnwrap(sessions.first)

        // When
        sut.update(viewEvent: .mockRandomWith(sessionID: oldestSessionID))

        // Then
        var savedView: RUMViewEvent??
        featureScope.rumDataStore.value(forKey: .watchdogRUMViewEvent) { savedView = $0 }
        XCTAssertNil(try XCTUnwrap(savedView))
    }

    func testGivenSessionStopsDuringStartup_whenItsScopeCompletes_itDoesNotRestoreThePendingView() throws {
        // Given
        let queue = DispatchQueue(label: "com.datadoghq.tests.startup")
        givenDefaultApp(didSend: XCTestExpectation(description: "No watchdog report expected"), queue: queue)
        queue.suspend()
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        let view: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: view)

        // When
        sut.sessionDidStop(sessionID: view.session.id)
        sut.sessionDidComplete(sessionID: view.session.id)
        queue.resume()
        queue.sync {}

        // Then
        var savedView: RUMViewEvent??
        featureScope.rumDataStore.value(forKey: .watchdogRUMViewEvent) { savedView = $0 }
        XCTAssertNil(try XCTUnwrap(savedView))
    }

    func testGivenStoppedSession_whenReplacementViewWriteFails_itDoesNotReportTheStaleView() throws {
        // Given
        let queue = DispatchQueue(label: "com.datadoghq.tests.persistence")
        givenDefaultApp(didSend: XCTestExpectation(description: "No watchdog report expected"), queue: queue)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        queue.sync {}
        let view: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: view)
        sut.sessionDidStop(sessionID: view.session.id)
        let store = try XCTUnwrap(featureScope.dataStore as? DataStoreMock)
        store.failingWriteKeys = [RUMDataStore.Key.watchdogRUMViewEvent.rawValue]

        // When
        sut.update(viewEvent: .mockRandomWith(sessionID: .mockRandom()))
        givenDefaultApp(didSend: XCTestExpectation(description: "No watchdog report expected"), queue: queue)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        queue.sync {}

        // Then
        XCTAssertEqual(sut.currentState, .started)
        XCTAssertNil(reporter.sendParams)
    }

    func testGivenStopBeforeFirstContext_whenMonitorStarts_itReportsPreviousLaunchThenSavesStop() throws {
        // Given
        let queue = DispatchQueue(label: "com.datadoghq.tests.startup")
        givenDefaultApp(didSend: XCTestExpectation(description: "Previous launch"), queue: queue)
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        queue.sync {}
        let previousView: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: previousView)
        givenDefaultApp(didSend: XCTestExpectation(description: "Previous launch reported"), queue: queue)
        let stoppedView: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: stoppedView)
        sut.sessionDidStop(sessionID: stoppedView.session.id)
        sut.update(viewEvent: stoppedView)
        sut.sessionDidComplete(sessionID: stoppedView.session.id)

        // When
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        queue.sync {}

        // Then
        let report = try XCTUnwrap(reporter.sendParams)
        XCTAssertEqual(report.viewEvent.view.id, previousView.view.id)
        var savedView: RUMViewEvent??
        featureScope.rumDataStore.value(forKey: .watchdogRUMViewEvent) { savedView = $0 }
        XCTAssertNil(try XCTUnwrap(savedView))
    }

    func testGivenResumedViewBeforeFirstContext_whenStoppedSessionUpdates_itSavesResumedView() throws {
        // Given
        let queue = DispatchQueue(label: "com.datadoghq.tests.startup")
        featureScope.rumDataStore.setValue(Optional<RUMViewEvent>.none, forKey: .watchdogRUMViewEvent)
        givenDefaultApp(didSend: XCTestExpectation(description: "No watchdog report expected"), queue: queue)
        let stoppedView: RUMViewEvent = .mockRandom()
        sut.sessionDidStop(sessionID: stoppedView.session.id)
        let resumedView: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: resumedView)
        sut.update(viewEvent: stoppedView)
        var beforeStart: RUMViewEvent??
        featureScope.rumDataStore.value(forKey: .watchdogRUMViewEvent) { beforeStart = $0 }
        XCTAssertNil(try XCTUnwrap(beforeStart))

        // When
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        queue.sync {}

        // Then
        var savedView: RUMViewEvent?
        featureScope.rumDataStore.value(forKey: .watchdogRUMViewEvent) { savedView = $0 }
        let view = try XCTUnwrap(savedView)
        XCTAssertEqual(view.view.id, resumedView.view.id)
    }

    func testGivenMonitorStoppedBeforeFirstContext_whenContextArrives_itIgnoresPendingUpdates() throws {
        // Given
        let queue = DispatchQueue(label: "com.datadoghq.tests.startup")
        let previousView: RUMViewEvent = .mockRandom()
        featureScope.rumDataStore.setValue(previousView, forKey: .watchdogRUMViewEvent)
        givenDefaultApp(didSend: XCTestExpectation(description: "No watchdog report expected"), queue: queue)
        sut.sessionDidStop(sessionID: previousView.session.id)
        sut.update(viewEvent: .mockRandom())
        sut.stop()

        // When
        sut.sessionDidStop(sessionID: UUID.mockRandom().uuidString.lowercased())
        sut.update(viewEvent: .mockRandom())
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        queue.sync {}

        // Then
        XCTAssertEqual(sut.currentState, .stopped)
        var savedView: RUMViewEvent?
        featureScope.rumDataStore.value(forKey: .watchdogRUMViewEvent) { savedView = $0 }
        let view = try XCTUnwrap(savedView)
        XCTAssertEqual(view.view.id, previousView.view.id)
    }

    func testGivenMonitorStarting_whenStopped_itDoesNotSavePendingUpdates() throws {
        // Given
        let queue = DispatchQueue(label: "com.datadoghq.tests.startup")
        let previousView: RUMViewEvent = .mockRandom()
        featureScope.rumDataStore.setValue(previousView, forKey: .watchdogRUMViewEvent)
        givenDefaultApp(didSend: XCTestExpectation(description: "No watchdog report expected"), queue: queue)
        queue.suspend()
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())
        sut.sessionDidStop(sessionID: previousView.session.id)
        sut.update(viewEvent: .mockRandom())

        // When
        sut.stop()
        queue.resume()
        queue.sync {}

        // Then
        XCTAssertEqual(sut.currentState, .stopped)
        var savedView: RUMViewEvent?
        featureScope.rumDataStore.value(forKey: .watchdogRUMViewEvent) { savedView = $0 }
        let view = try XCTUnwrap(savedView)
        XCTAssertEqual(view.view.id, previousView.view.id)
    }

    // MARK: Helpers

    private func givenDefaultApp(didSend: XCTestExpectation, queue: DispatchQueue = AppStateManager.defaultQueue) {
        given(
            isSimulator: false,
            isDebugging: false,
            appVersion: "1.0.0",
            osVersion: "1.0.0",
            systemBootTime: 1.0,
            vendorId: "foo",
            processId: UUID(),
            didCrash: false,
            didSend: didSend,
            queue: queue
        )
    }

    func given(
        isSimulator: Bool,
        isDebugging: Bool,
        appVersion: String,
        osVersion: String,
        systemBootTime: TimeInterval,
        vendorId: String?,
        processId: UUID,
        didCrash: Bool,
        didSend: XCTestExpectation,
        queue: DispatchQueue = AppStateManager.defaultQueue
    ) {
        let deviceInfo: DeviceInfo = .mockWith(
            isSimulator: isSimulator,
            vendorId: vendorId,
            isDebugging: false,
            systemBootTime: systemBootTime
        )

        featureScope.contextMock.version = appVersion
        featureScope.contextMock.device = deviceInfo
        featureScope.contextMock.set(additionalContext: LaunchReport(didCrash: didCrash))

        let appStateManager = AppStateManager(
            featureScope: featureScope,
            processId: processId,
            syntheticsEnvironment: false,
            queue: queue
        )

        let checker = WatchdogTerminationChecker(appStateManager: appStateManager, featureScope: featureScope)

        reporter = WatchdogTerminationReporterMock(didSend: didSend)

        sut = WatchdogTerminationMonitor(
            appStateManager: appStateManager,
            checker: checker,
            storage: NOPDatadogCore().storage,
            feature: featureScope,
            reporter: reporter
        )
    }
}
