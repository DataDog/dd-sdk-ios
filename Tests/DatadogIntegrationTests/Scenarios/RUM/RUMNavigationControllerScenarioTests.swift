/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapPushNextScreenButton() {
        buttons["Push Next Screen"].tap()
    }

    func tapBackButton() {
        navigationBars["Screen 4"].buttons["Screen 3"].tap()
    }

    func tapPopToTheFirstScreenButton() {
        buttons["Pop To The First Screen"].tap()
    }

    func swipeInteractiveBackGesture() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0, dy: 0.5))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.75, dy: 0.5))
        coordinate1.press(forDuration: 0.5, thenDragTo: coordinate2)
    }
}

class RUMNavigationControllerScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMNavigationControllerScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenario: RUMNavigationControllerScenario.self,
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        ) // start on "Screen1"

        app.tapPushNextScreenButton() // go to "Screen2"
        app.tapPushNextScreenButton() // go to "Screen3"
        app.tapPushNextScreenButton() // go to "Screen4"
        app.tapBackButton() // go to "Screen3"
        app.tapPopToTheFirstScreenButton() // go to "Screen1"
        app.tapPushNextScreenButton() // go to "Screen2"
        app.swipeInteractiveBackGesture() // swipe back to "Screen1"

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.from(requests: requests)?.viewVisits.count == 8
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.from(requests: recordedRUMRequests))
        XCTAssertEqual(session.viewVisits[0].path, "Screen1")
        XCTAssertEqual(session.viewVisits[0].actionEvents[0].action.type, .applicationStart)
        XCTAssertEqual(session.viewVisits[1].path, "Screen2")
        XCTAssertEqual(session.viewVisits[2].path, "Screen3")
        XCTAssertEqual(session.viewVisits[3].path, "Screen4")
        XCTAssertEqual(session.viewVisits[4].path, "Screen3")
        XCTAssertEqual(session.viewVisits[5].path, "Screen1")
        XCTAssertEqual(session.viewVisits[6].path, "Screen2")
        XCTAssertEqual(session.viewVisits[7].path, "Screen1")
    }
}
