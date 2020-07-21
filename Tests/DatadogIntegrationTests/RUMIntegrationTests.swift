/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

class RUMIntegrationTests: IntegrationTests {
    private struct Constants {
        /// Time needed for data to be uploaded to mock server.
        static let dataDeliveryTime: TimeInterval = 30
    }

    func testLaunchTheAppNavigateThroughRUMFixtures() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            mockLogsEndpointURL: server.obtainUniqueRecordingSession().recordingURL,     // mock any
            mockTracesEndpointURL: server.obtainUniqueRecordingSession().recordingURL,   // mock any
            mockRUMEndpointURL: rumServerSession.recordingURL,
            mockSourceEndpointURL: server.obtainUniqueRecordingSession().recordingURL    // mock any 
        )
        app.tapSendRUMEventsForUITests()

        // Return desired count or timeout
        let recordedRUMRequests = try rumServerSession.pullRecordedPOSTRequests(
            count: 1,
            timeout: Constants.dataDeliveryTime
        )

        recordedRUMRequests.forEach { request in
            // Example path here: `/36882784-420B-494F-910D-CBAC5897A309/ui-tests-client-token?ddsource=ios&batch_time=1576404000000&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:1.3.0-beta3,env:integration`
            let pathRegexp = #"^(.*)(\/ui-tests-client-token\?ddsource=ios&batch_time=)([0-9]+)(&ddtags=service:ui-tests-service-name,version:1.0,sdk_version:)([0-9].[0-9].[0-9](-[a-z0-9]*))(,env:integration)$"#
            XCTAssertNotNil(
                request.path.range(of: pathRegexp, options: .regularExpression, range: nil, locale: nil),
                "RUM request path: \(request.path) should match regexp: \(pathRegexp)"
            )
            XCTAssertTrue(request.httpHeaders.contains("Content-Type: text/plain;charset=UTF-8"))
        }

        // Assert RUM events
        let rumEventsMatchers = try recordedRUMRequests
            .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        let applicationStartAction: RUMActionEvent = try rumEventsMatchers[0].model()
        XCTAssertEqual(applicationStartAction.action.type, "application_start")
    }
}
