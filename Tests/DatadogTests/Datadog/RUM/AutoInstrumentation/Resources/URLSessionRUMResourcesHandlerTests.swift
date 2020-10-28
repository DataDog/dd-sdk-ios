/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension ResourceMetrics: EquatableInTests {}

class URLSessionRUMResourcesHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()

    private lazy var handler: URLSessionRUMResourcesHandler = {
        let handler = URLSessionRUMResourcesHandler(dateProvider: dateProvider)
        handler.subscribe(commandsSubscriber: commandSubscriber)
        return handler
    }()

    func testGivenTaskInterceptionWithNoSpanContext_whenInterceptionStarts_itStartsRUMResource() throws {
        let receiveCommand = expectation(description: "Receive RUM command")
        commandSubscriber.onCommandReceived = { _ in receiveCommand.fulfill() }

        // Given
        var request = URLRequest(url: .mockRandom())
        request.httpMethod = ["GET", "POST", "PUT", "DELETE"].randomElement()!
        let taskInterception = TaskInterception(request: request)
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
        XCTAssertEqual(resourceStartCommand.httpMethod, RUMHTTPMethod(request: request))
        XCTAssertNil(resourceStartCommand.spanContext)
    }

    func testGivenTaskInterceptionWithSpanContext_whenInterceptionStarts_itStartsRUMResource() throws {
        let receiveCommand = expectation(description: "Receive RUM command")
        commandSubscriber.onCommandReceived = { _ in receiveCommand.fulfill() }

        // Given
        let taskInterception = TaskInterception(request: .mockAny())
        taskInterception.register(spanContext: .mockWith(traceID: 1, spanID: 2))
        XCTAssertNotNil(taskInterception.spanContext)

        // When
        handler.notify_taskInterceptionStarted(interception: taskInterception)

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        let resourceStartCommand = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMStartResourceCommand)
        XCTAssertEqual(resourceStartCommand.spanContext?.traceID, "1")
        XCTAssertEqual(resourceStartCommand.spanContext?.spanID, "2")
    }

    func testGivenTaskInterceptionWithMetricsAndCompletion_whenInterceptionCompletes_itStopsRUMResourceWithMetrics() throws {
        let receiveCommands = expectation(description: "Receive 2 RUM commands")
        receiveCommands.expectedFulfillmentCount = 2
        var commandsReceived: [RUMCommand] = []
        commandSubscriber.onCommandReceived = { command in
            commandsReceived.append(command)
            receiveCommands.fulfill()
        }

        // Given
        let taskInterception = TaskInterception(request: .mockAny())
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
        XCTAssertEqual(resourceMetricsCommand.metrics, taskInterception.metrics)

        let resourceStopCommand = try XCTUnwrap(commandsReceived[1] as? RUMStopResourceCommand)
        XCTAssertEqual(resourceStopCommand.resourceKey, taskInterception.identifier.uuidString)
        XCTAssertEqual(resourceStopCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceStopCommand.attributes.count, 0)
        XCTAssertEqual(resourceStopCommand.kind, RUMResourceKind(request: taskInterception.request, response: resourceCompletion.httpResponse!))
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
        let taskInterception = TaskInterception(request: .mockAny())
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
        XCTAssertEqual(resourceMetricsCommand.metrics, taskInterception.metrics)

        let resourceStopCommand = try XCTUnwrap(commandsReceived[1] as? RUMStopResourceWithErrorCommand)
        XCTAssertEqual(resourceStopCommand.resourceKey, taskInterception.identifier.uuidString)
        XCTAssertEqual(resourceStopCommand.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(resourceStopCommand.attributes.count, 0)
        XCTAssertEqual(resourceStopCommand.errorMessage, DDError(error: taskError).title)
        XCTAssertEqual(resourceStopCommand.errorSource, .network)
        XCTAssertEqual(resourceStopCommand.stack, DDError(error: taskError).details)
        XCTAssertNil(resourceStopCommand.httpStatusCode)
    }
}
