/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import HTTPServerMock
import TestUtilities
import XCTest

private extension ExampleApplication {
    func tapSendRequestWithSampledSpan() {
        tapButton(titled: "Request With Sampled Span")
    }

    func tapSendRequestWithDroppedSpan() {
        tapButton(titled: "Request With Dropped Span")
    }

    func tapSendRequestWithManuallyKeptSpan() {
        tapButton(titled: "Request With Manually Kept Span")
    }

    func tapSendRequestWithManuallyDroppedSpan() {
        tapButton(titled: "Request With Manually Dropped Span")
    }
}

class RUMResourceActiveSpanAugmentationTests: IntegrationTests, RUMCommonAsserts, URLSessionTestsHelpers {

    func testSampled() throws {
        try runTest(samplingPriority: .autoKeep, decisionMaker: .agentRate) {
            $0.tapSendRequestWithSampledSpan()
        }
    }

    func testDropped() throws {
        try runTest(samplingPriority: .autoDrop, decisionMaker: .agentRate) {
            $0.tapSendRequestWithDroppedSpan()
        }
    }

    func testManuallyKept() throws {
        try runTest(samplingPriority: .manualKeep, decisionMaker: .manual) {
            $0.tapSendRequestWithManuallyKeptSpan()
        }
    }

    func testManuallyDropped() throws {
        try runTest(samplingPriority: .manualDrop, decisionMaker: .manual) {
            $0.tapSendRequestWithManuallyDroppedSpan()
        }
    }

    private func runTest(samplingPriority: SamplingPriority, decisionMaker: SamplingMechanismType, perfomingAction action: (ExampleApplication) -> ()) throws {
        // Server session recording first party requests send to `HTTPServerMock`.
        // Used to assert that trace propagation headers are send for first party requests.
        let customFirstPartyServerSession = server.obtainUniqueRecordingSession()
        
        // Server session recording `Spans` send to `HTTPServerMock`.
        let tracingServerSession = server.obtainUniqueRecordingSession()
        
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()
        
        // Requesting this first party by the app should create the RUM Resource.
        let firstPartyGETResourceURL = URL(
            string: customFirstPartyServerSession.recordingURL.deletingLastPathComponent().absoluteString + "inspect"
        )!
        let firstPartyPOSTResourceURL = customFirstPartyServerSession.recordingURL
        // Requesting this first party by the app should create the RUM Error.
        let firstPartyBadResourceURL = URL(string: "https://foo.bar/")!

        // Requesting this third party by the app should create the RUM Resource.
        let thirdPartyGETResourceURL = URL(string: "https://shopist.io/categories.json")!
        // Requesting this third party by the app should create the RUM Resource.
        let thirdPartyPOSTResourceURL = URL(string: "https://api.shopist.io/checkout.json")!

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMAndTracingURLSessionBaseScenario",
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
            ),
            urlSessionSetup: .init(instrumentationMethod: .delegateUsingFeatureFirstPartyHosts, initializationMethod: .beforeSDK)
        )

        action(app)

        try app.endRUMSession()

        // Get custom 1st party request sent to the server
        let firstPartyPOSTRequest = try XCTUnwrap(
            customFirstPartyServerSession
                .pullRecordedRequests(timeout: dataDeliveryTimeout) { $0.count == 1 }
                .first
        )

        XCTAssertEqual(firstPartyPOSTRequest.httpHeaders["x-datadog-origin"], "rum")

        // Get RUM Sessions with expected number of View visits and Resources
        let rumRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: rumRequests)

        let session = try XCTUnwrap(try RUMSessionMatcher.singleSession(from: rumRequests))
        sendCIAppLog(session)

        let firstPartyResource = try XCTUnwrap(
            session.views[1].resourceEvents.first { $0.resource.url == firstPartyPOSTResourceURL.absoluteString }
        )

        XCTAssertEqual(firstPartyResource.resource.method, .post)
        XCTAssertNotNil(firstPartyResource.resource.duration)
        XCTAssertGreaterThan(firstPartyResource.resource.duration!, 0)

        if samplingPriority.isKept {
            // Get expected number of `SpanMatchers`
            let recordedTracingRequests = try tracingServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
                try SpanMatcher.from(requests: requests).count == 1
            }
            let spanMatchers = try SpanMatcher.from(requests: recordedTracingRequests)

            XCTAssertEqual(spanMatchers.count, 1)
            let spanMatcher = try XCTUnwrap(spanMatchers.first)

            let spanId = try XCTUnwrap(spanMatcher.spanID())
            let traceId = try XCTUnwrap(spanMatcher.traceID())

            let firstPartyPOSTRequestTraceID = try XCTUnwrap(
                getTraceID(from: firstPartyPOSTRequest)
            )

            let firstPartyPOSTRequestSpanID = try XCTUnwrap(
                getSpanID(from: firstPartyPOSTRequest)
            )

            // Make sure the sampling priority and decision makers are the expected ones.
            XCTAssertEqual(
                firstPartyPOSTRequest.httpHeaders["x-datadog-sampling-priority"],
                "\(samplingPriority.rawValue)"
            )

            XCTAssertEqual(getDecisionMaker(from: firstPartyPOSTRequest), decisionMaker)

            XCTAssertEqual(
                firstPartyResource.dd.traceId,
                traceId.toString(representation: .hexadecimal)
            )
            XCTAssertEqual(
                firstPartyResource.dd.spanId,
                firstPartyPOSTRequestSpanID.toString(representation: .decimal)
            )

            // Make sure the trace ID is the same between the active span and RUM resource span
            XCTAssertEqual(firstPartyPOSTRequestTraceID, traceId)

            // Make sure the active span ID is the parent span ID of the RUM resource span
            XCTAssertEqual(
                firstPartyResource.dd.parentSpanId,
                spanId.toString(representation: .decimal)
            )

            let firstPartyResource2SampleRate = try XCTUnwrap(firstPartyResource.dd.rulePsr, "Traced resource should send sample rate")

            XCTAssertTrue(isValid(sampleRate: firstPartyResource2SampleRate), "\(firstPartyResource2SampleRate) is not valid sample rate")
        } else {
            _ = try tracingServerSession.pullRecordedRequests(timeout: 1) { requests in
                XCTAssertEqual(requests.count, 0, "There should be no tracing `Spans` send")
                return true
            }

            XCTAssertNil(getTraceID(from: firstPartyPOSTRequest))
            XCTAssertNil(getSpanID(from: firstPartyPOSTRequest))

            XCTAssertNil(firstPartyPOSTRequest.httpHeaders["x-datadog-sampling-priority"])
            XCTAssertNil(getDecisionMaker(from: firstPartyPOSTRequest))

            XCTAssertNil(firstPartyResource.dd.traceId)
            XCTAssertNil(firstPartyResource.dd.spanId)
            XCTAssertNil(firstPartyResource.dd.parentSpanId)
        }
    }

    private func getDecisionMaker(from request: Request) -> SamplingMechanismType? {
        let tags = getRequestTags(request)

        guard let value = tags["_dd.p.dm"]?.replacingOccurrences(of: "-", with: "") else {
            return nil
        }

        return SamplingMechanismType(rawValue: value)
    }
}
