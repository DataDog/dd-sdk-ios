/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import HTTPServerMock
import XCTest

class WebViewScenarioTest: IntegrationTests, LoggingCommonAsserts {
    func testWebViewLoggingScenario() throws {
        let loggingServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "WebViewTrackingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                logsEndpoint: loggingServerSession.recordingURL
            )
        )

        // Get expected number of `LogMatchers`
        let recordedRequests = try loggingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try LogMatcher.from(requests: requests).count >= 1
        }
        let logMatchers = try LogMatcher.from(requests: recordedRequests)

        // Assert common things
        assertLogging(requests: recordedRequests)

        logMatchers[0].assertStatus(equals: "error")
        logMatchers[0].assertMessage(equals: "console error: error")
    }
}
