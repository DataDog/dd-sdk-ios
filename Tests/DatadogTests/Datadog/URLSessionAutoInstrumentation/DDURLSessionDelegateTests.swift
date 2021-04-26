/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DDURLSessionDelegateTests: XCTestCase {
    private let interceptor = URLSessionInterceptorMock()
    private lazy var delegate: DDURLSessionDelegate = {
        let delegate = DDURLSessionDelegate()
        delegate.interceptor = interceptor
        return delegate
    }()

    // MARK: - Interception Flow

    func testGivenURLSessionWithDatadogDelegate_whenUsingTaskWithURL_itNotifiesInterceptor() {
        let notifyTaskReceivedData = expectation(description: "Notify task received data")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let notifyTaskMetricsCollected = expectation(description: "Notify task metrics collection")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.onTaskReceivedData = { _, _ in notifyTaskReceivedData.fulfill() }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }
        interceptor.onTaskMetricsCollected = { _, _ in notifyTaskMetricsCollected.fulfill() }

        // Given
        let session = URLSession.createServerMockURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URL.mockAny())
        task.resume()

        // Then
        wait(for: [notifyTaskReceivedData, notifyTaskMetricsCollected, notifyTaskCompleted], timeout: 0.5, enforceOrder: true)
        _ = server.waitAndReturnRequests(count: 1)
    }

    func testGivenURLSessionWithDatadogDelegate_whenUsingTaskWithURLRequest_itNotifiesInterceptor() {
        let notifyTaskReceivedData = expectation(description: "Notify task received data")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let notifyTaskMetricsCollected = expectation(description: "Notify task metrics collection")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.onTaskReceivedData = { _, _ in notifyTaskReceivedData.fulfill() }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }
        interceptor.onTaskMetricsCollected = { _, _ in notifyTaskMetricsCollected.fulfill() }

        // Given
        let session = URLSession.createServerMockURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URLRequest.mockAny())
        task.resume()

        // Then
        wait(for: [notifyTaskReceivedData, notifyTaskMetricsCollected, notifyTaskCompleted], timeout: 0.5, enforceOrder: true)
        _ = server.waitAndReturnRequests(count: 1)
    }

    // MARK: - Interception Values

    func testGivenURLSessionWithDatadogDelegate_whenTaskCompletesWithFailure_itPassessAllValuesToTheInterceptor() throws {
        let noTaskShouldReceiveData = expectation(description: "None of tasks should recieve data")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let notifyTaskMetricsCollected = expectation(description: "Notify task metrics collection")
        noTaskShouldReceiveData.isInverted = true
        notifyTaskCompleted.expectedFulfillmentCount = 2
        notifyTaskMetricsCollected.expectedFulfillmentCount = 2

        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let server = ServerMock(delivery: .failure(error: expectedError))

        interceptor.onTaskReceivedData = { _, _ in noTaskShouldReceiveData.fulfill() }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }
        interceptor.onTaskMetricsCollected = { _, _ in notifyTaskMetricsCollected.fulfill() }

        let dateBeforeAnyRequests = Date()

        // Given
        let session = URLSession.createServerMockURLSession(delegate: delegate)

        // When
        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.resume()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)

        let dateAfterAllRequests = Date()
        XCTAssertTrue(interceptor.taskMetrics[0].task === taskWithURL)
        XCTAssertGreaterThan(interceptor.taskMetrics[0].metrics.taskInterval.start, dateBeforeAnyRequests)
        XCTAssertLessThan(interceptor.taskMetrics[0].metrics.taskInterval.end, dateAfterAllRequests)
        XCTAssertTrue(interceptor.tasksCompleted[0].task === taskWithURL)
        XCTAssertEqual((interceptor.tasksCompleted[0].error! as NSError).localizedDescription, "some error")

        XCTAssertTrue(interceptor.taskMetrics[1].task === taskWithURLRequest)
        XCTAssertGreaterThan(interceptor.taskMetrics[1].metrics.taskInterval.start, dateBeforeAnyRequests)
        XCTAssertLessThan(interceptor.taskMetrics[1].metrics.taskInterval.end, dateAfterAllRequests)
        XCTAssertTrue(interceptor.tasksCompleted[1].task === taskWithURLRequest)
        XCTAssertEqual((interceptor.tasksCompleted[1].error! as NSError).localizedDescription, "some error")

        XCTAssertEqual(interceptor.tasksReceivedData.count, 0, "When tasks complete with failure, they should not receive data")
    }

    func testGivenURLSessionWithDatadogDelegate_whenTaskCompletesWithSuccess_itPassessAllValuesToTheInterceptor() throws {
        let notifyTaskReceivedData = expectation(description: "Notify 2 tasks received data")
        let notifyTaskCompleted = expectation(description: "Notify 2 tasks completion")
        let notifyTaskMetricsCollected = expectation(description: "Notify 2 tasks metrics collection")
        notifyTaskReceivedData.expectedFulfillmentCount = 2
        notifyTaskCompleted.expectedFulfillmentCount = 2
        notifyTaskMetricsCollected.expectedFulfillmentCount = 2

        let randomData: Data = .mockRandom()
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: randomData))

        interceptor.onTaskReceivedData = { _, _ in notifyTaskReceivedData.fulfill() }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }
        interceptor.onTaskMetricsCollected = { _, _ in notifyTaskMetricsCollected.fulfill() }

        let dateBeforeAnyRequests = Date()

        // Given
        let session = URLSession.createServerMockURLSession(delegate: delegate)

        // When
        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.resume()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)

        let dateAfterAllRequests = Date()
        XCTAssertTrue(interceptor.taskMetrics[0].task === taskWithURL)
        XCTAssertGreaterThan(interceptor.taskMetrics[0].metrics.taskInterval.start, dateBeforeAnyRequests)
        XCTAssertLessThan(interceptor.taskMetrics[0].metrics.taskInterval.end, dateAfterAllRequests)
        XCTAssertTrue(interceptor.tasksCompleted[0].task === taskWithURL)
        XCTAssertNil(interceptor.tasksCompleted[0].error)
        XCTAssertTrue(interceptor.tasksReceivedData[0].task === taskWithURL)
        XCTAssertEqual(interceptor.tasksReceivedData[0].data, randomData)

        XCTAssertTrue(interceptor.taskMetrics[1].task === taskWithURLRequest)
        XCTAssertGreaterThan(interceptor.taskMetrics[1].metrics.taskInterval.start, dateBeforeAnyRequests)
        XCTAssertLessThan(interceptor.taskMetrics[1].metrics.taskInterval.end, dateAfterAllRequests)
        XCTAssertTrue(interceptor.tasksCompleted[1].task === taskWithURLRequest)
        XCTAssertNil(interceptor.tasksCompleted[1].error)
        XCTAssertTrue(interceptor.tasksReceivedData[1].task === taskWithURLRequest)
        XCTAssertEqual(interceptor.tasksReceivedData[1].data, randomData)
    }

    // MARK: - Usage errors

    func testGivenAutoInstrumentationInstanceIsNil_whenInitializingDDURLSessionDelegate_itPrintsError() {
        let printFunction = PrintFunctionMock()
        let previousConsolePrint = consolePrint
        consolePrint = printFunction.print
        defer { consolePrint = previousConsolePrint }

        // given
        URLSessionAutoInstrumentation.instance = nil

        // when
        _ = DDURLSessionDelegate()

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: `Datadog.initialize()` must be called before initializing the `DDURLSessionDelegate` and
            first party hosts must be specified in `Datadog.Configuration`: `trackURLSession(firstPartyHosts:)`
            to enable network requests tracking.
            """
        )
    }

    func testGivenAutoInstrumentationInstanceIsNil_whenInitializingDDURLSessionDelegateWithCustomFirstPartyHosts_itPrintsError() {
        let printFunction = PrintFunctionMock()
        let previousConsolePrint = consolePrint
        consolePrint = printFunction.print
        defer { consolePrint = previousConsolePrint }

        // given
        URLSessionAutoInstrumentation.instance = nil

        // when
        _ = DDURLSessionDelegate(additionalFirstPartyHosts: ["foo.com"])

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: `Datadog.initialize()` must be called before initializing the `DDURLSessionDelegate` and
            first party hosts must be specified in `Datadog.Configuration`: `trackURLSession(firstPartyHosts:)`
            to enable network requests tracking.
            """
        )
    }

    func testWhenDDURLSessionDelegateInits_itPicksCorrectInterceptor() {
        // given
        URLSessionAutoInstrumentation.instance = URLSessionAutoInstrumentation(
            configuration: .mockAny(),
            dateProvider: SystemDateProvider(),
            appStateListener: AppStateListener.mockAny()
        )
        defer { URLSessionAutoInstrumentation.instance = nil }

        // when
        let testDelegate = DDURLSessionDelegate()

        // then
        XCTAssert(
            testDelegate.interceptor === URLSessionAutoInstrumentation.instance?.interceptor,
            "\(String(describing: testDelegate.interceptor)) must be identical to \(String(describing: URLSessionAutoInstrumentation.instance?.interceptor))"
        )
    }

    func testWhenDDURLSessionDelegateInitsWithCustomFirstPartyHosts_itPicksCorrectInterceptor() {
        // given
        URLSessionAutoInstrumentation.instance = URLSessionAutoInstrumentation(
            configuration: .mockAny(),
            dateProvider: SystemDateProvider(),
            appStateListener: AppStateListener.mockAny()
        )
        defer { URLSessionAutoInstrumentation.instance = nil }

        // when
        let testDelegate = DDURLSessionDelegate(additionalFirstPartyHosts: ["foo.com"])

        // then
        XCTAssert(
            testDelegate.interceptor === URLSessionAutoInstrumentation.instance?.interceptor,
            "\(String(describing: testDelegate.interceptor)) must be identical to \(String(describing: URLSessionAutoInstrumentation.instance?.interceptor))"
        )
    }
}
