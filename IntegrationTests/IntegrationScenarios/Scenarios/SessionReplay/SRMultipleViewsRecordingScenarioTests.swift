/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapNextButton() {
        buttons["NEXT"].safeTap(within: 5)
    }

    func wait(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}

class SRMultipleViewsRecordingScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testSRMultipleViewsRecordingScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()
        // Server session recording SR segments send to `HTTPServerMock`.
        let srServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "SRMultipleViewsRecordingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL,
                srEndpoint: srServerSession.recordingURL
            )
        )
        for _ in (0..<5) {
            app.wait(seconds: 1)
            app.tapNextButton()
        }
        try app.endRUMSession() // show "end view"

        // Pull RUM data from server until we see that "end view" was reported
        let rumRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }
        // Pull SR data from server - we know it is delivered faster than RUM so we don't need to await any longer
        let srRequests = try srServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout, until: { _ in true })

        assertRUM(requests: rumRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: rumRequests))
        sendCIAppLog(session)
        print(srRequests)
    }
}
