/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogRUM

class URLSessionRUMResourcesHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()

    private func createHandler(
        rumAttributesProvider: RUM.ResourceAttributesProvider? = nil,
        distributedTracing: DistributedTracing? = nil
    ) -> URLSessionRUMResourcesHandler {
        let handler = URLSessionRUMResourcesHandler(
            dateProvider: dateProvider,
            rumAttributesProvider: rumAttributesProvider,
            distributedTracing: distributedTracing
        )
        handler.publish(to: commandSubscriber)
        return handler
    }

    private lazy var handler = createHandler(rumAttributesProvider: nil)

    func testGivenFirstPartyInterception_withSampledTrace_itInjectDDTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.datadog],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField), "rum")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "100")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "_dd.p.tid=a")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "100")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.baggage), "session.id=abcdef01-2345-6789-abcd-ef0123456789")

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 100)
        XCTAssertNil(injectedTraceContext.parentSpanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, 100)
        XCTAssertTrue(injectedTraceContext.isKept)
        XCTAssertEqual(injectedTraceContext.rumSessionId, "abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectB3TraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "000000000000000a0000000000000064-0000000000000064-1")

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 100)
        XCTAssertNil(injectedTraceContext.parentSpanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, 100)
        XCTAssertTrue(injectedTraceContext.isKept)
        XCTAssertEqual(injectedTraceContext.rumSessionId, "abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectB3MultiTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3multi],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "000000000000000a0000000000000064")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "0000000000000064")
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "1")

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 100)
        XCTAssertNil(injectedTraceContext.parentSpanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, 100)
        XCTAssertTrue(injectedTraceContext.isKept)
        XCTAssertEqual(injectedTraceContext.rumSessionId, "abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectW3CTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.tracecontext],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-000000000000000a0000000000000064-0000000000000064-01")

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 100)
        XCTAssertNil(injectedTraceContext.parentSpanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, 100)
        XCTAssertTrue(injectedTraceContext.isKept)
        XCTAssertEqual(injectedTraceContext.rumSessionId, "abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectDDTraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .sampled
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.datadog],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField), "rum")
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField))

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectB3TraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "0")

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectB3MultiTraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3multi],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "0")

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectW3CTraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.tracecontext],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-000000000000000a0000000000000064-0000000000000064-00")

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterceptionAndShouldSetBaggageHeaderAndBaggageHeaderValuesToSet_withSampledTrace_itDoesNotOverwriteTraceHeadersExceptBaggage() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        var orgRequest: URLRequest = .mockWith(url: "https://www.example.com")
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.traceIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.tagsField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Single.b3Field)
        orgRequest.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.traceparent)
        orgRequest.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.tracestate)
        let initialBaggageHeaderValue = "custom=12"
        orgRequest.setValue(initialBaggageHeaderValue, forHTTPHeaderField: W3CHTTPHeaders.baggage)

        let (request, _) = handler.modify(
            request: orgRequest,
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                ),
                userConfigurationContext: .mockWith(id: "some_user_id"),
                accountConfigurationContext: .mockRandom()
            )
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.tracestate), "custom")
        XCTAssertNotEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.baggage), initialBaggageHeaderValue)
    }

    func testGivenFirstPartyInterceptionAndShouldNotSetBaggageHeaderAndBaggageHeaderValuesToSet_withSampledTrace_itDoesNotOverwriteTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        var orgRequest: URLRequest = .mockWith(url: "https://www.example.com")
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.traceIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.tagsField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Single.b3Field)
        orgRequest.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.traceparent)
        orgRequest.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.tracestate)
        orgRequest.setValue("custom=12", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        let (request, traceContext) = handler.modify(
            request: orgRequest,
            headerTypes: [
                .b3,
                .b3multi,
            ],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                ),
                userConfigurationContext: .mockWith(id: "some_user_id"),
                accountConfigurationContext: .mockRandom()
            )
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.tracestate), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.baggage), "custom=12")

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterceptionAndShouldSetBaggageHeaderAndBaggageHeaderValuesEmpty_withSampledTrace_itDoesNotOverwriteTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        // When
        var orgRequest: URLRequest = .mockWith(url: "https://www.example.com")
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.traceIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.tagsField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField)
        orgRequest.setValue("custom", forHTTPHeaderField: B3HTTPHeaders.Single.b3Field)
        orgRequest.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.traceparent)
        orgRequest.setValue("custom", forHTTPHeaderField: W3CHTTPHeaders.tracestate)
        orgRequest.setValue("custom=12", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        let (request, traceContext) = handler.modify(
            request: orgRequest,
            headerTypes: [
                .b3,
                .b3multi,
            ],
            networkContext: NetworkContext(
                rumContext: nil,
                userConfigurationContext: nil,
                accountConfigurationContext: nil
            )
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.traceIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.spanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.parentSpanIDField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Multiple.sampledField), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.tracestate), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.baggage), "custom=12")

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenTaskInterceptionWithNoSpanContext_whenInterceptionStarts_itStartsRUMResource() throws {
        let receiveCommand = expectation(description: "Receive RUM command")
        commandSubscriber.onCommandReceived = { _ in receiveCommand.fulfill() }

        // Given
        let request: ImmutableRequest = .mockWith(
            url: .mockRandom(),
            httpMethod: ["GET", "POST", "PUT", "DELETE"].randomElement()!
        )
        let taskInterception = URLSessionTaskInterception(request: request, isFirstParty: .random())
        XCTAssertNil(taskInterception.trace)

        // When
        handler.interceptionDidStart(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let resourceStartCommand = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMStartResourceCommand)
        XCTAssertEqual(resourceStartCommand.resourceKey, taskInterception.identifier.uuidString)
        XCTAssertEqual(resourceStartCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceStartCommand.attributes.count, 0)
        XCTAssertEqual(resourceStartCommand.url, taskInterception.request.url?.absoluteString)
        XCTAssertEqual(resourceStartCommand.httpMethod, RUMMethod(httpMethod: request.httpMethod))
        XCTAssertNil(resourceStartCommand.spanContext)
    }

    func testGivenTaskInterceptionWithSpanContext_whenInterceptionStarts_itStartsRUMResource() throws {
        let receiveCommand = expectation(description: "Receive RUM command")
        commandSubscriber.onCommandReceived = { _ in receiveCommand.fulfill() }

        // Given
        let traceSamplingRate: Double = .mockRandom(min: 0, max: 100)

        let handler = createHandler(
            distributedTracing: .init(
                sampler: Sampler(samplingRate: Float(traceSamplingRate)),
                firstPartyHosts: .init(),
                traceIDGenerator: DefaultTraceIDGenerator(),
                spanIDGenerator: DefaultSpanIDGenerator(),
                traceContextInjection: .all
            )
        )

        let taskInterception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: .random())
        taskInterception.register(trace: TraceContext(
            traceID: 100,
            spanID: 200,
            parentSpanID: nil,
            sampleRate: .mockAny(),
            isKept: .mockAny(),
            rumSessionId: .mockAny()
        ))
        XCTAssertNotNil(taskInterception.trace)

        // When
        handler.interceptionDidStart(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let resourceStartCommand = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMStartResourceCommand)
        let spanContext = try XCTUnwrap(resourceStartCommand.spanContext)
        XCTAssertEqual(spanContext.traceID, .init(idLo: 100))
        XCTAssertEqual(spanContext.spanID, .init(rawValue: 200))
        XCTAssertEqual(spanContext.samplingRate, traceSamplingRate / 100, accuracy: 0.01)
    }

    func testGivenTaskInterceptionWithMetricsAndResponse_whenInterceptionCompletes_itStopsRUMResourceWithMetrics() throws {
        let receiveCommands = expectation(description: "Receive 2 RUM commands")
        receiveCommands.expectedFulfillmentCount = 2
        var commandsReceived: [RUMCommand] = []
        commandSubscriber.onCommandReceived = { command in
            commandsReceived.append(command)
            receiveCommands.fulfill()
        }

        // Given
        let taskInterception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: .random())
        let resourceMetrics: ResourceMetrics = .mockAny()
        taskInterception.register(metrics: resourceMetrics)
        let response: HTTPURLResponse = .mockResponseWith(statusCode: 200)
        taskInterception.register(response: response, error: nil)

        // When
        handler.interceptionDidComplete(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let resourceMetricsCommand = try XCTUnwrap(commandsReceived[0] as? RUMAddResourceMetricsCommand)
        XCTAssertEqual(resourceMetricsCommand.resourceKey, taskInterception.identifier.uuidString)
        XCTAssertEqual(resourceMetricsCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceMetricsCommand.attributes.count, 0)
        DDAssertReflectionEqual(resourceMetricsCommand.metrics, taskInterception.metrics)

        let resourceStopCommand = try XCTUnwrap(commandsReceived[1] as? RUMStopResourceCommand)
        XCTAssertEqual(resourceStopCommand.resourceKey, taskInterception.identifier.uuidString)
        XCTAssertEqual(resourceStopCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceStopCommand.attributes.count, 0)
        XCTAssertEqual(resourceStopCommand.kind, RUMResourceType(response: response))
        XCTAssertEqual(resourceStopCommand.httpStatusCode, 200)
        XCTAssertEqual(resourceStopCommand.size, taskInterception.metrics?.responseSize)
    }

    func testGivenTaskInterceptionWithMetricsAndError_whenInterceptionCompletes_itStopsRUMResourceWithErrorAndMetrics() throws {
        let receiveCommands = expectation(description: "Receive 2 RUM commands")
        receiveCommands.expectedFulfillmentCount = 2
        var commandsReceived: [RUMCommand] = []
        commandSubscriber.onCommandReceived = { command in
            commandsReceived.append(command)
            receiveCommands.fulfill()
        }

        // Given
        let taskInterception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: .random())
        let taskError = NSError(domain: "domain", code: 123, userInfo: [NSLocalizedDescriptionKey: "network error"])
        let resourceMetrics: ResourceMetrics = .mockAny()
        taskInterception.register(metrics: resourceMetrics)
        taskInterception.register(response: nil, error: taskError)

        // When
        handler.interceptionDidComplete(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let resourceMetricsCommand = try XCTUnwrap(commandsReceived[0] as? RUMAddResourceMetricsCommand)
        XCTAssertEqual(resourceMetricsCommand.resourceKey, taskInterception.identifier.uuidString)
        XCTAssertEqual(resourceMetricsCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceMetricsCommand.attributes.count, 0)
        DDAssertReflectionEqual(resourceMetricsCommand.metrics, taskInterception.metrics)

        let resourceStopCommand = try XCTUnwrap(commandsReceived[1] as? RUMStopResourceWithErrorCommand)
        XCTAssertEqual(resourceStopCommand.resourceKey, taskInterception.identifier.uuidString)
        XCTAssertEqual(resourceStopCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceStopCommand.attributes.count, 0)
        XCTAssertEqual(resourceStopCommand.errorType, DDError(error: taskError).type)
        XCTAssertEqual(resourceStopCommand.errorMessage, DDError(error: taskError).message)
        XCTAssertEqual(resourceStopCommand.errorSource, .network)
        XCTAssertEqual(resourceStopCommand.stack, DDError(error: taskError).stack)
        XCTAssertNil(resourceStopCommand.httpStatusCode)
    }

    // MARK: - RUM Resource Attributes Provider

    func testGivenRUMAttributesProviderRegistered_whenInterceptionCompletesWithResponse_itAddsCustomRUMAttributes() throws {
        let receiveCommand = expectation(description: "Receive RUMStopResourceCommand")
        var stopResourceCommand: RUMStopResourceCommand?
        commandSubscriber.onCommandReceived = { command in
            if let command = command as? RUMStopResourceCommand {
                stopResourceCommand = command
                receiveCommand.fulfill()
            }
        }

        // Given
        let mockRequest: ImmutableRequest = .mockAny()
        let mockResponse: URLResponse = .mockAny()
        let mockData: Data = .mockRandom()
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()

        let handler = createHandler { request, response, data, error in
            XCTAssertEqual(request, mockRequest.unsafeOriginal)
            XCTAssertEqual(response, mockResponse)
            XCTAssertEqual(data, mockData)
            XCTAssertNil(error)
            return mockAttributes
        }

        // When
        let taskInterception = URLSessionTaskInterception(request: mockRequest, isFirstParty: .random())
        taskInterception.register(nextData: mockData)
        taskInterception.register(metrics: .mockAny())
        taskInterception.register(response: mockResponse, error: nil)
        handler.interceptionDidComplete(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        DDAssertDictionariesEqual(stopResourceCommand!.attributes, mockAttributes)
    }

    func testGivenTaskInterceptionWithError_whenInterceptionCompletes_itAsksForCustomRUMAttributes() throws {
        let receiveCommand = expectation(description: "Receive RUMStopResourceWithErrorCommand")
        var stopResourceWithErrorCommand: RUMStopResourceWithErrorCommand?
        commandSubscriber.onCommandReceived = { command in
            if let command = command as? RUMStopResourceWithErrorCommand {
                stopResourceWithErrorCommand = command
                receiveCommand.fulfill()
            }
        }

        // Given
        let mockRequest: ImmutableRequest = .mockAny()
        let mockError = ErrorMock()
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()

        let handler = createHandler { request, response, data, error in
            XCTAssertEqual(request, mockRequest.unsafeOriginal)
            XCTAssertNil(response)
            XCTAssertNil(data)
            XCTAssertTrue(error is ErrorMock)
            return mockAttributes
        }

        // When
        let taskInterception = URLSessionTaskInterception(request: mockRequest, isFirstParty: .random())
        taskInterception.register(metrics: .mockAny())
        taskInterception.register(response: nil, error: mockError)
        handler.interceptionDidComplete(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        DDAssertDictionariesEqual(stopResourceWithErrorCommand!.attributes, mockAttributes)
    }

    func testGivenAllTracingHeaderTypes_itUsesTheSameIds() throws {
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )
        let request: URLRequest = .mockWith(httpMethod: "GET")
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
                "tracestate": "dd=o:rum;p:0000000000000064;s:1",
                "traceparent": "00-000000000000000a0000000000000064-0000000000000064-01",
                "X-B3-SpanId": "0000000000000064",
                "X-B3-Sampled": "1",
                "X-B3-TraceId": "000000000000000a0000000000000064",
                "b3": "000000000000000a0000000000000064-0000000000000064-1",
                "x-datadog-trace-id": "100",
                "x-datadog-parent-id": "100",
                "x-datadog-sampling-priority": "1",
                "x-datadog-origin": "rum",
                "x-datadog-tags": "_dd.p.tid=a",
                "baggage": "session.id=abcdef01-2345-6789-abcd-ef0123456789",
            ]
        )
    }

    // MARK: - Baggage Header Merging Tests

    func testGivenRequestWithExistingBaggageHeader_whenTraceContextIsInjected_itMergesBaggageHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        var request = URLRequest.mockWith(url: "https://www.example.com")
        request.setValue("custom.key=custom.value,another.key=another.value", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        // When
        let (modifiedRequest, _) = handler.modify(
            request: request,
            headerTypes: [.datadog],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)

        // Verify that both existing and new baggage values are present
        XCTAssertTrue(baggageHeader?.contains("custom.key=custom.value") == true)
        XCTAssertTrue(baggageHeader?.contains("another.key=another.value") == true)
        XCTAssertTrue(baggageHeader?.contains("session.id=abcdef01-2345-6789-abcd-ef0123456789") == true)
    }

    func testGivenRequestWithExistingBaggageHeader_whenTraceContextIsInjectedWithW3C_itMergesBaggageHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        var request = URLRequest.mockWith(url: "https://www.example.com")
        request.setValue("custom.key=custom.value,session.id=old.session.id", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        // When
        let (modifiedRequest, _) = handler.modify(
            request: request,
            headerTypes: [.tracecontext],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)

        // Verify that existing custom key is preserved
        XCTAssertTrue(baggageHeader?.contains("custom.key=custom.value") == true)
        // Verify that session.id is overridden with new value
        XCTAssertTrue(baggageHeader?.contains("session.id=abcdef01-2345-6789-abcd-ef0123456789") == true)
        XCTAssertFalse(baggageHeader?.contains("session.id=old.session.id") == true)
    }

    func testGivenRequestWithComplexBaggageHeader_whenTraceContextIsInjected_itMergesBaggageHeadersCorrectly() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        var request = URLRequest.mockWith(url: "https://www.example.com")
        // This is the complex scenario from the user's requirement
        request.setValue(" toto=1,car= Dacia Sandero ,session.id = 2,testProp=1; testProp2=4;prop3 ", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        // When
        let (modifiedRequest, _) = handler.modify(
            request: request,
            headerTypes: [.tracecontext],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                ),
                userConfigurationContext: .init(id: "user123"),
                accountConfigurationContext: .init(id: "account456")
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)

        // Parse the result to verify merging behavior
        let baggageDict = extractBaggageKeyValuePairs(from: baggageHeader!)

        // Verify that new values override previous ones
        XCTAssertEqual(baggageDict["session.id"], "abcdef01-2345-6789-abcd-ef0123456789")

        // Verify that previous values are preserved when not overridden
        XCTAssertEqual(baggageDict["toto"], "1")
        XCTAssertEqual(baggageDict["car"], "Dacia Sandero")
        XCTAssertEqual(baggageDict["testProp"], "1; testProp2=4;prop3")

        // Verify that new values are added
        XCTAssertEqual(baggageDict["user.id"], "user123")
        XCTAssertEqual(baggageDict["account.id"], "account456")

        // Verify all expected keys are present
        XCTAssertEqual(baggageDict.keys.count, 6)
    }

    func testGivenRequestWithoutBaggageHeader_whenTraceContextIsInjected_itAddsBaggageHeader() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        let request = URLRequest.mockWith(url: "https://www.example.com")

        // When
        let (modifiedRequest, _) = handler.modify(
            request: request,
            headerTypes: [.tracecontext],
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)
        XCTAssertEqual(baggageHeader, "session.id=abcdef01-2345-6789-abcd-ef0123456789")
    }

    func testGivenRequestWithBaggageHeader_whenMultipleHeaderTypesAreInjected_itMergesBaggageOnlyOnce() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0),
                traceContextInjection: .all
            )
        )

        var request = URLRequest.mockWith(url: "https://www.example.com")
        request.setValue("custom.key=custom.value", forHTTPHeaderField: W3CHTTPHeaders.baggage)

        // When
        let (modifiedRequest, _) = handler.modify(
            request: request,
            headerTypes: [.datadog, .tracecontext], // Both inject baggage headers
            networkContext: NetworkContext(
                rumContext: .init(
                    applicationID: .mockRandom(),
                    sessionID: "abcdef01-2345-6789-abcd-ef0123456789"
                )
            )
        )

        // Then
        let baggageHeader = modifiedRequest.value(forHTTPHeaderField: W3CHTTPHeaders.baggage)
        XCTAssertNotNil(baggageHeader)

        // Verify that session.id appears only once (not duplicated)
        let sessionIdMatches = baggageHeader?.components(separatedBy: "session.id=").count ?? 0
        XCTAssertEqual(sessionIdMatches, 2) // Original string + 1 occurrence = 2

        // Verify that both custom and session values are present
        XCTAssertTrue(baggageHeader?.contains("custom.key=custom.value") == true)
        XCTAssertTrue(baggageHeader?.contains("session.id=abcdef01-2345-6789-abcd-ef0123456789") == true)
    }

    // MARK: - GraphQL Header Extraction Tests

    func testGivenRequestWithGraphQLHeaders_whenInterceptionCompletes_itExtractsGraphQLAttributes() throws {
        let receiveCommand = expectation(description: "Receive RUMStopResourceCommand")
        var stopResourceCommand: RUMStopResourceCommand?
        commandSubscriber.onCommandReceived = { command in
            if let command = command as? RUMStopResourceCommand {
                stopResourceCommand = command
                receiveCommand.fulfill()
            }
        }

        // Given
        var mockRequest: URLRequest = .mockWith(url: "https://graphql.example.com/api")
        mockRequest.setValue("GetUser", forHTTPHeaderField: ExpectedGraphQLHeaders.operationName)
        mockRequest.setValue("query", forHTTPHeaderField: ExpectedGraphQLHeaders.operationType)
        mockRequest.setValue("{\"userId\":\"123\"}", forHTTPHeaderField: ExpectedGraphQLHeaders.variables)
        mockRequest.setValue("query GetUser($userId: ID!) { user(id: $userId) { name } }", forHTTPHeaderField: ExpectedGraphQLHeaders.payload)

        let immutableRequest = ImmutableRequest(request: mockRequest)
        let taskInterception = URLSessionTaskInterception(request: immutableRequest, isFirstParty: false)
        let response: HTTPURLResponse = .mockResponseWith(statusCode: 200)
        taskInterception.register(response: response, error: nil)

        // When
        handler.interceptionDidComplete(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let attributes = try XCTUnwrap(stopResourceCommand?.attributes)
        XCTAssertEqual(attributes[CrossPlatformAttributes.graphqlOperationName] as? String, "GetUser")
        XCTAssertEqual(attributes[CrossPlatformAttributes.graphqlOperationType] as? String, "query")
        XCTAssertEqual(attributes[CrossPlatformAttributes.graphqlVariables] as? String, "{\"userId\":\"123\"}")
        XCTAssertEqual(attributes[CrossPlatformAttributes.graphqlPayload] as? String, "query GetUser($userId: ID!) { user(id: $userId) { name } }")
    }

    func testGivenRequestWithGraphQLHeaders_whenInterceptionCompletesWithError_itExtractsGraphQLAttributes() throws {
        let receiveCommand = expectation(description: "Receive RUMStopResourceWithErrorCommand")
        var stopResourceWithErrorCommand: RUMStopResourceWithErrorCommand?
        commandSubscriber.onCommandReceived = { command in
            if let command = command as? RUMStopResourceWithErrorCommand {
                stopResourceWithErrorCommand = command
                receiveCommand.fulfill()
            }
        }

        // Given
        var mockRequest: URLRequest = .mockWith(url: "https://graphql.example.com/api")
        mockRequest.setValue("FailedMutation", forHTTPHeaderField: ExpectedGraphQLHeaders.operationName)
        mockRequest.setValue("mutation", forHTTPHeaderField: ExpectedGraphQLHeaders.operationType)

        let immutableRequest = ImmutableRequest(request: mockRequest)
        let taskInterception = URLSessionTaskInterception(request: immutableRequest, isFirstParty: false)
        let taskError = NSError(domain: "network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection failed"])
        taskInterception.register(response: nil, error: taskError)

        // When
        handler.interceptionDidComplete(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let attributes = try XCTUnwrap(stopResourceWithErrorCommand?.attributes)
        XCTAssertEqual(attributes[CrossPlatformAttributes.graphqlOperationName] as? String, "FailedMutation")
        XCTAssertEqual(attributes[CrossPlatformAttributes.graphqlOperationType] as? String, "mutation")
    }

    // MARK: - Helper Methods

    private func extractBaggageKeyValuePairs(from header: String) -> [String: String] {
        var dict: [String: String] = [:]
        let fields = header.split(separator: ",")

        for field in fields {
            let fieldString = String(field)
            if let equalIndex = fieldString.firstIndex(of: "=") {
                let key = fieldString[..<equalIndex].trimmingCharacters(in: .whitespaces)
                let value = fieldString[fieldString.index(after: equalIndex)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    dict[key] = value
                }
            }
        }

        return dict
    }
}

// MARK: - Test Helpers

struct ExpectedGraphQLHeaders {
    static let operationName: String = "_dd-custom-header-graph-ql-operation-name"
    static let operationType: String = "_dd-custom-header-graph-ql-operation-type"
    static let variables: String = "_dd-custom-header-graph-ql-variables"
    static let payload: String = "_dd-custom-header-graph-ql-payload"
}
