/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import DatadogInternal
import XCTest

private extension ExampleApplication {
    func tapSend3rdPartyRequests() {
        buttons["Send 3rd party requests"].tap()
    }
}

class RUMResourcesScenarioTests: IntegrationTests, RUMCommonAsserts {
    private struct Expectations {
        let expectedFirstPartyRequestsViewControllerName: String
        let expectedThirdPartyRequestsViewControllerName: String
    }

    func testRUMURLSessionResourcesScenario_composition() throws {
        try runTest(
            for: "RUMURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "Runner.SendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "Runner.SendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .legacyComposition,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testRUMURLSessionResourcesScenario_legacyWithAdditionalFirstyPartyHosts() throws {
        try runTest(
            for: "RUMURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "Runner.SendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "Runner.SendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .legacyWithAdditionalFirstyPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testRUMURLSessionResourcesScenario_legacyWithFeatureFirstPartyHosts() throws {
        try runTest(
            for: "RUMURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "Runner.SendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "Runner.SendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .legacyWithFeatureFirstPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testRUMURLSessionResourcesScenario_inheritance() throws {
        try runTest(
            for: "RUMURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "Runner.SendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "Runner.SendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .legacyInheritance,
                initializationMethod: .afterSDK
            )
        )
    }

    func testRUMURLSessionResourcesScenario_delegateUsingFeatureFirstPartyHosts() throws {
        try runTest(
            for: "RUMURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "Runner.SendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "Runner.SendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .delegateUsingFeatureFirstPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }

    func testRUMURLSessionResourcesScenario_delegateWithAdditionalFirstyPartyHosts() throws {
        try runTest(
            for: "RUMURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "Runner.SendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "Runner.SendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .delegateWithAdditionalFirstyPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }

    func testRUMNSURLSessionResourcesScenario_composition() throws {
        try runTest(
            for: "RUMNSURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "ObjcSendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "ObjcSendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .legacyComposition,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testRUMNSURLSessionResourcesScenario_legacyWithAdditionalFirstyPartyHosts() throws {
        try runTest(
            for: "RUMNSURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "ObjcSendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "ObjcSendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .legacyWithAdditionalFirstyPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testRUMNSURLSessionResourcesScenario_legacyWithFeatureFirstPartyHosts() throws {
        try runTest(
            for: "RUMNSURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "ObjcSendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "ObjcSendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .legacyWithFeatureFirstPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }
    
    func testRUMNSURLSessionResourcesScenario_inheritance() throws {
        try runTest(
            for: "RUMNSURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "ObjcSendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "ObjcSendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .legacyInheritance,
                initializationMethod: .afterSDK
            )
        )
    }

    func testRUMNSURLSessionResourcesScenario_delegateUsingFeatureFirstPartyHosts() throws {
        try runTest(
            for: "RUMNSURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "ObjcSendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "ObjcSendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .delegateUsingFeatureFirstPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }

    func testRUMNSURLSessionResourcesScenario_delegateWithAdditionalFirstyPartyHosts() throws {
        try runTest(
            for: "RUMNSURLSessionResourcesScenario",
            expectations: Expectations(
                expectedFirstPartyRequestsViewControllerName: "ObjcSendFirstPartyRequestsViewController",
                expectedThirdPartyRequestsViewControllerName: "ObjcSendThirdPartyRequestsViewController"
            ),
            urlSessionSetup: .init(
                instrumentationMethod: .delegateWithAdditionalFirstyPartyHosts,
                initializationMethod: .afterSDK
            )
        )
    }

    /// Both, `URLSession` (Swift) and `NSURLSession` (Objective-C) scenarios use different storyboards
    /// and different view controllers to run this test, but the the logic and the instrumentation is the same.
    private func runTest(for testScenarioClassName: String, expectations: Expectations, urlSessionSetup: URLSessionSetup) throws {
        precondition(urlSessionSetup.initializationMethod == .afterSDK, "The SDK must be initialized before enabling URLSession ")

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
        // Requesting this first party by the app should create the RUM Resource and inject tracing headers into the request.
        let firstPartyPOSTResourceURL = customFirstPartyServerSession.recordingURL
        // Requesting this first party by the app should create the RUM Error.
        let firstPartyBadResourceURL = URL(string: "https://foo.bar/")!

        // Requesting this third party by the app should create the RUM Resource.
        let thirdPartyGETResourceURL = URL(string: "https://shopist.io/categories.json")!
        // Requesting this third party by the app should create the RUM Resource.
        let thirdPartyPOSTResourceURL = URL(string: "https://api.shopist.io/checkout.json")!

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: testScenarioClassName,
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
            urlSessionSetup: urlSessionSetup
        )

        app.tapSend3rdPartyRequests()

        try app.endRUMSession()

        // Get custom 1st party request sent to the server
        let firstPartyPOSTRequest = try XCTUnwrap(
            customFirstPartyServerSession
                .pullRecordedRequests(timeout: dataDeliveryTimeout) { $0.count == 1 }
                .first
        )

        let firstPartyPOSTRequestTraceID = try XCTUnwrap(
            getTraceID(from: firstPartyPOSTRequest),
            "Tracing information should be propagated to `firstPartyPOSTResourceURL`."
        )
        let firstPartyPOSTRequestSpanID = try XCTUnwrap(
            getSpanID(from: firstPartyPOSTRequest),
            "Tracing information should be propagated to `firstPartyPOSTResourceURL`."
        )
        XCTAssertEqual(
            firstPartyPOSTRequest.httpHeaders["x-datadog-sampling-priority"],
            "1",
            "`x-datadog-sampling-priority: 1` header must be set for `firstPartyPOSTResourceURL`"
        )
        XCTAssertEqual(
            firstPartyPOSTRequest.httpHeaders["x-datadog-origin"],
            "rum",
            "`x-datadog-origin: rum` header must be set for `firstPartyPOSTResourceURL`"
        )

        // Get RUM Sessions with expected number of View visits and Resources
        let rumRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: rumRequests)

        let session = try XCTUnwrap(try RUMSessionMatcher.singleSession(from: rumRequests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        // Asserts in `SendFirstPartyRequestsVC` RUM View
        XCTAssertEqual(session.views[1].name, expectations.expectedFirstPartyRequestsViewControllerName)
        XCTAssertEqual(session.views[1].path, expectations.expectedFirstPartyRequestsViewControllerName)
        XCTAssertEqual(session.views[1].resourceEvents.count, 2, "1st screen should track 2 RUM Resources")
        XCTAssertEqual(session.views[1].errorEvents.count, 1, "1st screen should track 1 RUM Errors")

        let firstPartyResource1 = try XCTUnwrap(
            session.views[1].resourceEvents.first { $0.resource.url == firstPartyGETResourceURL.absoluteString },
            "RUM Resource should be send for `firstPartyGETResourceURL`"
        )
        XCTAssertEqual(firstPartyResource1.resource.method, .get)
        XCTAssertNotNil(firstPartyResource1.resource.duration)
        XCTAssertGreaterThan(firstPartyResource1.resource.duration!, 0)

        XCTAssertNotNil(firstPartyResource1.dd.traceId)
        XCTAssertNotNil(firstPartyResource1.dd.spanId)
        XCTAssertNotNil(firstPartyResource1.dd.rulePsr)

        let firstPartyResource2 = try XCTUnwrap(
            session.views[1].resourceEvents.first { $0.resource.url == firstPartyPOSTResourceURL.absoluteString },
            "RUM Resource should be send for `firstPartyPOSTResourceURL`"
        )
        XCTAssertEqual(firstPartyResource2.resource.method, .post)
        XCTAssertNotNil(firstPartyResource2.resource.duration)
        XCTAssertGreaterThan(firstPartyResource2.resource.duration!, 0)
        XCTAssertEqual(
            firstPartyResource2.dd.traceId,
            firstPartyPOSTRequestTraceID.toString(representation: .hexadecimal),
            "Tracing information should be propagated to `firstPartyPOSTResourceURL`"
        )
        XCTAssertEqual(
            firstPartyResource2.dd.spanId,
            firstPartyPOSTRequestSpanID.toString(representation: .decimal),
            "Tracing information should be propagated to `firstPartyPOSTResourceURL`"
        )
        let firstPartyResource2SampleRate = try XCTUnwrap(firstPartyResource2.dd.rulePsr, "Traced resource should send sample rate")
        XCTAssertTrue(isValid(sampleRate: firstPartyResource2SampleRate), "\(firstPartyResource2SampleRate) is not valid sample rate")

        let firstPartyResourceError1 = try XCTUnwrap(
            session.views[1].errorEvents.first { $0.error.resource?.url == firstPartyBadResourceURL.absoluteString },
            "RUM Error should be send for `firstPartyBadResourceURL`"
        )
        XCTAssertEqual(firstPartyResourceError1.error.resource?.method, .get)

        // Asserts in `SendThirdPartyRequestsVC` RUM View
        XCTAssertEqual(session.views[2].name, expectations.expectedThirdPartyRequestsViewControllerName)
        XCTAssertEqual(session.views[2].path, expectations.expectedThirdPartyRequestsViewControllerName)
        XCTAssertEqual(session.views[2].resourceEvents.count, 2, "2nd screen should track 2 RUM Resources")
        XCTAssertEqual(session.views[2].errorEvents.count, 0, "2nd screen should track no RUM Errors")

        let thirdPartyResource1 = try XCTUnwrap(
            session.views[2].resourceEvents.first { $0.resource.url == thirdPartyGETResourceURL.absoluteString },
            "RUM Resource should be send for `thirdPartyGETResourceURL`"
        )
        XCTAssertEqual(thirdPartyResource1.resource.method, .get)
        XCTAssertNotNil(thirdPartyResource1.resource.duration)
        XCTAssertGreaterThan(thirdPartyResource1.resource.duration!, 0)
        XCTAssertNil(thirdPartyResource1.dd.traceId, "3rd party RUM Resources should not be traced")
        XCTAssertNil(thirdPartyResource1.dd.spanId, "3rd party RUM Resources should not be traced")
        XCTAssertNil(thirdPartyResource1.dd.rulePsr, "Not traced resource should not send sample rate")

        let thirdPartyResource2 = try XCTUnwrap(
            session.views[2].resourceEvents.first { $0.resource.url == thirdPartyPOSTResourceURL.absoluteString },
            "RUM Resource should be send for `thirdPartyPOSTResourceURL`"
        )
        XCTAssertEqual(thirdPartyResource2.resource.method, .post)
        XCTAssertNotNil(thirdPartyResource2.resource.duration)
        XCTAssertGreaterThan(thirdPartyResource2.resource.duration!, 0)
        XCTAssertNil(thirdPartyResource2.dd.traceId, "3rd party RUM Resources should not be traced")
        XCTAssertNil(thirdPartyResource2.dd.spanId, "3rd party RUM Resources should not be traced")
        XCTAssertNil(thirdPartyResource2.dd.rulePsr, "Not traced resource should not send sample rate")

        XCTAssertTrue(
            thirdPartyResource1.resource.dns != nil || thirdPartyResource2.resource.dns != nil,
            "At least one 3rd party resource should track DNS resolution phase"
        )
        XCTAssertTrue(
            thirdPartyResource1.resource.connect != nil || thirdPartyResource2.resource.connect != nil,
            "At least one 3rd party resource should track connect phase"
        )
        XCTAssertTrue(
            thirdPartyResource1.resource.ssl != nil || thirdPartyResource2.resource.ssl != nil,
            "At least one 3rd party resource should track secure connect phase"
        )
        XCTAssertTrue(
            thirdPartyResource1.resource.firstByte != nil && thirdPartyResource2.resource.firstByte != nil,
            "Both 3rd party resources should track TTFB phase"
        )
        XCTAssertTrue(
            thirdPartyResource1.resource.download != nil && thirdPartyResource2.resource.download != nil,
            "Both 3rd party resources should track download phase"
        )

        // Assert there were no tracing `Spans` sent
        _ = try tracingServerSession.pullRecordedRequests(timeout: 1) { requests in
            XCTAssertEqual(requests.count, 0, "There should be no tracing `Spans` send")
            return true
        }

        // Assert it adds custom RUM attributes to intercepted RUM Resources:
        session.resourceEventMatchers.forEach { resourceEvent in
            XCTAssertNotNil(try? resourceEvent.attribute(forKeyPath: "context.response.body.truncated") as String)
            XCTAssertNotNil(try? resourceEvent.attribute(forKeyPath: "context.response.headers") as String)
            XCTAssertNil(try? resourceEvent.attribute(forKeyPath: "context.response.error") as String)
        }

        // Assert it adds custom RUM attributes to intercepted RUM Resources which finished with error:
        session.errorEventMatchers.forEach { errorEvent in
            XCTAssertNil(try? errorEvent.attribute(forKeyPath: "context.response.body.truncated") as String)
            XCTAssertNil(try? errorEvent.attribute(forKeyPath: "context.response.headers") as String)
            XCTAssertNotNil(try? errorEvent.attribute(forKeyPath: "context.response.error") as String)
        }
    }

    private func getTraceID(from request: Request) -> TraceID? {
        guard let traceIDLoValue = request.httpHeaders["x-datadog-trace-id"] else {
            return nil
        }

        // tags are comma separated key=value pairs
        let tags = request.httpHeaders[TracingHTTPHeaders.tagsField]?.split(separator: ",")
            .map { $0.split(separator: "=") }
            .reduce(into: [String: String]()) { result, pair in
                if pair.count == 2 {
                    result[String(pair[0])] = String(pair[1])
                }
            } ?? [:]

        let traceIDHiValue = tags[TracingHTTPHeaders.TagKeys.traceIDHi] ?? "0"
        
        return .init(
            idHi: UInt64(traceIDHiValue, radix: 16) ?? 0,
            idLo: UInt64(traceIDLoValue, radix: 10) ?? 0
        )
    }
    private func getSpanID(from request: Request) -> SpanID? {
        guard let spanId = request.httpHeaders["x-datadog-parent-id"] else {
            return nil
        }
        return .init(spanId, representation: .decimal)
    }
    private func isValid(sampleRate: Double) -> Bool { sampleRate >= 0 && sampleRate <= 1 }
}
