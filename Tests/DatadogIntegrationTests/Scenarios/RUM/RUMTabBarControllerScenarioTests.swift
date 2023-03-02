/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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
            testScenarioClassName: "RUMTabBarAutoInstrumentationScenario",
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
        XCTAssertEqual(session.viewVisits[0].name, "Screen A")
        XCTAssertEqual(session.viewVisits[0].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[0]) // go to "Screen B1"

        XCTAssertEqual(session.viewVisits[1].name, "Screen B1")
        XCTAssertEqual(session.viewVisits[1].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[1])// go to "Screen B2"

        XCTAssertEqual(session.viewVisits[2].name, "Screen B2")
        XCTAssertEqual(session.viewVisits[2].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[2])// go to "Screen B1"

        XCTAssertEqual(session.viewVisits[3].name, "Screen B1")
        XCTAssertEqual(session.viewVisits[3].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[3])// go to "Screen C1"

        XCTAssertEqual(session.viewVisits[4].name, "Screen C1")
        XCTAssertEqual(session.viewVisits[4].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[4])// go to "Screen C2"

        XCTAssertEqual(session.viewVisits[5].name, "Screen C2")
        XCTAssertEqual(session.viewVisits[5].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[5])// go to "Screen A"

        XCTAssertEqual(session.viewVisits[6].name, "Screen A")
        XCTAssertEqual(session.viewVisits[6].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[6])// go to "Screen C2"

        XCTAssertEqual(session.viewVisits[7].name, "Screen C2")
        XCTAssertEqual(session.viewVisits[7].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[7])// go to "Screen C1"

        XCTAssertEqual(session.viewVisits[8].name, "Screen C1")
        XCTAssertEqual(session.viewVisits[8].path, "UIViewController")
    }
}
