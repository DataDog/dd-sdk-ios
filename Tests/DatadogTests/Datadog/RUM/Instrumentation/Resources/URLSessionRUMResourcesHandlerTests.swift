/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class URLSessionRUMResourcesHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let traceSamplingRate: Double = .mockRandom(min: 0, max: 1)
    private let commandSubscriber = RUMCommandSubscriberMock()

    private func createHandler(rumAttributesProvider: URLSessionRUMAttributesProvider? = nil) -> URLSessionRUMResourcesHandler {
        let handler = URLSessionRUMResourcesHandler(
            dateProvider: dateProvider,
            tracingSampler: Sampler(samplingRate: Float(traceSamplingRate * 100)),
            rumAttributesProvider: rumAttributesProvider
        )
        handler.publish(to: commandSubscriber)
        return handler
    }
    private lazy var handler = createHandler(rumAttributesProvider: nil)

    func testGivenTaskInterceptionWithNoSpanContext_whenInterceptionStarts_itStartsRUMResource() throws {
        let receiveCommand = expectation(description: "Receive RUM command")
        commandSubscriber.onCommandReceived = { _ in receiveCommand.fulfill() }

        // Given
        var request = URLRequest(url: .mockRandom())
        request.httpMethod = ["GET", "POST", "PUT", "DELETE"].randomElement()!
        let taskInterception = TaskInterception(request: request, isFirstParty: .random())
        XCTAssertNil(taskInterception.spanContext)

        // When
        handler.notify_taskInterceptionStarted(interception: taskInterception)

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
        let taskInterception = TaskInterception(request: .mockAny(), isFirstParty: .random())
        taskInterception.register(spanContext: .mockWith(traceID: 1, spanID: 2))
        XCTAssertNotNil(taskInterception.spanContext)

        // When
        handler.notify_taskInterceptionStarted(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let resourceStartCommand = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMStartResourceCommand)
        let spanContext = try XCTUnwrap(resourceStartCommand.spanContext)
        XCTAssertEqual(spanContext.traceID, "1")
        XCTAssertEqual(spanContext.spanID, "2")
        XCTAssertEqual(spanContext.samplingRate, traceSamplingRate, accuracy: 0.01)
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
        let taskInterception = TaskInterception(request: .mockAny(), isFirstParty: .random())
        let resourceMetrics: ResourceMetrics = .mockAny()
        let resourceCompletion: ResourceCompletion = .mockWith(response: .mockResponseWith(statusCode: 200), error: nil)
        taskInterception.register(metrics: resourceMetrics)
        taskInterception.register(completion: resourceCompletion)

        // When
        handler.notify_taskInterceptionCompleted(interception: taskInterception)

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
        XCTAssertEqual(resourceStopCommand.kind, RUMResourceType(response: resourceCompletion.httpResponse!))
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
        let taskInterception = TaskInterception(request: .mockAny(), isFirstParty: .random())
        let taskError = NSError(domain: "domain", code: 123, userInfo: [NSLocalizedDescriptionKey: "network error"])
        let resourceMetrics: ResourceMetrics = .mockAny()
        let resourceCompletion: ResourceCompletion = .mockWith(response: nil, error: taskError)
        taskInterception.register(metrics: resourceMetrics)
        taskInterception.register(completion: resourceCompletion)

        // When
        handler.notify_taskInterceptionCompleted(interception: taskInterception)

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
        let taskInterception = TaskInterception(request: mockRequest, isFirstParty: .random())
        taskInterception.register(nextData: mockData)
        taskInterception.register(metrics: .mockAny())
        taskInterception.register(completion: .mockWith(response: mockResponse, error: nil))
        handler.notify_taskInterceptionCompleted(interception: taskInterception)

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
        let taskInterception = TaskInterception(request: mockRequest, isFirstParty: .random())
        taskInterception.register(metrics: .mockAny())
        taskInterception.register(completion: .mockWith(response: nil, error: mockError))
        handler.notify_taskInterceptionCompleted(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        DDAssertDictionariesEqual(stopResourceWithErrorCommand!.attributes, mockAttributes)
    }
}
