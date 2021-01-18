/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapButton(titled buttonTitle: String) {
        buttons[buttonTitle].tap()
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
            testScenario: RUMModalViewsAutoInstrumentationScenario.self,
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

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.from(requests: requests)?.viewVisits.count == 9
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.from(requests: recordedRUMRequests))
        let visits = session.viewVisits
        XCTAssertEqual(visits[0].path, "Screen")
        XCTAssertEqual(visits[0].actionEvents[0].action.type, .applicationStart)
        XCTAssertGreaterThan(visits[0].actionEvents[0].action.loadingTime!, 0)
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[0]) // start on "Screen"
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[0]) // go to modal "Modal"

        XCTAssertEqual(visits[1].path, "Modal")
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[1]) // go to modal "Modal"
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[1]) // dismiss to "Screen"

        XCTAssertEqual(visits[2].path, "Screen")
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[2]) // dismiss to "Screen"
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[2]) // go to modal "Modal"

        XCTAssertEqual(visits[3].path, "Modal")
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[3]) // go to modal "Modal"
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[3]) // interactive dismiss to "Screen"

        XCTAssertEqual(visits[4].path, "Screen")
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[4]) // interactive dismiss to "Screen"
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[4]) // go to modal "Modal"

        XCTAssertEqual(visits[5].path, "Modal")
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[5]) // go to modal "Modal"
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[5]) // interactive and cancelled dismiss, stay on "Modal"

        XCTAssertEqual(visits[6].path, "Screen")
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[6])  // interactive and cancelled dismiss, stay on "Modal"
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[6])

        XCTAssertEqual(visits[7].path, "Modal")
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[7]) // interactive and cancelled dismiss, stay on "Modal"
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[7]) // dismiss to "Screen"

        XCTAssertEqual(visits[8].path, "Screen")
        RUMSessionMatcher.assertViewWasInitiallyActive(visits[8]) // dismiss to "Screen"
    }
}
