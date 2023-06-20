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
        rumAttributesProvider: RUMResourceAttributesProvider? = nil,
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
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
            )
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.datadog]
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField), "rum")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "1")
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectB3TraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
            )
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Single.b3Field), "00000000000000000000000000000001-0000000000000001-1")
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectB3MultiTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
            )
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3multi]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.traceIDField), "00000000000000000000000000000001")
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.spanIDField), "0000000000000001")
        XCTAssertNil(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.sampledField), "1")
    }

    func testGivenFirstPartyInterception_withSampledTrace_itInjectW3CTraceHeaders() throws {
        // Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockKeepAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
            )
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.tracecontext]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-00000000000000000000000000000001-0000000000000001-01")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectDDTraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
            )
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.datadog]
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField), "rum")
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: TracingHTTPHeaders.samplingPriorityField), "0")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectB3TraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
            )
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Single.b3Field), "0")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectB3MultiTraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
            )
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.b3multi]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertNil(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.traceIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.spanIDField))
        XCTAssertNil(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.parentSpanIDField))
        XCTAssertEqual(request.value(forHTTPHeaderField: OTelHTTPHeaders.Multiple.sampledField), "0")
    }

    func testGivenFirstPartyInterception_withRejectedTrace_itDoesNotInjectW3CTraceHeaders() throws {
        /// Given
        let handler = createHandler(
            distributedTracing: .init(
                sampler: .mockRejectAll(),
                firstPartyHosts: .init(),
                traceIDGenerator: RelativeTracingUUIDGenerator(startingFrom: 1, advancingByCount: 0)
            )
        )

        // When
        let request = handler.modify(
            request: .mockWith(url: "https://www.example.com"),
            headerTypes: [.tracecontext]
        )

        XCTAssertNil(request.value(forHTTPHeaderField: TracingHTTPHeaders.originField))
        XCTAssertEqual(request.value(forHTTPHeaderField: W3CHTTPHeaders.traceparent), "00-00000000000000000000000000000001-0000000000000001-00")
    }

    func testGivenTaskInterceptionWithNoSpanContext_whenInterceptionStarts_itStartsRUMResource() throws {
        let receiveCommand = expectation(description: "Receive RUM command")
        commandSubscriber.onCommandReceived = { _ in receiveCommand.fulfill() }

        // Given
        var request = URLRequest(url: .mockRandom())
        request.httpMethod = ["GET", "POST", "PUT", "DELETE"].randomElement()!
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
                traceIDGenerator: DefaultTraceIDGenerator()
            )
        )

        let taskInterception = URLSessionTaskInterception(request: .mockAny(), isFirstParty: .random())
        taskInterception.register(traceID: 1, spanID: 2, parentSpanID: nil)
        XCTAssertNotNil(taskInterception.trace)

        // When
        handler.interceptionDidStart(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let resourceStartCommand = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMStartResourceCommand)
        let spanContext = try XCTUnwrap(resourceStartCommand.spanContext)
        XCTAssertEqual(spanContext.traceID, "1")
        XCTAssertEqual(spanContext.spanID, "2")
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
        let mockRequest: URLRequest = .mockAny()
        let mockResponse: URLResponse = .mockAny()
        let mockData: Data = .mockRandom()
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()

        let handler = createHandler { request, response, data, error in
            XCTAssertEqual(request, mockRequest)
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
        let mockRequest: URLRequest = .mockAny()
        let mockError = ErrorMock()
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()

        let handler = createHandler { request, response, data, error in
            XCTAssertEqual(request, mockRequest)
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
}
