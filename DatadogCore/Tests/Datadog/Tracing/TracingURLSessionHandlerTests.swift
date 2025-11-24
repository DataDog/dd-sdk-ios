/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogLogs
@testable import DatadogTrace

class TracingURLSessionHandlerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    var core: PassthroughCoreMock!
    var tracer: DatadogTracer!
    var handler: TracingURLSessionHandler!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        let receiver = ContextMessageReceiver()
        core = PassthroughCoreMock(messageReceiver: CombinedFeatureMessageReceiver([
            LogMessageReceiver.mockAny(),
            receiver
        ]))

        tracer = .mockWith(
            core: core,
            traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
            spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
            loggingIntegration: TracingWithLoggingIntegration(core: core, service: .mockAny(), networkInfoEnabled: .mockAny())
        )

        handler = TracingURLSessionHandler(
            tracer: tracer,
            contextReceiver: receiver,
            samplingRate: .maxSampleRate,
            firstPartyHosts: .init([
                "www.example.com": [.datadog]
            ]),
            traceContextInjection: .all
        )
    }

    override func tearDown() {
        core = nil
        tracer = nil
        handler = nil
        super.tearDown()
    }

    func testGivenFirstPartyInterceptionWithNoError_itDoesNotSendLog() throws {
        let expectation = expectation(description: "Send span")
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let request: ImmutableRequest = .mockWith(httpMethod: "POST")
        // TODO: RUM-13455 - Trace requires metrics mode for now
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .metrics)
        interception.register(metrics: .mockAny())
        interception.register(response: .mockResponseWith(statusCode: 200), error: nil)

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        XCTAssertNotNil(envelope?.spans.first)

        let log: LogEvent? = core.events().last
        XCTAssertNil(log)
    }

    func testGivenFirstPartyInterceptionWithNetworkError_whenInterceptionCompletes_itEncodesRequestInfoInSpanAndSendsLog() throws {
        let expectation = expectation(description: "Send span and log")
        expectation.expectedFulfillmentCount = 2
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let request: ImmutableRequest = .mockWith(
            url: URL(string: "http://www.example.com")!,
            httpMethod: "GET"
        )
        let error = NSError(domain: "domain", code: 123, userInfo: [NSLocalizedDescriptionKey: "network error"])
        // TODO: RUM-13455 - Trace requires metrics mode for now
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .metrics)
        interception.register(response: nil, error: error)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 30)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(span.resource, "http://www.example.com")
        XCTAssertEqual(span.duration, 30)
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags[OTTags.httpUrl], request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod], "GET")
        XCTAssertEqual(span.tags[SpanTags.errorType], "domain - 123")
        XCTAssertEqual(span.tags[SpanTags.kind], "client")
        XCTAssertEqual(
            span.tags[SpanTags.errorStack],
            "Error Domain=domain Code=123 \"network error\" UserInfo={NSLocalizedDescription=network error}"
        )
        XCTAssertEqual(span.tags[SpanTags.errorMessage], "network error")
        XCTAssertEqual(span.tags.count, 8)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send error log")
        XCTAssertEqual(log.status, .error)
        XCTAssertEqual(log.message, "network error")
        XCTAssertEqual(
            log.attributes.internalAttributes?["dd.trace_id"] as? String,
            String(span.traceID, representation: .hexadecimal)
        )
        XCTAssertEqual(
            log.attributes.internalAttributes?["dd.trace_id"] as? String,
            String(span.traceID, representation: .hexadecimal)
        )
        XCTAssertEqual(
            log.attributes.internalAttributes?["dd.span_id"] as? String,
            String(span.spanID, representation: .hexadecimal)
        )
        XCTAssertEqual(log.error?.kind, "domain - 123")
        XCTAssertEqual(log.attributes.internalAttributes?.count, 2)
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.userAttributes[OTLogFields.event]),
            "error"
        )
        XCTAssertEqual(
            log.error?.stack,
            "Error Domain=domain Code=123 \"network error\" UserInfo={NSLocalizedDescription=network error}"
        )
        XCTAssertEqual(log.attributes.userAttributes.count, 1)
    }

    func testGivenFirstPartyInterceptionWithClientError_whenInterceptionCompletes_itEncodesRequestInfoInSpanAndSendsLog() throws {
        let expectation = expectation(description: "Send span and log")
        expectation.expectedFulfillmentCount = 2
        core.onEventWriteContext = { _ in expectation.fulfill() }

        // Given
        let request: ImmutableRequest = .mockWith(httpMethod: "GET")
        // TODO: RUM-13455 - Trace requires metrics mode for now
        let interception = URLSessionTaskInterception(request: request, isFirstParty: true, trackingMode: .metrics)
        interception.register(response: .mockResponseWith(statusCode: 404), error: nil)
        interception.register(
            metrics: .mockWith(
                fetch: .init(
                    start: .mockDecember15th2019At10AMUTC(),
                    end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)
                )
            )
        )

        // When
        handler.interceptionDidComplete(interception: interception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let envelope: SpanEventsEnvelope? = core.events().last
        let span = try XCTUnwrap(envelope?.spans.first)
        XCTAssertEqual(span.operationName, "urlsession.request")
        XCTAssertEqual(span.resource, "404")
        XCTAssertEqual(span.duration, 2)
        XCTAssertTrue(span.isError)
        XCTAssertEqual(span.tags[OTTags.httpUrl], request.url!.absoluteString)
        XCTAssertEqual(span.tags[OTTags.httpMethod], "GET")
        XCTAssertEqual(span.tags[OTTags.httpStatusCode], "404")
        XCTAssertEqual(span.tags[SpanTags.errorType], "HTTPURLResponse - 404")
        XCTAssertEqual(span.tags[SpanTags.errorMessage], "404 not found")
        XCTAssertEqual(span.tags[SpanTags.kind], "client")
        XCTAssertEqual(
            span.tags[SpanTags.errorStack],
            "Error Domain=HTTPURLResponse Code=404 \"404 not found\" UserInfo={NSLocalizedDescription=404 not found}"
        )
        XCTAssertEqual(span.tags.count, 9)

        let log: LogEvent = try XCTUnwrap(core.events().last, "It should send error log")
        XCTAssertEqual(log.status, .error)
        XCTAssertEqual(log.message, "404 not found")
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes?["dd.trace_id"]),
            String(span.traceID, representation: .hexadecimal)
        )
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.internalAttributes?["dd.span_id"]),
            String(span.spanID, representation: .hexadecimal)
        )
        XCTAssertEqual(log.error?.kind, "HTTPURLResponse - 404")
        XCTAssertEqual(log.attributes.internalAttributes?.count, 2)
        DDAssertJSONEqual(
            AnyEncodable(log.attributes.userAttributes[OTLogFields.event]),
            "error"
        )
        XCTAssertEqual(
            log.error?.stack,
            "Error Domain=HTTPURLResponse Code=404 \"404 not found\" UserInfo={NSLocalizedDescription=404 not found}"
        )
        XCTAssertEqual(log.attributes.userAttributes.count, 1)
    }

    func testGivenAllTracingHeaderTypes_itUsesTheSameIds() throws {
        let request: URLRequest = .mockWith(httpMethod: "GET")
        let fakeSessionId = "8b723a25-e941-47ea-9173-910c866ccf19"
        let fakeContext: DatadogContext = .mockWith(
            additionalContext: [
                RUMCoreContext(
                    applicationID: .mockRandom(),
                    sessionID: fakeSessionId
                )
            ]
        )
        let message = FeatureMessage.context(fakeContext)
        _ = handler.contextReceiver.receive(message: message, from: core)
        let (modifiedRequest, _) = handler.modify(
            request: request,
            headerTypes: [.datadog, .tracecontext, .b3, .b3multi],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertEqual(
            modifiedRequest.allHTTPHeaderFields,
            [
                "traceparent": "00-000000000000000a0000000000000064-0000000000000064-01",
                "X-B3-SpanId": "0000000000000064",
                "X-B3-Sampled": "1",
                "X-B3-TraceId": "000000000000000a0000000000000064",
                "b3": "000000000000000a0000000000000064-0000000000000064-1",
                "x-datadog-trace-id": "100",
                "x-datadog-tags": "_dd.p.tid=a,_dd.p.dm=-1",
                "baggage": "session.id=\(fakeSessionId)",
                "tracestate": "dd=p:0000000000000064;s:1;t.dm:-1",
                "x-datadog-parent-id": "100",
                "x-datadog-sampling-priority": "1"
            ]
        )
    }
}
