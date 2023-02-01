/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLSessionSwizzlerTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private let interceptor = URLSessionInterceptorMock()

    override func setUpWithError() throws {
        super.setUp()
        let instrumentation = URLSessionAutoInstrumentation(
            swizzler: try URLSessionSwizzler(),
            interceptor: interceptor
        )

        instrumentation.enable() // swizzle `URLSession`

        core = DatadogCoreProxy()
        core.register(feature: instrumentation)
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    // MARK: - Interception Flow

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURLRequestAndCompletion_itNotifiesCreationAndCompletionAndModifiesTheRequest() throws {
        let requestModified = expectation(description: "Modify request")
        let notifyTaskCreated = expectation(description: "Notify task creation")
        let notifyTaskReceivedData = expectation(description: "Notify task received data")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let completionHandlerCalled = expectation(description: "Call completion handler")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onRequestModified = { _, session in
            XCTAssertNotNil(session)
            requestModified.fulfill()
        }
        interceptor.onTaskCreated = { _, session in
            XCTAssertNotNil(session)
            notifyTaskCreated.fulfill()
        }
        interceptor.onTaskReceivedData = { _, session in
            XCTAssertNotNil(session)
            notifyTaskReceivedData.fulfill()
        }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let delegate = DDURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URLRequest(url: .mockRandom())) { _, _, _ in
            completionHandlerCalled.fulfill()
        }
        task.resume()

        // Then
        wait(for: [requestModified, notifyTaskCreated, notifyTaskReceivedData, notifyTaskCompleted, completionHandlerCalled], timeout: 2, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(requestSent, interceptor.modifiedRequest, "The request should be modified")
    }

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURLAndCompletion_itNotifiesTaskCreationAndCompletionAndModifiesTheRequestOnlyPriorToIOS13() throws {
        let requestModified = expectation(description: "Modify request")
        if #available(iOS 13.0, *) {
            requestModified.isInverted = true
        }
        let notifyTaskCreated = expectation(description: "Notify task creation")
        let notifyTaskReceivedData = expectation(description: "Notify task received data")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let completionHandlerCalled = expectation(description: "Call completion handler")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onRequestModified = { _, session in
            XCTAssertNotNil(session)
            requestModified.fulfill()
        }
        interceptor.onTaskCreated = { _, session in
            XCTAssertNotNil(session)
            notifyTaskCreated.fulfill()
        }
        interceptor.onTaskReceivedData = { _, session in
            XCTAssertNotNil(session)
            notifyTaskReceivedData.fulfill()
        }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let delegate = DDURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URL.mockRandom()) { _, _, _ in
            completionHandlerCalled.fulfill()
        }
        task.resume()

        // Then
        wait(for: [requestModified, notifyTaskCreated, notifyTaskReceivedData, notifyTaskCompleted, completionHandlerCalled], timeout: 2, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        if #available(iOS 13.0, *) {
            XCTAssertNotEqual(requestSent, interceptor.modifiedRequest, "The request should not be modified on iOS 13.0 and above.")
        } else {
            XCTAssertEqual(requestSent, interceptor.modifiedRequest, "The request should be modified prior to iOS 13.0.")
        }
    }

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURLRequest_itNotifiesCreationAndCompletionAndModifiesTheRequest() throws {
        let requestModified = expectation(description: "Modify request")
        let notifyTaskCreated = expectation(description: "Notify task creation")
        let notifyTaskReceivedData = expectation(description: "Notify task received data")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onRequestModified = { _, session in
            XCTAssertNotNil(session)
            requestModified.fulfill()
        }
        interceptor.onTaskCreated = { _, session in
            XCTAssertNotNil(session)
            notifyTaskCreated.fulfill()
        }
        interceptor.onTaskReceivedData = { _, session in
            XCTAssertNotNil(session)
            notifyTaskReceivedData.fulfill()
        }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let delegate = DDURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URLRequest(url: .mockAny()))
        task.resume()

        // Then
        wait(for: [requestModified, notifyTaskCreated, notifyTaskReceivedData, notifyTaskCompleted], timeout: 2, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(requestSent, interceptor.modifiedRequest, "The request should be modified.")
    }

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURL_itNotifiesCreationAndCompletionAndDoesNotModifyTheRequest() throws {
        let requestNotModified = expectation(description: "Do not modify request")
        requestNotModified.isInverted = true
        let notifyTaskCreated = expectation(description: "Notify task creation")
        let notifyTaskReceivedData = expectation(description: "Notify task received data")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onRequestModified = { _, _ in requestNotModified.fulfill() }
        interceptor.onTaskCreated = { _, session in
            XCTAssertNotNil(session)
            notifyTaskCreated.fulfill()
        }
        interceptor.onTaskReceivedData = { _, session in
            XCTAssertNotNil(session)
            notifyTaskReceivedData.fulfill()
        }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let delegate = DDURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URL.mockRandom())
        task.resume()

        // Then
        wait(for: [requestNotModified, notifyTaskCreated, notifyTaskReceivedData, notifyTaskCompleted], timeout: 2, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertNotEqual(requestSent, interceptor.modifiedRequest, "The request should not be modified.")
    }

    func testGivenNSURLSession_whenNillifyingCompletionHandler_itNotifiesCreationAndCompletion() throws {
        let notifyTaskCreated = expectation(description: "Notify 2 tasks creation")
        notifyTaskCreated.expectedFulfillmentCount = 2
        let notifyTaskCompleted = expectation(description: "Notify 2 tasks completion")
        notifyTaskCompleted.expectedFulfillmentCount = 2
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onTaskCreated = { _, session in
            XCTAssertNotNil(session)
            notifyTaskCreated.fulfill()
        }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let delegate = DDURLSessionDelegate(in: core)
        let nsSession = NSURLSessionBridge(server.getInterceptedURLSession(delegate: delegate))!

        // When
        let task1 = nsSession.dataTask(with: URL.mockRandom(), completionHandler: nil)!
        task1.resume()

        let task2 = nsSession.dataTask(with: URLRequest.mockAny(), completionHandler: nil)!
        task2.resume()

        // Then
        wait(for: [notifyTaskCreated, notifyTaskCompleted], timeout: 2, enforceOrder: false)

        _ = server.waitAndReturnRequests(count: 2)
    }

    func testGivenNonInterceptedSession_itDoesntCallInterceptor() throws {
        let doNotModifyRequest = expectation(description: "Do not notify request modification")
        doNotModifyRequest.isInverted = true
        interceptor.onRequestModified = { _, _ in doNotModifyRequest.fulfill() }
        let doNotNotifyTaskCreated = expectation(description: "Do not notify task creation")
        doNotNotifyTaskCreated.isInverted = true
        interceptor.onTaskCreated = { _, _ in doNotNotifyTaskCreated.fulfill() }

        // Given
        let session = URLSession(configuration: .default)

        // When
        let taskWithURL = session.dataTask(with: URL.mockAny())
        let taskWithURLRequest = session.dataTask(with: URLRequest.mockAny())
        let taskWithURLWithCompletion = session.dataTask(with: URL.mockAny()) { _, _, _ in }
        let taskWithURLRequestWithCompletion = session.dataTask(with: URLRequest.mockAny()) { _, _, _ in }

        // Then
        waitForExpectations(timeout: 2, handler: nil)
        XCTAssertNotNil(taskWithURL)
        XCTAssertNotNil(taskWithURLRequest)
        XCTAssertNotNil(taskWithURLWithCompletion)
        XCTAssertNotNil(taskWithURLRequestWithCompletion)
    }

    // MARK: - Interception Values

    func testGivenSuccessfulTask_whenUsingSwizzledAPIs_itPassesAllValuesToTheInterceptor() throws {
        let completionHandlersCalled = expectation(description: "Call 2 completion handlers")
        completionHandlersCalled.expectedFulfillmentCount = 2
        let notifyTaskReceivedData = expectation(description: "Notify 4 tasks received data")
        notifyTaskReceivedData.expectedFulfillmentCount = 4
        let notifyTaskCompleted = expectation(description: "Notify 4 tasks completion")
        notifyTaskCompleted.expectedFulfillmentCount = 4

        interceptor.onTaskReceivedData = { _, _ in notifyTaskReceivedData.fulfill() }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let expectedResponse: HTTPURLResponse = .mockResponseWith(statusCode: 200)
        let expectedData: Data = .mockRandom()
        let server = ServerMock(delivery: .success(response: expectedResponse, data: expectedData))
        let delegate = DDURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let taskWithURLRequestAndCompletion = session.dataTask(with: URLRequest(url: .mockAny())) { data, response, error in
            XCTAssertEqual(data, expectedData)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, expectedResponse.statusCode)
            XCTAssertNil(error)
            completionHandlersCalled.fulfill()
        }
        taskWithURLRequestAndCompletion.taskDescription = "taskWithURLRequestAndCompletion"
        taskWithURLRequestAndCompletion.resume()

        let taskWithURLAndCompletion = session.dataTask(with: URL.mockAny()) { data, response, error in
            XCTAssertEqual(data, expectedData)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, expectedResponse.statusCode)
            XCTAssertNil(error)
            completionHandlersCalled.fulfill()
        }
        taskWithURLAndCompletion.taskDescription = "taskWithURLAndCompletion"
        taskWithURLAndCompletion.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.taskDescription = "taskWithURLRequest"
        taskWithURLRequest.resume()

        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.taskDescription = "taskWithURL"
        taskWithURL.resume()

        // Then
        waitForExpectations(timeout: 2, handler: nil)

        _ = server.waitAndReturnRequests(count: 4)
        XCTAssertEqual(interceptor.tasksCreated.count, 4, "Interceptor should record creation of 4 tasks")
        XCTAssertEqual(interceptor.tasksReceivedData.count, 4, "Interceptor should record data for all 4 tasks")
        XCTAssertEqual(interceptor.tasksCompleted.count, 4, "Interceptor should record completion of 4 tasks")

        let originalTasks = [taskWithURLRequestAndCompletion, taskWithURLAndCompletion, taskWithURLRequest, taskWithURL]
        try originalTasks.forEach { originalTask in
            let taskDescription = originalTask.taskDescription!

            let interceptedTask = try interceptor.interceptedTask(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTask, originalTask)

            let interceptedTaskWithData = try interceptor.interceptedTaskWithData(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTaskWithData.task, originalTask)
            XCTAssertEqual(interceptedTaskWithData.data, expectedData)

            let interceptedTaskWithCompletion = try interceptor.interceptedTaskWithCompletion(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTaskWithCompletion.task, originalTask)
            XCTAssertNil(interceptedTaskWithCompletion.error)
        }
    }

    func testGivenFailedTask_whenUsingSwizzledAPIs_itPassesAllValuesToTheInterceptor() throws {
        let completionHandlersCalled = expectation(description: "Call 2 completion handlers")
        completionHandlersCalled.expectedFulfillmentCount = 2
        let noTaskShouldReceiveData = expectation(description: "None of tasks should recieve data")
        noTaskShouldReceiveData.isInverted = true
        let notifyTaskCompleted = expectation(description: "Notify 4 tasks completion")
        notifyTaskCompleted.expectedFulfillmentCount = 4

        interceptor.onTaskReceivedData = { _, _ in noTaskShouldReceiveData.fulfill() }
        interceptor.onTaskCompleted = { _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let server = ServerMock(delivery: .failure(error: expectedError))
        let delegate = DDURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let taskWithURLRequestAndCompletion = session.dataTask(with: URLRequest(url: .mockAny())) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error! as NSError).localizedDescription, "some error")
            completionHandlersCalled.fulfill()
        }
        taskWithURLRequestAndCompletion.taskDescription = "taskWithURLRequestAndCompletion"
        taskWithURLRequestAndCompletion.resume()

        let taskWithURLAndCompletion = session.dataTask(with: URL.mockAny()) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error! as NSError).localizedDescription, "some error")
            completionHandlersCalled.fulfill()
        }
        taskWithURLAndCompletion.taskDescription = "taskWithURLAndCompletion"
        taskWithURLAndCompletion.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.taskDescription = "taskWithURLRequest"
        taskWithURLRequest.resume()

        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.taskDescription = "taskWithURL"
        taskWithURL.resume()

        // Then
        waitForExpectations(timeout: 2, handler: nil)

        _ = server.waitAndReturnRequests(count: 4)
        XCTAssertEqual(interceptor.tasksCreated.count, 4, "Interceptor should record creation of 4 tasks")
        XCTAssertEqual(interceptor.tasksReceivedData.count, 0, "Interceptor should no record data for any task")
        XCTAssertEqual(interceptor.tasksCompleted.count, 4, "Interceptor should record completion of 4 tasks")

        let originalTasks = [taskWithURLRequestAndCompletion, taskWithURLAndCompletion, taskWithURLRequest, taskWithURL]
        try originalTasks.forEach { originalTask in
            let taskDescription = originalTask.taskDescription!

            let interceptedTask = try interceptor.interceptedTask(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTask, originalTask)

            let interceptedTaskWithData = interceptor.interceptedTaskWithData(by: taskDescription)
            XCTAssertNil(interceptedTaskWithData, "Data should not be recorded for \(originalTask) (\(taskDescription)")

            let interceptedTaskWithCompletion = try interceptor.interceptedTaskWithCompletion(by: taskDescription).unwrapOrThrow()
            XCTAssertIdentical(interceptedTaskWithCompletion.task, originalTask)
            XCTAssertEqual((interceptedTaskWithCompletion.error! as NSError).localizedDescription, "some error")
        }
    }
}
