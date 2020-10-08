/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapSend3rdPartyRequests() {
        buttons["Send 3rd party requests"].tap()
    }
}

class RUMResourcesScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMResourcesScenario() throws {
        // Server session recording first party requests send to `HTTPServerMock`.
        // Used to assert that trace propagation headers are send for first party requests.
        let customFirstPartyServerSession = server.obtainUniqueRecordingSession()

        // Server session recording `Spans` send to `HTTPServerMock`.
        let tracingServerSession = server.obtainUniqueRecordingSession()
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        // Requesting this first party by the app should create the `Span` and RUM Resource.
        let firstPartyGETResourceURL = URL(
            string: customFirstPartyServerSession.recordingURL.deletingLastPathComponent().absoluteString + "inspect"
        )!
        // Requesting this first party by the app should create the `Span` and RUM Resource.
        let firstPartyPOSTResourceURL = customFirstPartyServerSession.recordingURL
        // Requesting this first party by the app should create the `Span` with error and RUM Error.
        let firstPartyBadResourceURL = URL(string: "https://foo.bar")!

        // Requesting this third party by the app should create the RUM Resource.
        let thirdPartyGETResourceURL = URL(string: "https://bitrise.io")!
        // Requesting this third party by the app should create the RUM Resource.
        let thirdPartyPOSTResourceURL = URL(string: "https://bitrise.io/about")!

        let app = ExampleApplication()
        app.launchWith(
            testScenario: RUMResourcesScenario.self,
            serverConfiguration: HTTPServerMockConfiguration(
                tracesEndpoint: tracingServerSession.recordingURL,
                rumEndpoint: rumServerSession.recordingURL,
                instrumentedEndpoints: [
                    firstPartyGETResourceURL,
                    firstPartyPOSTResourceURL,
                    firstPartyBadResourceURL,
                    thirdPartyGETResourceURL,
                    thirdPartyPOSTResourceURL
                ]
            )
        )

        app.tapSend3rdPartyRequests()

        // Get Tracing requests
        let tracingRequests = try tracingServerSession
            .pullRecordedPOSTRequests(count: 1, timeout: dataDeliveryTimeout)

        // Get RUM requests
        let rumRequests = try rumServerSession
            .pullRecordedPOSTRequests(count: 1, timeout: dataDeliveryTimeout)

        assertHTTPHeadersAndPath(in: rumRequests)

        // Get `Spans`
        let spanMatchers = try tracingRequests
            .flatMap { request in try SpanMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        // Get RUM Events
        let rumEventMatchers = try rumRequests
            .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        try XCTAssertTrue(
            spanMatchers.contains { span in try span.resource() == firstPartyGETResourceURL.absoluteString },
            "`Span` should be send for `firstPartyGETResourceURL`"
        )
        try XCTAssertTrue(
            spanMatchers.contains { span in try span.resource() == firstPartyPOSTResourceURL.absoluteString },
            "`Span` should be send for `firstPartyPOSTResourceURL`"
        )
        try XCTAssertTrue(
            spanMatchers.contains { span in try span.resource() == firstPartyBadResourceURL.absoluteString },
            "`Span` should be send for `firstPartyBadResourceURL`"
        )
        try XCTAssertFalse(
            spanMatchers.contains { span in try span.resource() == thirdPartyGETResourceURL.absoluteString },
            "`Span` should NOT bet send for `thirdPartyGETResourceURL`"
        )
        try XCTAssertFalse(
            spanMatchers.contains { span in try span.resource() == thirdPartyPOSTResourceURL.absoluteString },
            "`Span` should NOT bet send for `thirdPartyPOSTResourceURL`"
        )

        // Get RUM Sessions
        let rumSessions = try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers)
        XCTAssertEqual(rumSessions.count, 1, "All events should be tracked within one RUM Session.")

        let session = rumSessions[0]
        XCTAssertEqual(session.viewVisits.count, 2, "The RUM Session should track 2 RUM Views")

        // Asserts in `SendFirstPartyRequestsVC` RUM View
        XCTAssertEqual(session.viewVisits[0].path, "SendFirstPartyRequestsVC")
        XCTAssertEqual(session.viewVisits[0].resourceEvents.count, 2, "1st screen should track 2 RUM Resources")
        XCTAssertEqual(session.viewVisits[0].errorEvents.count, 2, "1st screen should track 2 RUM Errors")

        let firstPartyResource1 = try XCTUnwrap(
            session.viewVisits[0].resourceEvents.first { $0.resource.url == firstPartyGETResourceURL.absoluteString },
            "RUM Resource should be send for `firstPartyGETResourceURL`"
        )
        XCTAssertEqual(firstPartyResource1.resource.method, .methodGET)
        XCTAssertGreaterThan(firstPartyResource1.resource.duration, 0)

        let firstPartyResource2 = try XCTUnwrap(
            session.viewVisits[0].resourceEvents.first { $0.resource.url == firstPartyPOSTResourceURL.absoluteString },
            "RUM Resource should be send for `firstPartyPOSTResourceURL`"
        )
        XCTAssertEqual(firstPartyResource2.resource.method, .post)
        XCTAssertGreaterThan(firstPartyResource2.resource.duration, 0)

        let firstPartyResourceError1 = try XCTUnwrap(
            session.viewVisits[0].errorEvents.first { $0.error.resource?.url == firstPartyBadResourceURL.absoluteString },
            "RUM Error should be send for `firstPartyBadResourceURL`"
        )
        XCTAssertEqual(firstPartyResourceError1.error.resource?.method, .methodGET)

        XCTAssertTrue(
            session.viewVisits[0].errorEvents.contains { event in
                event.error.message.matches(
                    regex: #"^Span error \(urlsession.request\): (.*)| A server with the specified hostname could not be found.$"#
                )
            },
            "RUM Error should be send for `firstPartyBadResourceURL` request's Span error"
        )

        // Asserts in `SendThirdPartyRequestsVC` RUM View
        XCTAssertEqual(session.viewVisits[1].path, "SendThirdPartyRequestsVC")
        XCTAssertEqual(session.viewVisits[1].resourceEvents.count, 2, "2nd screen should track 2 RUM Resources")
        XCTAssertEqual(session.viewVisits[1].errorEvents.count, 0, "2nd screen should track no RUM Errors")

        let thirdPartyResource1 = try XCTUnwrap(
            session.viewVisits[1].resourceEvents.first { $0.resource.url == thirdPartyGETResourceURL.absoluteString },
            "RUM Resource should be send for `thirdPartyGETResourceURL`"
        )
        XCTAssertEqual(thirdPartyResource1.resource.method, .methodGET)
        XCTAssertGreaterThan(thirdPartyResource1.resource.duration, 0)

        let thirdPartyResource2 = try XCTUnwrap(
            session.viewVisits[1].resourceEvents.first { $0.resource.url == thirdPartyPOSTResourceURL.absoluteString },
            "RUM Resource should be send for `thirdPartyPOSTResourceURL`"
        )
        XCTAssertEqual(thirdPartyResource2.resource.method, .post)
        XCTAssertGreaterThan(thirdPartyResource2.resource.duration, 0)

        XCTAssertTrue(
            thirdPartyResource1.resource.dns != nil || thirdPartyResource2.resource.dns != nil,
            "At leas one of the third party resources should lead to DNS resolution phase"
        )
    }
}
