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
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.datadog]
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField), "rum")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "64")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.tagsField), "_dd.p.tid=a")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "64")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 100)
        XCTAssertNil(injectedTraceContext.parentSpanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, 100)
        XCTAssertTrue(injectedTraceContext.isKept)
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectB3TraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: B3HTTPHeaders.Single.b3Field), "000000000000000a0000000000000064-0000000000000064-1")

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 100)
        XCTAssertNil(injectedTraceContext.parentSpanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, 100)
        XCTAssertTrue(injectedTraceContext.isKept)
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectB3MultiTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3multi]
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
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectW3CTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.tracecontext]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-000000000000000a0000000000000064-0000000000000064-01")

        let injectedTraceContext = try XCTUnwrap(traceContext, "It must return injected trace context")
        XCTAssertEqual(injectedTraceContext.traceID, .init(idHi: 10, idLo: 100))
        XCTAssertEqual(injectedTraceContext.spanID, 100)
        XCTAssertNil(injectedTraceContext.parentSpanID)
        XCTAssertEqual(injectedTraceContext.sampleRate, 100)
        XCTAssertTrue(injectedTraceContext.isKept)
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectDDTraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.datadog]
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField), "rum")
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectB3TraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3]
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
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3multi]
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
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )

        // When
        let (request, traceContext) = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.tracecontext]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-000000000000000a0000000000000064-0000000000000064-00")

        XCTAssertNil(traceContext, "It must return no trace context")
    }

    func testGivenFirstPartyInterception_withSampledTrace_itDoesNotOverwriteTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: .init(idHi: 10, idLo: 100)),
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
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

        let (request, traceContext) = handler.modify(
            request: orgRequest,
            headerTypes: [
                .datadog,
                .b3,
                .b3multi,
                .tracecontext
            ]
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
                spanIDGenerator: DefaultSpanIDGenerator()
            )
        )

        let taskInterception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: .random())
        taskInterception.register(trace: TraceContext(
            traceID: 100,
            spanID: 200,
            parentSpanID: nil,
            sampleRate: .mockAny(),
            isKept: .mockAny()
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
                spanIDGenerator: RelativeSpanIDGenerator(startingFrom: 100, advancingByCount: 0)
            )
        )
        let request: URLRequest = .mockWith(httpMethod: "GET")
        let (modifiedRequest, _) = handler.modify(request: request, headerTypes: [.datadog, .tracecontext, .b3, .b3multi])

        XCTAssertEqual(
            modifiedRequest.allHTTPHeaderFields,
            [
                "tracestate": "dd=o:rum;p:0000000000000064;s:1",
                "traceparent": "00-000000000000000a0000000000000064-0000000000000064-01",
                "X-B3-SpanId": "0000000000000064",
                "X-B3-Sampled": "1",
                "X-B3-TraceId": "000000000000000a0000000000000064",
                "b3": "000000000000000a0000000000000064-0000000000000064-1",
                "x-datadog-trace-id": "64",
                "x-datadog-parent-id": "64",
                "x-datadog-sampling-priority": "1",
                "x-datadog-origin": "rum",
                "x-datadog-tags": "_dd.p.tid=a"
            ]
        )
    }
}
