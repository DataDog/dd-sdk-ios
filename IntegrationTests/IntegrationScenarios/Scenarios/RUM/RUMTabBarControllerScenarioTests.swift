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

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        XCTAssertEqual(session.views[1].name, "Screen A")
        XCTAssertEqual(session.views[1].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[1]) // go to "Screen B1"

        XCTAssertEqual(session.views[2].name, "Screen B1")
        XCTAssertEqual(session.views[2].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[2])// go to "Screen B2"

        XCTAssertEqual(session.views[3].name, "Screen B2")
        XCTAssertEqual(session.views[3].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[3])// go to "Screen B1"

        XCTAssertEqual(session.views[4].name, "Screen B1")
        XCTAssertEqual(session.views[4].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[4])// go to "Screen C1"

        XCTAssertEqual(session.views[5].name, "Screen C1")
        XCTAssertEqual(session.views[5].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[5])// go to "Screen C2"

        XCTAssertEqual(session.views[6].name, "Screen C2")
        XCTAssertEqual(session.views[6].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[6])// go to "Screen A"

        XCTAssertEqual(session.views[7].name, "Screen A")
        XCTAssertEqual(session.views[7].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[7])// go to "Screen C2"

        XCTAssertEqual(session.views[8].name, "Screen C2")
        XCTAssertEqual(session.views[8].path, "UIViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[8])// go to "Screen C1"

        XCTAssertEqual(session.views[9].name, "Screen C1")
        XCTAssertEqual(session.views[9].path, "UIViewController")
    }
}
