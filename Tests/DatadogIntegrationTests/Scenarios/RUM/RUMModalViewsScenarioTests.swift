/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
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

        let launchView = try XCTUnwrap(session.applicationLaunchView)
        XCTAssertEqual(launchView.actionEvents[0].action.type, .applicationStart)
        XCTAssertGreaterThan(launchView.actionEvents[0].action.loadingTime!, 0)

        let visits = session.viewVisits
        XCTAssertEqual(visits[0].name, "Screen")
        XCTAssertEqual(visits[0].path, "Example.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[0]) // go to modal "Modal"

        XCTAssertEqual(visits[1].name, "Modal")
        XCTAssertEqual(visits[1].path, "Example.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[1]) // dismiss to "Screen"

        XCTAssertEqual(visits[2].name, "Screen")
        XCTAssertEqual(visits[2].path, "Example.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[2]) // go to modal "Modal"

        XCTAssertEqual(visits[3].name, "Modal")
        XCTAssertEqual(visits[3].path, "Example.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[3]) // interactive dismiss to "Screen"

        XCTAssertEqual(visits[4].name, "Screen")
        XCTAssertEqual(visits[4].path, "Example.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[4]) // go to modal "Modal"

        XCTAssertEqual(visits[5].name, "Modal")
        XCTAssertEqual(visits[5].path, "Example.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[5]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(visits[6].name, "Screen")
        XCTAssertEqual(visits[6].path, "Example.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[6]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(visits[7].name, "Modal")
        XCTAssertEqual(visits[7].path, "Example.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[7]) // dismiss to "Screen"

        XCTAssertEqual(visits[8].name, "Screen")
        XCTAssertEqual(visits[8].path, "Example.RUMMVSViewController")
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

        let applicationLaunchView = try XCTUnwrap(session.applicationLaunchView)
        XCTAssertEqual(applicationLaunchView.actionEvents[0].action.type, .applicationStart)
        XCTAssertGreaterThan(applicationLaunchView.actionEvents[0].action.loadingTime!, 0)

        let visits = session.viewVisits
        XCTAssertEqual(visits[0].name, "Screen")
        XCTAssertEqual(visits[0].path, "Example.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[0]) // go to modal "Modal"

        XCTAssertEqual(visits[1].name, "Modal")
        XCTAssertEqual(visits[1].path, "Example.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[1]) // dismiss to "Screen"

        XCTAssertEqual(visits[2].name, "Screen")
        XCTAssertEqual(visits[2].path, "Example.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[2]) // go to modal "Modal", which is untracked

        XCTAssertEqual(visits[3].name, "Screen")    // Screen restarts properly
        XCTAssertEqual(visits[3].path, "Example.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[4]) // go to modal "Modal"

        XCTAssertEqual(visits[4].name, "Modal")
        XCTAssertEqual(visits[4].path, "Example.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[5]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(visits[5].name, "Screen")
        XCTAssertEqual(visits[5].path, "Example.RUMMVSViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[6]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(visits[6].name, "Modal")
        XCTAssertEqual(visits[6].path, "Example.RUMMVSModalViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[7]) // dismiss to "Screen"

        XCTAssertEqual(visits[7].name, "Screen")
        XCTAssertEqual(visits[7].path, "Example.RUMMVSViewController")
    }
}
