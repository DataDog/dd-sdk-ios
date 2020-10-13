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

class RUMModalViewsScenarioTests: IntegrationTests, RUMCommonAsserts, RUMM742Workaround {
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

        // Get POST requests
        let recordedRUMRequests = try pullRecordedRUMRequests(from: rumServerSession) { session in
            session.viewVisits.count >= 9 // TODO: RUMM-742 Replace this workaround with a nicer way.
        }

        // Get RUM Events
        let rumEventsMatchers = try recordedRUMRequests
            .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        // Assert common things
        assertHTTPHeadersAndPath(in: recordedRUMRequests)

        // Get RUM Sessions
        let rumSessions = try RUMSessionMatcher.groupMatchersBySessions(rumEventsMatchers)
        XCTAssertEqual(rumSessions.count, 1, "All events should be tracked within one RUM Session.")

        let session = rumSessions[0]
        XCTAssertEqual(session.viewVisits.count, 9, "The RUM Session should track 9 RUM Views")
        XCTAssertEqual(session.viewVisits[0].path, "Screen")
        XCTAssertEqual(session.viewVisits[0].actionEvents[0].action.type, .applicationStart)
        XCTAssertEqual(session.viewVisits[1].path, "Modal")
        XCTAssertEqual(session.viewVisits[2].path, "Screen")
        XCTAssertEqual(session.viewVisits[3].path, "Modal")
        XCTAssertEqual(session.viewVisits[4].path, "Screen")
        XCTAssertEqual(session.viewVisits[5].path, "Modal")
        XCTAssertEqual(session.viewVisits[6].path, "Screen")
        XCTAssertEqual(session.viewVisits[7].path, "Modal")
        XCTAssertEqual(session.viewVisits[8].path, "Screen")
    }
}
