/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import XCTest

class RUMScrubbingScenarioTests: UITests, RUMCommonAsserts {
    func testRUMScrubbingScenario() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMScrubbingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        try app.endRUMSession()

        // Get RUM Session with expected number of RUM Errors
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        let view = session.views[1]
        XCTAssertGreaterThan(view.viewEvents.count, 0)
        view.viewEvents.forEach { event in
            XCTAssertTrue(event.view.url.isRedacted)
            XCTAssertTrue(event.view.name?.isRedacted == true)
        }

        XCTAssertGreaterThan(view.errorEvents.count, 0)
        view.errorEvents.forEach { event in
            XCTAssertTrue(event.error.message.isRedacted)
            XCTAssertTrue(event.view.url.isRedacted)
            XCTAssertTrue(event.view.name?.isRedacted == true)
            XCTAssertTrue(event.error.resource?.url.isRedacted ?? true)
            XCTAssertTrue(event.error.stack?.isRedacted ?? true)
        }

        XCTAssertGreaterThan(view.resourceEvents.count, 0)
        view.resourceEvents.forEach { event in
            XCTAssertTrue(event.resource.url.isRedacted)
            XCTAssertTrue(event.view.name?.isRedacted == true)
        }

        XCTAssertGreaterThan(view.actionEvents.count, 0)
        view.actionEvents.forEach { event in
            XCTAssertTrue(event.action.target?.name.isRedacted ?? true)
            XCTAssertTrue(event.view.name?.isRedacted == true)
        }
    }
}

private extension String {
    var isRedacted: Bool {
        let sensitivePart = "sensitive"
        return !contains(sensitivePart)
    }
}
