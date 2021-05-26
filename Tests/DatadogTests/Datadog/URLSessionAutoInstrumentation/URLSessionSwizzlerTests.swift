/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension URLSessionSwizzler {
    func unswizzle() {
        dataTaskWithURLRequestAndCompletion.unswizzle()
        dataTaskWithURLRequest.unswizzle()
        dataTaskWithURLAndCompletion?.unswizzle()
        dataTaskWithURL?.unswizzle()
    }
}

extension URLSessionAutoInstrumentation {
    func disable() {
        swizzler.unswizzle()
    }
}

class URLSessionSwizzlerTests: XCTestCase {
    private let interceptor = URLSessionInterceptorMock()

    override func setUpWithError() throws {
        super.setUp()
        URLSessionAutoInstrumentation.instance = .init(
            swizzler: try URLSessionSwizzler(),
            interceptor: interceptor
        )
        URLSessionAutoInstrumentation.instance?.enable() // swizzle `URLSession`
    }

    override func tearDown() {
        URLSessionAutoInstrumentation.instance?.disable() // unswizzle `URLSession`
        URLSessionAutoInstrumentation.instance?.deinitialize()
        super.tearDown()
    }

    private func interceptedSession() -> URLSession {
        return .createServerMockURLSession(delegate: DDURLSessionDelegate())
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
        let session = interceptedSession()

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
        let session = interceptedSession()

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
        let session = interceptedSession()

        // When
        let task = session.dataTask(with: URLRequest(url: .mockAny()))
        task.resume()

        // Then
        wait(for: [requestModified, notifyTaskCreated, notifyTaskReceivedData, notifyTaskCompleted], timeout: 2, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(requestSent, interceptor.modifiedRequest, "The request should be modified.")
    }

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURL_itNotifiesCreationAndCompletionAndDoesNotModifiyTheRequest() throws {
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
        let session = interceptedSession()

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
        let nsSession = NSURLSessionBridge(interceptedSession())!

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

    func testGivenSuccessfulTask_whenUsingSwizzledAPIs_itPassessAllValuesToTheInterceptor() {
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
        let session = interceptedSession()

        // When
        let taskWithURLRequestAndCompletion = session.dataTask(with: URLRequest(url: .mockAny())) { data, response, error in
            XCTAssertEqual(data, expectedData)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, expectedResponse.statusCode)
            XCTAssertNil(error)
            completionHandlersCalled.fulfill()
        }
        taskWithURLRequestAndCompletion.resume()

        let taskWithURLAndCompletion = session.dataTask(with: URL.mockAny()) { data, response, error in
            XCTAssertEqual(data, expectedData)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, expectedResponse.statusCode)
            XCTAssertNil(error)
            completionHandlersCalled.fulfill()
        }
        taskWithURLAndCompletion.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.resume()

        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.resume()

        // Then
        waitForExpectations(timeout: 2, handler: nil)

        _ = server.waitAndReturnRequests(count: 4)
        XCTAssertEqual(interceptor.tasksCreated.count, 4, "Interceptor should record all 4 tasks created.")
        XCTAssertEqual(interceptor.tasksCompleted.count, 4, "Interceptor should record all 4 tasks completed.")

        XCTAssertTrue(interceptor.tasksCreated[0] === taskWithURLRequestAndCompletion)
        XCTAssertTrue(interceptor.tasksCompleted[0].task === taskWithURLRequestAndCompletion)
        XCTAssertNil(interceptor.tasksCompleted[0].error)
        XCTAssertEqual(interceptor.tasksReceivedData[0].data, expectedData)

        XCTAssertTrue(interceptor.tasksCreated[1] === taskWithURLAndCompletion)
        XCTAssertTrue(interceptor.tasksCompleted[1].task === taskWithURLAndCompletion)
        XCTAssertNil(interceptor.tasksCompleted[1].error)
        XCTAssertEqual(interceptor.tasksReceivedData[1].data, expectedData)

        XCTAssertTrue(interceptor.tasksCreated[2] === taskWithURLRequest)
        XCTAssertTrue(interceptor.tasksCompleted[2].task === taskWithURLRequest)
        XCTAssertNil(interceptor.tasksCompleted[2].error)
        XCTAssertEqual(interceptor.tasksReceivedData[2].data, expectedData)

        XCTAssertTrue(interceptor.tasksCreated[3] === taskWithURL)
        XCTAssertTrue(interceptor.tasksCompleted[3].task === taskWithURL)
        XCTAssertNil(interceptor.tasksCompleted[3].error)
        XCTAssertEqual(interceptor.tasksReceivedData[3].data, expectedData)
    }

    func testGivenFailedTask_whenUsingSwizzledAPIs_itPassessAllValuesToTheInterceptor() {
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
        let session = interceptedSession()

        // When
        let taskWithURLRequestAndCompletion = session.dataTask(with: URLRequest(url: .mockAny())) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error! as NSError).localizedDescription, "some error")
            completionHandlersCalled.fulfill()
        }
        taskWithURLRequestAndCompletion.resume()

        let taskWithURLAndCompletion = session.dataTask(with: URL.mockAny()) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error! as NSError).localizedDescription, "some error")
            completionHandlersCalled.fulfill()
        }
        taskWithURLAndCompletion.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.resume()

        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.resume()

        // Then
        waitForExpectations(timeout: 2, handler: nil)

        _ = server.waitAndReturnRequests(count: 4)
        XCTAssertEqual(interceptor.tasksCreated.count, 4, "Interceptor should record all 4 tasks created.")
        XCTAssertEqual(interceptor.tasksCompleted.count, 4, "Interceptor should record all 4 tasks completed.")

        XCTAssertTrue(interceptor.tasksCreated[0] === taskWithURLRequestAndCompletion)
        XCTAssertTrue(interceptor.tasksCompleted[0].task === taskWithURLRequestAndCompletion)
        XCTAssertEqual((interceptor.tasksCompleted[0].error! as NSError).localizedDescription, "some error")

        XCTAssertTrue(interceptor.tasksCreated[1] === taskWithURLAndCompletion)
        XCTAssertTrue(interceptor.tasksCompleted[1].task === taskWithURLAndCompletion)
        XCTAssertEqual((interceptor.tasksCompleted[1].error! as NSError).localizedDescription, "some error")

        XCTAssertTrue(interceptor.tasksCreated[2] === taskWithURLRequest)
        XCTAssertTrue(interceptor.tasksCompleted[2].task === taskWithURLRequest)
        XCTAssertEqual((interceptor.tasksCompleted[2].error! as NSError).localizedDescription, "some error")

        XCTAssertTrue(interceptor.tasksCreated[3] === taskWithURL)
        XCTAssertTrue(interceptor.tasksCompleted[3].task === taskWithURL)
        XCTAssertEqual((interceptor.tasksCompleted[3].error! as NSError).localizedDescription, "some error")

        XCTAssertEqual(interceptor.tasksReceivedData.count, 0, "When tasks complete with failure, they should not receive data")
    }
}
