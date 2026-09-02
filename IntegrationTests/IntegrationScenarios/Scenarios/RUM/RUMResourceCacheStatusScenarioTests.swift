/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import TestUtilities
import XCTest

/// Verifies how RUM Resource events report the "server-validated cache" scenario: an OS-level HTTP cache
/// revalidation (`304 Not Modified`) that the app sees as a transparent `200`.
///
/// This locks in today's already-shipped behaviour: the RUM Resource's `resource.status_code` reflects the
/// *app-visible* response (`200`, synthesized by the OS for a revalidated cache hit) - never the `304` that
/// was actually exchanged on the wire.
class RUMResourceCacheStatusScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMResourceCacheStatusScenario_revalidatedCacheHitReportsAppVisibleStatusCode() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        // A resource that supports ETag-based revalidation: the mock server responds `200` on the 1st request
        // and `304` (no body) on the 2nd request, once the device's local HTTP cache sends `If-None-Match`.
        let cacheServerSession = server.obtainUniqueRecordingSession()
        let cacheableResourceURL = cacheServerSession
            .recordingURL
            .appendingPathComponent("cache-test/resource-1")

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMResourceCacheStatusScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL,
                instrumentedEndpoints: [cacheableResourceURL]
            )
        )

        try app.endRUMSession()

        // Get RUM Session with expected number of View visits and Resources
        let rumRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: rumRequests)

        // Prove that the mock server actually took its `304` branch for the 2nd request - otherwise the
        // status-code assertions below would pass just the same even if revalidation never happened.
        let cacheRequests = try cacheServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            requests.count == 2
        }
        let cacheResponseStatuses = try cacheRequests.map { request -> Int in
            let json = try JSONSerialization.jsonObject(with: request.httpBody) as? [String: Int]
            return try XCTUnwrap(json?["response_status"])
        }
        XCTAssertEqual(cacheResponseStatuses, [200, 304], "The mock server must serve `200` for the 'prime' request and `304` for the 'revalidate' request")

        let session = try XCTUnwrap(try RUMSessionMatcher.singleSession(from: rumRequests))
        sendCIAppLog(session)

        let views = try session.views.dropApplicationLaunchView()
        let resourceEvents = views[0].resourceEvents.filter { $0.resource.url == cacheableResourceURL.absoluteString }

        XCTAssertEqual(resourceEvents.count, 2, "Both the 'prime' and 'revalidate' requests should create a RUM Resource event")

        let primeResource = resourceEvents[0]
        let revalidateResource = resourceEvents[1]

        XCTAssertEqual(primeResource.resource.statusCode, 200, "The 'prime' request is a genuine cache miss - server responds `200`")

        // This is the behaviour under test: even though the 2nd request was revalidated by the server with a
        // `304 Not Modified`, the app (and therefore RUM) only ever sees the OS-synthesized `200` response.
        XCTAssertEqual(
            revalidateResource.resource.statusCode,
            200,
            "The 'revalidate' request is transparently served as `200` to the app, even though `304` was exchanged on the wire"
        )

        // NOTE: today's shipped `isLocalCacheHit` logic (see `ResourceMetrics.init(taskMetrics:)`) derives
        // `local_cache_hit` from the *last* `URLSessionTaskMetrics` transaction. For a revalidated cache hit,
        // that last transaction is the `.networkLoad` one (carrying the `304`), so `local_cache_hit` is
        // expected to read `false` here - this is a known, already-understood limitation, not something this
        // test should fail on. We only log it for visibility.
        print("ℹ️ revalidated resource `local_cache_hit` = \(String(describing: revalidateResource.resource.localCacheHit))")
    }
}
