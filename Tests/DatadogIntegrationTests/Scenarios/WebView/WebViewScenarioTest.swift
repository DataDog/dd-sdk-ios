/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import HTTPServerMock
import XCTest

class WebViewScenarioTest: IntegrationTests, RUMCommonAsserts {
    func testWebViewRUMEventsScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "WebViewTrackingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.viewVisits.count == 2
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))

        XCTAssertEqual(session.viewVisits.count, 2)
        session.viewVisits[0].viewEvents.forEach { nativeView in
            XCTAssertEqual(nativeView.source, .ios)
        }
        session.viewVisits[1].viewEvents.forEach { browserView in
            // ideally `source` should be `.browser`
            // but it's not implemented in `browser-sdk` yet
            XCTAssertNotEqual(browserView.source, .ios)
        }
    }
}
