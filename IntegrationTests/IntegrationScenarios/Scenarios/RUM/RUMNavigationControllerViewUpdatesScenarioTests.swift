/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// TODO: RUM-16908 Merge into `RUMNavigationControllerScenarioTests` once `viewUpdates` feature flag is removed

import HTTPServerMock
import TestUtilities
import XCTest

private extension ExampleApplication {
    func tapPushNextScreenButton() {
        tapButton(titled: "Push Next Screen")
    }

    func tapBackButton() {
        navigationBars["Screen 4"].buttons["Screen 3"].safeTap()
    }

    func tapPopToTheFirstScreenButton() {
        tapButton(titled: "Pop To The First Screen")
    }

    func swipeInteractiveBackGesture() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0, dy: 0.5))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.80, dy: 0.5))
        coordinate1.press(forDuration: 0.5, thenDragTo: coordinate2)
    }
}

/// Mirrors `RUMNavigationControllerScenarioTests` with the `.viewUpdates` feature flag enabled.
/// Inactive transitions are asserted directly against `viewUpdateEvents` so the test actually exercises
/// the delta-projection pipeline, rather than through `assertViewWasEventuallyInactive` whose
/// `?? viewEvents.last` fallback would pass even with no `view_update` deltas.
class RUMNavigationControllerViewUpdatesScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMNavigationControllerScenario() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMNavigationControllerViewUpdatesScenario",
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

        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertNotNil(session.ttidEvent)
        XCTAssertGreaterThan(session.timeToInitialDisplay!, 0)

        XCTAssertEqual(session.views[1].name, "Screen1")
        XCTAssertEqual(session.views[1].path, "UIViewController")
        XCTAssertFalse(session.views[1].viewUpdateEvents.isEmpty)
        XCTAssertEqual(session.views[1].latestUpdateValue(\.view.isActive), false) // go to "Screen2"

        XCTAssertEqual(session.views[2].name, "Screen2")
        XCTAssertEqual(session.views[2].path, "UIViewController")
        XCTAssertFalse(session.views[2].viewUpdateEvents.isEmpty)
        XCTAssertEqual(session.views[2].latestUpdateValue(\.view.isActive), false) // go to "Screen3"

        XCTAssertEqual(session.views[3].name, "Screen3")
        XCTAssertEqual(session.views[3].path, "Runner.RUMNCSScreen3ViewController")
        XCTAssertFalse(session.views[3].viewUpdateEvents.isEmpty)
        XCTAssertEqual(session.views[3].latestUpdateValue(\.view.isActive), false) // go to "Screen4"

        XCTAssertEqual(session.views[4].name, "Screen4")
        XCTAssertEqual(session.views[4].path, "UIViewController")
        XCTAssertFalse(session.views[4].viewUpdateEvents.isEmpty)
        XCTAssertEqual(session.views[4].latestUpdateValue(\.view.isActive), false) // go to "Screen3"

        XCTAssertEqual(session.views[5].name, "Screen3")
        XCTAssertEqual(session.views[5].path, "Runner.RUMNCSScreen3ViewController")
        XCTAssertFalse(session.views[5].viewUpdateEvents.isEmpty)
        XCTAssertEqual(session.views[5].latestUpdateValue(\.view.isActive), false) // go to "Screen1"

        XCTAssertEqual(session.views[6].name, "Screen1")
        XCTAssertEqual(session.views[6].path, "UIViewController")
        XCTAssertFalse(session.views[6].viewUpdateEvents.isEmpty)
        XCTAssertEqual(session.views[6].latestUpdateValue(\.view.isActive), false) // go to "Screen2"

        XCTAssertEqual(session.views[7].name, "Screen2")
        XCTAssertEqual(session.views[7].path, "UIViewController")
        XCTAssertFalse(session.views[7].viewUpdateEvents.isEmpty)
        XCTAssertEqual(session.views[7].latestUpdateValue(\.view.isActive), false) // swipe back to "Screen1"

        XCTAssertEqual(session.views[8].name, "Screen1")
        XCTAssertEqual(session.views[8].path, "UIViewController")
    }
}
