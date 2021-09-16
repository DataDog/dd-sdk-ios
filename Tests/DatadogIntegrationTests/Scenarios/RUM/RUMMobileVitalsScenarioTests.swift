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

        // Wait for the app to settle down for 3 second
        Thread.sleep(forTimeInterval: 3.0)

        app.tapNoOpButton()
        app.tapBlockMainThreadButton()
        app.tapNoOpButton()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            let visitCount = try RUMSessionMatcher.singleSession(from: requests)?.viewVisits.count
            return visitCount == 1
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))

        XCTAssertEqual(session.viewVisits[0].viewEvents.count, 2)
        let event1 = session.viewVisits[0].viewEvents[0].view
        let event2 = session.viewVisits[0].viewEvents[1].view

        let longTask1 = try XCTUnwrap(event1.longTask)
        let longTask2 = try XCTUnwrap(event2.longTask)
        XCTAssertEqual(longTask1.count + 1, longTask2.count)

        let cpuTicksPerSec2 = try XCTUnwrap(event2.cpuTicksPerSecond)
        XCTAssertGreaterThan(cpuTicksPerSec2, 0.0)

        let fps2 = try XCTUnwrap(event2.refreshRateAverage)
        XCTAssertGreaterThan(fps2, 0.0)
    }
}
