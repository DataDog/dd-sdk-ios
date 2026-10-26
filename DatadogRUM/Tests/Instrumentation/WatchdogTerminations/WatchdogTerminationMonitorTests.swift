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

        // RUM view update before start, this must be ignored
        let viewEvent1: RUMViewEvent = .mockRandom()
        sut.update(viewEvent: viewEvent1)

        // monitor reveives the launch report
        _ = sut.receive(message: .context(featureScope.contextMock), from: NOPDatadogCore())

        // Flush the queue to ensure the monitor has transitioned to `.started`
        // before updating the view event. Without this, the update would be
        // dropped because the monitor is still in `.starting` state.
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

        // RUM view update before start, this must be ignored
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
        featureScope.rumDataStore.setValue(true, forKey: .watchdogRUMSessionStopped)

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
