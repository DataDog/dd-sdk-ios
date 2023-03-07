/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapPushNextScreenButton() {
        buttons["Push Next Screen"].safeTap(within: 5)
    }

    func tapBackButton() {
        navigationBars["Screen 4"].buttons["Screen 3"].safeTap()
    }

    func tapPopToTheFirstScreenButton() {
        buttons["Pop To The First Screen"].safeTap()
    }

    func swipeInteractiveBackGesture() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0, dy: 0.5))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.80, dy: 0.5))
        coordinate1.press(forDuration: 0.5, thenDragTo: coordinate2)
    }
}

class RUMNavigationControllerScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMNavigationControllerScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMNavigationControllerScenario",
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

        try app.endRUMSession()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        sendCIAppLog(session)

        let applicationLaunchView = try XCTUnwrap(session.applicationLaunchView)
        XCTAssertEqual(applicationLaunchView.actionEvents[0].action.type, .applicationStart)
        XCTAssertGreaterThan(applicationLaunchView.actionEvents[0].action.loadingTime!, 0)

        let visits = session.viewVisits
        XCTAssertEqual(visits[0].name, "Screen1")
        XCTAssertEqual(visits[0].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[0]) // go to "Screen2"

        XCTAssertEqual(session.viewVisits[1].name, "Screen2")
        XCTAssertEqual(session.viewVisits[1].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[1])// go to "Screen3"

        XCTAssertEqual(session.viewVisits[2].name, "Screen3")
        XCTAssertEqual(session.viewVisits[2].path, "Runner.RUMNCSScreen3ViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[2])// go to "Screen4"

        XCTAssertEqual(session.viewVisits[3].name, "Screen4")
        XCTAssertEqual(session.viewVisits[3].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[3])// go to "Screen3"

        XCTAssertEqual(session.viewVisits[4].name, "Screen3")
        XCTAssertEqual(session.viewVisits[4].path, "Runner.RUMNCSScreen3ViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[4])// go to "Screen1"

        XCTAssertEqual(session.viewVisits[5].name, "Screen1")
        XCTAssertEqual(session.viewVisits[5].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[5])// go to "Screen2"

        XCTAssertEqual(session.viewVisits[6].name, "Screen2")
        XCTAssertEqual(session.viewVisits[6].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[6])// swipe back to "Screen1"

        XCTAssertEqual(session.viewVisits[7].name, "Screen1")
        XCTAssertEqual(session.viewVisits[7].path, "UIViewController")
    }
}
