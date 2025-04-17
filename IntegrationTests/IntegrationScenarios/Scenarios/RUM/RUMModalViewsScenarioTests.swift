/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import TestUtilities
import XCTest

private extension ExampleApplication {
    func tapButton(titled buttonTitle: String) {
        buttons[buttonTitle].safeTap(within: 5)
    }

    func swipeToPullModalDown() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.75))
        coordinate1.press(forDuration: 0.3, thenDragTo: coordinate2)
    }

    func swipeToPullModalDownButThenCancel() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.35))
        coordinate1.press(forDuration: 0.3, thenDragTo: coordinate2)
    }
}

class RUMModalViewsScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMModalViewsScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMModalViewsAutoInstrumentationScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        ) // start on "Screen"

        app.tapButton(titled: "Present modally from code") // go to modal "Modal"
        app.tapButton(titled: "Dismiss by self.dismiss()") // dismiss to "Screen"

        app.tapButton(titled: "Present modally - .fullScreen") // go to modal "Modal"
        app.tapButton(titled: "Dismiss by parent.dismiss()") // dismiss to "Screen"

        app.tapButton(titled: "Present modally - .pageSheet") // go to modal "Modal"
        app.swipeToPullModalDown() // interactive dismiss to "Screen"

        app.tapButton(titled: "Present modally - .pageSheet") // go to modal "Modal"
        app.swipeToPullModalDownButThenCancel() // interactive and cancelled dismiss, stay on "Modal"
        app.tapButton(titled: "Dismiss by self.dismiss()") // dismiss to "Screen"

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
        XCTAssertGreaterThan(initialView.actionEvents[0].action.loadingTime!, 0)

        XCTAssertEqual(session.views[1].name, "Screen")
        XCTAssertEqual(session.views[1].path, "Runner.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[1]) // go to modal "Modal"

        XCTAssertEqual(session.views[2].name, "Modal")
        XCTAssertEqual(session.views[2].path, "Runner.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[2]) // dismiss to "Screen"

        XCTAssertEqual(session.views[3].name, "Screen")
        XCTAssertEqual(session.views[3].path, "Runner.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[3]) // go to modal "Modal"

        XCTAssertEqual(session.views[4].name, "Modal")
        XCTAssertEqual(session.views[4].path, "Runner.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[4]) // interactive dismiss to "Screen"

        XCTAssertEqual(session.views[5].name, "Screen")
        XCTAssertEqual(session.views[5].path, "Runner.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[5]) // go to modal "Modal"

        XCTAssertEqual(session.views[6].name, "Modal")
        XCTAssertEqual(session.views[6].path, "Runner.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[6]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(session.views[7].name, "Screen")
        XCTAssertEqual(session.views[7].path, "Runner.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[7]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(session.views[8].name, "Modal")
        XCTAssertEqual(session.views[8].path, "Runner.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[8]) // dismiss to "Screen"

        XCTAssertEqual(session.views[9].name, "Screen")
        XCTAssertEqual(session.views[9].path, "Runner.RUMMVSViewController")
    }

    func testRUMUntrackedModalViewsScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMUntrackedModalViewsAutoInstrumentationScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        ) // start on "Screen"

        app.tapButton(titled: "Present modally from code") // go to modal "Modal"
        app.tapButton(titled: "Dismiss by self.dismiss()") // dismiss to "Screen"

        app.tapButton(titled: "Present modally - .fullScreen") // go to modal "Modal"
        app.tapButton(titled: "Dismiss by parent.dismiss()") // dismiss to "Screen"

        app.tapButton(titled: "Present modally - .pageSheet") // go to modal "Modal"
        app.swipeToPullModalDown() // interactive dismiss to "Screen"

        app.tapButton(titled: "Present modally - .pageSheet") // go to modal "Modal"
        app.swipeToPullModalDownButThenCancel() // interactive and cancelled dismiss, stay on "Modal"
        app.tapButton(titled: "Dismiss by self.dismiss()") // dismiss to "Screen"

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
        XCTAssertGreaterThan(initialView.actionEvents[0].action.loadingTime!, 0)

        XCTAssertEqual(session.views[1].name, "Screen")
        XCTAssertEqual(session.views[1].path, "Runner.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[1]) // go to modal "Modal"

        XCTAssertEqual(session.views[2].name, "Modal")
        XCTAssertEqual(session.views[2].path, "Runner.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[2]) // dismiss to "Screen"

        XCTAssertEqual(session.views[3].name, "Screen")
        XCTAssertEqual(session.views[3].path, "Runner.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[3]) // go to modal "Modal", which is untracked

        XCTAssertEqual(session.views[4].name, "Screen")    // Screen restarts properly
        XCTAssertEqual(session.views[4].path, "Runner.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[4]) // go to modal "Modal"

        XCTAssertEqual(session.views[5].name, "Modal")
        XCTAssertEqual(session.views[5].path, "Runner.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[5]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(session.views[6].name, "Screen")
        XCTAssertEqual(session.views[6].path, "Runner.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[6]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(session.views[7].name, "Modal")
        XCTAssertEqual(session.views[7].path, "Runner.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[7]) // dismiss to "Screen"

        XCTAssertEqual(session.views[8].name, "Screen")
        XCTAssertEqual(session.views[8].path, "Runner.RUMMVSViewController")
    }
}
