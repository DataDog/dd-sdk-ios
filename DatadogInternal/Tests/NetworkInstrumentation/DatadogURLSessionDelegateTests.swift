/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class DatadogURLSessionDelegateTests: XCTestCase {
    private var core: SingleFeatureCoreMock<NetworkInstrumentationFeature>! // swiftlint:disable:this implicitly_unwrapped_optional
    private let interceptor = URLSessionInterceptorMock()

    override func setUpWithError() throws {
        super.setUp()

        core = SingleFeatureCoreMock()
        try core.register(urlSessionInterceptor: interceptor)
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

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
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

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
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URLRequest.mockAny())
        task.resume()

        // Then
        wait(for: [notifyTaskReceivedData, notifyTaskMetricsCollected, notifyTaskCompleted], timeout: 0.5, enforceOrder: true)
        _ = server.waitAndReturnRequests(count: 1)
    }

    // MARK: - Interception Values

    func testGivenURLSessionWithDatadogDelegate_whenTaskCompletesWithFailure_itPassesAllValuesToTheInterceptor() throws {
        let noTaskShouldReceiveData = expectation(description: "None of tasks should receive data")
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
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.taskDescription = "taskWithURL"
        taskWithURL.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.taskDescription = "taskWithURLRequest"
        taskWithURLRequest.resume()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)

        let dateAfterAllRequests = Date()

        XCTAssertEqual(interceptor.taskMetrics.count, 2, "Interceptor should record metrics for 2 tasks")
        XCTAssertEqual(interceptor.tasksReceivedData.count, 0, "Interceptor should not record data for any task")
        XCTAssertEqual(interceptor.tasksCompleted.count, 2, "Interceptor should record completion for 2 tasks")

        let originalTasks = [taskWithURL, taskWithURLRequest]
        try originalTasks.forEach { originalTask in
            let taskDescription = originalTask.taskDescription!

            let interceptedTaskWithMetrics = try interceptor.interceptedTaskWithMetrics(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTaskWithMetrics.task, originalTask)
            XCTAssertGreaterThan(interceptedTaskWithMetrics.metrics.taskInterval.start, dateBeforeAnyRequests)
            XCTAssertLessThan(interceptedTaskWithMetrics.metrics.taskInterval.end, dateAfterAllRequests)

            let interceptedTaskWithData = interceptor.interceptedTaskWithData(by: taskDescription)
            XCTAssertNil(interceptedTaskWithData, "Data should not be recorded for \(originalTask) (\(taskDescription)")

            let interceptedTaskWithCompletion = try interceptor.interceptedTaskWithCompletion(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTaskWithCompletion.task, originalTask)
            XCTAssertEqual((interceptedTaskWithCompletion.error! as NSError).localizedDescription, "some error")
        }
    }

    func testGivenURLSessionWithDatadogDelegate_whenTaskCompletesWithSuccess_itPassesAllValuesToTheInterceptor() throws {
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
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.taskDescription = "taskWithURL"
        taskWithURL.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.taskDescription = "taskWithURLRequest"
        taskWithURLRequest.resume()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)

        let dateAfterAllRequests = Date()

        XCTAssertEqual(interceptor.taskMetrics.count, 2, "Interceptor should record metrics for 2 tasks.")
        XCTAssertEqual(interceptor.tasksReceivedData.count, 2, "Interceptor should record data for 2 tasks")
        XCTAssertEqual(interceptor.tasksCompleted.count, 2, "Interceptor should record completion for 2 tasks")

        let originalTasks = [taskWithURL, taskWithURLRequest]
        try originalTasks.forEach { originalTask in
            let taskDescription = originalTask.taskDescription!

            let interceptedTaskWithMetrics = try interceptor.interceptedTaskWithMetrics(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTaskWithMetrics.task, originalTask)
            XCTAssertGreaterThan(interceptedTaskWithMetrics.metrics.taskInterval.start, dateBeforeAnyRequests)
            XCTAssertLessThan(interceptedTaskWithMetrics.metrics.taskInterval.end, dateAfterAllRequests)

            let interceptedTaskWithData = try interceptor.interceptedTaskWithData(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTaskWithData.task, originalTask)
            XCTAssertEqual(interceptedTaskWithData.data, randomData)

            let interceptedTaskWithCompletion = try interceptor.interceptedTaskWithCompletion(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTaskWithCompletion.task, originalTask)
            XCTAssertNil(interceptedTaskWithCompletion.error)
        }
    }

    // MARK: - Usage

    func testItCanBeInitializedBeforeInitializingDefaultSDKCore() throws {
        // Given
        let delegate = DatadogURLSessionDelegate()

        // When
        defaultDatadogCore = core
        defer { defaultDatadogCore = NOPDatadogCore() }

        // Then
        XCTAssertNotNil(delegate.interceptor)
    }

    func testItCanBeInitializedAfterInitializingDefaultSDKCore() throws {
        // Given
        defaultDatadogCore = core
        defer { defaultDatadogCore = NOPDatadogCore() }

        // When
        let delegate = DatadogURLSessionDelegate()

        // Then
        XCTAssertNotNil(delegate.interceptor)
    }

    func testItOnlyKeepsInstrumentationWhileSDKCoreIsAvailableInMemory() throws {
        // Given
        var core: DatadogCoreProtocol? = SingleFeatureCoreMock<NetworkInstrumentationFeature>()
        try core?.register(urlSessionInterceptor: interceptor)

        // When
        let delegate = DatadogURLSessionDelegate(in: core)
        // Then
        XCTAssertNotNil(delegate.interceptor)

        // When (deinitialize core)
        core = nil
        // Then
        XCTAssertNil(delegate.interceptor)
    }
}
