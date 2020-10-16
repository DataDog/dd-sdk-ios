/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapTapBarButton(named tabName: String) {
        tabBars.buttons[tabName].tap()
    }

    func tapButton(named buttonName: String) {
        staticTexts[buttonName].tap()
    }

    func tapBackButton() {
        navigationBars["UIView"].buttons.firstMatch.tap()
    }
}

class RUMTabBarControllerScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMTabBarScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenario: RUMTabBarAutoInstrumentationScenario.self,
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        ) // start on "Screen A"

        app.tapTapBarButton(named: "Tab B") // go to "Screen B1"
        app.tapButton(named: "Screen B1") // go to "Screen B2"
        app.tapBackButton() // go to "Screen B1"
        app.tapTapBarButton(named: "Tab C") // go to "Screen C1"
        app.tapButton(named: "Screen C1") // go to "Screen C2"
        app.tapTapBarButton(named: "Tab A") // go to "Screen A"
        app.tapTapBarButton(named: "Tab C") // go to "Screen C2"
        app.tapTapBarButton(named: "Tab C") // go to "Screen C1"

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.from(requests: requests)?.viewVisits.count == 9
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.from(requests: recordedRUMRequests))
        XCTAssertEqual(session.viewVisits[0].path, "Screen A")
        XCTAssertEqual(session.viewVisits[0].actionEvents[0].action.type, .applicationStart)
        XCTAssertEqual(session.viewVisits[1].path, "Screen B1")
        XCTAssertEqual(session.viewVisits[2].path, "Screen B2")
        XCTAssertEqual(session.viewVisits[3].path, "Screen B1")
        XCTAssertEqual(session.viewVisits[4].path, "Screen C1")
        XCTAssertEqual(session.viewVisits[5].path, "Screen C2")
        XCTAssertEqual(session.viewVisits[6].path, "Screen A")
        XCTAssertEqual(session.viewVisits[7].path, "Screen C2")
        XCTAssertEqual(session.viewVisits[8].path, "Screen C1")
    }
}
