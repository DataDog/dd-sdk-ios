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
        // therefore i used `threshold: 1.0` for long tasks in this scenario
        app.tapNoOpButton()
        app.tapBlockMainThreadButton()
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

        for event in session.viewVisits[0].viewEvents {
            let longTask = try XCTUnwrap(event.view.longTask)
            print(longTask.count)
        }

        XCTAssertEqual(session.viewVisits[0].viewEvents.count, 5)
        let event1 = session.viewVisits[0].viewEvents[0].view
        let event2 = session.viewVisits[0].viewEvents[1].view
        let event3 = session.viewVisits[0].viewEvents[2].view
        let event4 = session.viewVisits[0].viewEvents[3].view
        let event5 = session.viewVisits[0].viewEvents[4].view

        let longTask1 = try XCTUnwrap(event1.longTask) // start view
        let longTask2 = try XCTUnwrap(event2.longTask) // no-op action
        let longTask3 = try XCTUnwrap(event3.longTask) // block main thread
        let longTask4 = try XCTUnwrap(event4.longTask) // no-op action
        let longTask5 = try XCTUnwrap(event5.longTask) // block main thread

        XCTAssertEqual(longTask1.count, longTask2.count)
        XCTAssertEqual(longTask2.count + 1, longTask3.count)
        XCTAssertEqual(longTask3.count, longTask4.count)
        XCTAssertEqual(longTask4.count + 1, longTask5.count)

        let cpuTicksPerSec2 = try XCTUnwrap(event2.cpuTicksPerSecond)
        XCTAssertGreaterThan(cpuTicksPerSec2, 0.0)

        let fps2 = try XCTUnwrap(event2.refreshRateAverage)
        XCTAssertGreaterThan(fps2, 0.0)
    }
}
