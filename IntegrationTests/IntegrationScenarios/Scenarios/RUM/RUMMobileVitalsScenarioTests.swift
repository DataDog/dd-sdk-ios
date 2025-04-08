/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import TestUtilities
import XCTest

private extension ExampleApplication {
    func tapNoOpButton() {
        buttons["No-op"].tap()
    }

    func tapBlockMainThreadButton() {
        buttons["Block Main Thread"].tap()
    }

    func tapStartNewViewButton() {
        buttons["Start New View"].tap()
    }
}

class RUMMobileVitalsScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMMobileVitalsScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMMobileVitalsScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        // NOTE: RUMM-1086 even tapNoOpButton() can take up to 0.25sec in my local,
        // therefore i used `threshold: 2.5` for long tasks in this scenario
        app.tapNoOpButton()
        app.tapBlockMainThreadButton() // block main thread for 3 seconds
        app.tapNoOpButton()
        app.tapBlockMainThreadButton()
        app.tapNoOpButton()

        try app.endRUMSession()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        sendCIAppLog(session)

        let views = try session.views.dropApplicationLaunchView()
        let lastViewEvent = try XCTUnwrap(views.first?.viewEvents.last)

        let cpuTicksPerSecond = try XCTUnwrap(lastViewEvent.view.cpuTicksPerSecond)
        XCTAssertGreaterThan(cpuTicksPerSecond, 0.0)

        let refreshRateAverage = try XCTUnwrap(lastViewEvent.view.refreshRateAverage)
        XCTAssertGreaterThan(refreshRateAverage, 0.0)

        let longTaskEvents = views[0].longTaskEvents
        XCTAssertEqual(longTaskEvents.count, 2)

        let longTask1 = longTaskEvents[0]
        XCTAssertGreaterThan(longTask1.longTask.duration, 3_000_000_000)
        let longTask2 = longTaskEvents[1]
        XCTAssertGreaterThan(longTask2.longTask.duration, 3_000_000_000)
    }

    func testRUMShortTimeSpentCPUScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMMobileVitalsScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        // NOTE: RUMM-1086 even tapNoOpButton() can take up to 0.25sec in my local,
        // therefore i used `threshold: 2.5` for long tasks in this scenario
        app.tapStartNewViewButton()
        try app.endRUMSession()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        sendCIAppLog(session)

        let views = try session.views.dropApplicationLaunchView()
        let lastViewEvent = try XCTUnwrap(views[1].viewEvents.last)
        let oneSecond: TimeInterval = 1

        // When
        XCTAssertLessThan(lastViewEvent.view.timeSpent, oneSecond.toInt64Nanoseconds, "When view lasts less than 1s")

        // Then
        XCTAssertNil(lastViewEvent.view.cpuTicksPerSecond, "It should have no CPU ticks reported")
    }
}
