/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapNoOpButton() {
        buttons["No-op"].tap()
    }

    func tapBlockMainThreadButton() {
        buttons["Block Main Thread"].tap()
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

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            let eventCount = try RUMSessionMatcher.singleSession(from: requests)?.longTaskEventMatchers.count
            return eventCount == 2
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))

        XCTAssertEqual(session.viewVisits[0].viewEvents.count, 5)

        let viewLongTask1 = try XCTUnwrap(session.viewVisits[0].viewEvents[0].view.longTask) // start view
        let viewLongTask2 = try XCTUnwrap(session.viewVisits[0].viewEvents[1].view.longTask) // no-op action
        let viewLongTask3 = try XCTUnwrap(session.viewVisits[0].viewEvents[2].view.longTask) // block main thread
        let viewLongTask4 = try XCTUnwrap(session.viewVisits[0].viewEvents[3].view.longTask) // no-op action
        let viewLongTask5 = try XCTUnwrap(session.viewVisits[0].viewEvents[4].view.longTask) // block main thread

        XCTAssertEqual(viewLongTask1.count, viewLongTask2.count, "Add action event should NOT increment long task count")
        XCTAssertEqual(viewLongTask2.count + 1, viewLongTask3.count, "Block main thread button should increment long task count")
        XCTAssertEqual(viewLongTask3.count, viewLongTask4.count, "Add action event should NOT increment long task count")
        XCTAssertEqual(viewLongTask4.count + 1, viewLongTask5.count, "Block main thread button should increment long task count")

        let viewEvent = session.viewVisits[0].viewEvents[2].view

        let cpuTicksPerSec2 = try XCTUnwrap(viewEvent.cpuTicksPerSecond)
        XCTAssertGreaterThan(cpuTicksPerSec2, 0.0)

        let fps2 = try XCTUnwrap(viewEvent.refreshRateAverage)
        XCTAssertGreaterThan(fps2, 0.0)

        let longTaskEvents = session.viewVisits[0].longTaskEvents
        XCTAssertEqual(longTaskEvents.count, 2)

        let longTask1 = longTaskEvents[0]
        XCTAssertGreaterThan(longTask1.longTask.duration, 3_000_000_000)
        let longTask2 = longTaskEvents[1]
        XCTAssertGreaterThan(longTask2.longTask.duration, 3_000_000_000)
    }
}
