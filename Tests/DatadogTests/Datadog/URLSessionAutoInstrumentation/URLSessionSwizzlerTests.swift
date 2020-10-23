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

class URLSessionSwizzlerTests: XCTestCase {
    private let interceptor = URLSessionInterceptorMock()
    private var swizzler: URLSessionSwizzler! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        super.setUp()
        swizzler = try URLSessionSwizzler()
        swizzler.swizzle()
    }

    override func tearDown() {
        swizzler.unswizzle()
        super.tearDown()
    }

    private func interceptedSession() -> URLSession {
        let delegate = DDURLSessionDelegate()
        delegate.interceptor = self.interceptor
        return URLSession.createServerMockURLSession(delegate: delegate)
    }

    // MARK: - Interception Flow

    func testGivenURLSession_whenUsingTaskWithURLRequestAndCompletion_itNotifiesCreationAndCompletionAndModifiesTheRequest() throws {
        let requestModified = expectation(description: "Modify request")
        let notifyTaskCreated = expectation(description: "Notify task creation")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let completionHandlerCalled = expectation(description: "Call completion handler")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onRequestModified = { _ in requestModified.fulfill() }
        interceptor.onTaskCreated = { _, _ in notifyTaskCreated.fulfill() }
        interceptor.onTaskCompleted = { _, _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let session = interceptedSession()

        // When
        let task = session.dataTask(with: URLRequest(url: .mockRandom())) { _, _, _ in
            completionHandlerCalled.fulfill()
        }
        task.resume()

        // Then
        wait(for: [requestModified, notifyTaskCreated, notifyTaskCompleted, completionHandlerCalled], timeout: 0.5, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(requestSent, interceptor.modifiedRequest, "The request should be modified")
    }

    func testGivenURLSession_whenUsingTaskWithURLAndCompletion_itNotifiesTaskCreationAndCompletionAndModifiesTheRequestOnlyPriorToIOS13() throws {
        let requestModified = expectation(description: "Modify request")
        if #available(iOS 13.0, *) {
            requestModified.isInverted = true
        }
        let notifyTaskCreated = expectation(description: "Notify task creation")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let completionHandlerCalled = expectation(description: "Call completion handler")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onRequestModified = { _ in requestModified.fulfill() }
        interceptor.onTaskCreated = { _, _ in notifyTaskCreated.fulfill() }
        interceptor.onTaskCompleted = { _, _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let session = interceptedSession()

        // When
        let task = session.dataTask(with: URL.mockRandom()) { _, _, _ in
            completionHandlerCalled.fulfill()
        }
        task.resume()

        // Then
        wait(for: [requestModified, notifyTaskCreated, notifyTaskCompleted, completionHandlerCalled], timeout: 0.5, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        if #available(iOS 13.0, *) {
            XCTAssertNotEqual(requestSent, interceptor.modifiedRequest, "The request should not be modified on iOS 13.0 and above.")
        } else {
            XCTAssertEqual(requestSent, interceptor.modifiedRequest, "The request should be modified prior to iOS 13.0.")
        }
    }

    func testGivenURLSession_whenUsingTaskWithURLRequest_itNotifiesCreationAndCompletionAndModifiesTheRequest() throws {
        let requestModified = expectation(description: "Modify request")
        let notifyTaskCreated = expectation(description: "Notify task creation")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onRequestModified = { _ in requestModified.fulfill() }
        interceptor.onTaskCreated = { _, _ in notifyTaskCreated.fulfill() }
        interceptor.onTaskCompleted = { _, _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let session = interceptedSession()

        // When
        let task = session.dataTask(with: URLRequest(url: .mockAny()))
        task.resume()

        // Then
        wait(for: [requestModified, notifyTaskCreated, notifyTaskCompleted], timeout: 0.5, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(requestSent, interceptor.modifiedRequest, "The request should be modified.")
    }

    func testGivenURLSession_whenUsingTaskWithURL_itNotifiesCreationAndCompletionAndDoesNotModifiyTheRequest() throws {
        let requestNotModified = expectation(description: "Do not modify request")
        requestNotModified.isInverted = true
        let notifyTaskCreated = expectation(description: "Notify task creation")
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onRequestModified = { _ in requestNotModified.fulfill() }
        interceptor.onTaskCreated = { _, _ in notifyTaskCreated.fulfill() }
        interceptor.onTaskCompleted = { _, _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let session = interceptedSession()

        // When
        let task = session.dataTask(with: URL.mockRandom())
        task.resume()

        // Then
        wait(for: [requestNotModified, notifyTaskCreated, notifyTaskCompleted], timeout: 0.5, enforceOrder: true)

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertNotEqual(requestSent, interceptor.modifiedRequest, "The request should not be modified.")
    }

    func testGivenNSURLSession_whenNillifyingCompletionHandler_itNotifiesCreationAndCompletion() throws {
        let notifyTaskCreated = expectation(description: "Notify 2 tasks creation")
        notifyTaskCreated.expectedFulfillmentCount = 2
        let notifyTaskCompleted = expectation(description: "Notify any task completion")
        notifyTaskCompleted.expectedFulfillmentCount = 2
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.modifiedRequest = URLRequest(url: .mockRandom())
        interceptor.onTaskCreated = { _, _ in notifyTaskCreated.fulfill() }
        interceptor.onTaskCompleted = { _, _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let nsSession = NSURLSessionBridge(interceptedSession())!

        // When
        let task1 = nsSession.dataTask(with: URL.mockRandom(), completionHandler: nil)!
        task1.resume()

        let task2 = nsSession.dataTask(with: URLRequest.mockAny(), completionHandler: nil)!
        task2.resume()

        // Then
        wait(for: [notifyTaskCreated, notifyTaskCompleted], timeout: 0.5, enforceOrder: true)

        _ = server.waitAndReturnRequests(count: 2)
    }

    func testGivenNonInterceptedSession_itDoesntCallInterceptor() throws {
        let doNotNotifyTaskCreated = expectation(description: "Notify task creation")
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
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertNotNil(taskWithURL)
        XCTAssertNotNil(taskWithURLRequest)
        XCTAssertNotNil(taskWithURLWithCompletion)
        XCTAssertNotNil(taskWithURLRequestWithCompletion)
    }

    // MARK: - Interception Values

    func testGivenSuccessfulTask_whenUsingSwizzledAPIs_itPassessAllValuesToTheInterceptor() {
        let completionHandlersCalled = expectation(description: "Call completion handlers")
        completionHandlersCalled.expectedFulfillmentCount = 2

        // Given
        let expectedResponse: HTTPURLResponse = .mockResponseWith(statusCode: 200)
        let expectedData: Data = .mock(ofSize: 10)
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
        waitForExpectations(timeout: 0.5, handler: nil)

        _ = server.waitAndReturnRequests(count: 4)
        XCTAssertEqual(interceptor.tasksCreated.count, 4, "Interceptor should record all 4 tasks created.")
        XCTAssertEqual(interceptor.tasksCompleted.count, 4, "Interceptor should record all 4 tasks completed.")

        XCTAssertTrue(interceptor.tasksCreated[0].session === session)
        XCTAssertTrue(interceptor.tasksCreated[0].task === taskWithURLRequestAndCompletion)
        XCTAssertTrue(interceptor.tasksCompleted[0].session === session)
        XCTAssertTrue(interceptor.tasksCompleted[0].task === taskWithURLRequestAndCompletion)
        XCTAssertNil(interceptor.tasksCompleted[0].error)

        XCTAssertTrue(interceptor.tasksCreated[1].session === session)
        XCTAssertTrue(interceptor.tasksCreated[1].task === taskWithURLAndCompletion)
        XCTAssertTrue(interceptor.tasksCompleted[1].session === session)
        XCTAssertTrue(interceptor.tasksCompleted[1].task === taskWithURLAndCompletion)
        XCTAssertNil(interceptor.tasksCompleted[1].error)

        XCTAssertTrue(interceptor.tasksCreated[2].session === session)
        XCTAssertTrue(interceptor.tasksCreated[2].task === taskWithURLRequest)
        XCTAssertTrue(interceptor.tasksCompleted[2].session === session)
        XCTAssertTrue(interceptor.tasksCompleted[2].task === taskWithURLRequest)
        XCTAssertNil(interceptor.tasksCompleted[2].error)

        XCTAssertTrue(interceptor.tasksCreated[3].session === session)
        XCTAssertTrue(interceptor.tasksCreated[3].task === taskWithURL)
        XCTAssertTrue(interceptor.tasksCompleted[3].session === session)
        XCTAssertTrue(interceptor.tasksCompleted[3].task === taskWithURL)
        XCTAssertNil(interceptor.tasksCompleted[3].error)
    }

    func testGivenFailedTask_whenUsingSwizzledAPIs_itPassessAllValuesToTheInterceptor() {
        let notifyTaskCompleted = expectation(description: "Notify task completion")
        notifyTaskCompleted.expectedFulfillmentCount = 4
        interceptor.onTaskCompleted = { _, _, _ in notifyTaskCompleted.fulfill() }

        // Given
        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let server = ServerMock(delivery: .failure(error: expectedError))
        let session = interceptedSession()

        // When
        let taskWithURLRequestAndCompletion = session.dataTask(with: URLRequest(url: .mockAny())) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error! as NSError).localizedDescription, "some error")
        }
        taskWithURLRequestAndCompletion.resume()

        let taskWithURLAndCompletion = session.dataTask(with: URL.mockAny()) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error! as NSError).localizedDescription, "some error")
        }
        taskWithURLAndCompletion.resume()

        let taskWithURLRequest = session.dataTask(with: URLRequest(url: .mockAny()))
        taskWithURLRequest.resume()

        let taskWithURL = session.dataTask(with: URL.mockAny())
        taskWithURL.resume()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        _ = server.waitAndReturnRequests(count: 4)
        XCTAssertEqual(interceptor.tasksCreated.count, 4, "Interceptor should record all 4 tasks created.")
        XCTAssertEqual(interceptor.tasksCompleted.count, 4, "Interceptor should record all 4 tasks completed.")

        XCTAssertTrue(interceptor.tasksCreated[0].session === session)
        XCTAssertTrue(interceptor.tasksCreated[0].task === taskWithURLRequestAndCompletion)
        XCTAssertTrue(interceptor.tasksCompleted[0].session === session)
        XCTAssertTrue(interceptor.tasksCompleted[0].task === taskWithURLRequestAndCompletion)
        XCTAssertEqual((interceptor.tasksCompleted[0].error! as NSError).localizedDescription, "some error")

        XCTAssertTrue(interceptor.tasksCreated[1].session === session)
        XCTAssertTrue(interceptor.tasksCreated[1].task === taskWithURLAndCompletion)
        XCTAssertTrue(interceptor.tasksCompleted[1].session === session)
        XCTAssertTrue(interceptor.tasksCompleted[1].task === taskWithURLAndCompletion)
        XCTAssertEqual((interceptor.tasksCompleted[1].error! as NSError).localizedDescription, "some error")

        XCTAssertTrue(interceptor.tasksCreated[2].session === session)
        XCTAssertTrue(interceptor.tasksCreated[2].task === taskWithURLRequest)
        XCTAssertTrue(interceptor.tasksCompleted[2].session === session)
        XCTAssertTrue(interceptor.tasksCompleted[2].task === taskWithURLRequest)
        XCTAssertEqual((interceptor.tasksCompleted[2].error! as NSError).localizedDescription, "some error")

        XCTAssertTrue(interceptor.tasksCreated[3].session === session)
        XCTAssertTrue(interceptor.tasksCreated[3].task === taskWithURL)
        XCTAssertTrue(interceptor.tasksCompleted[3].session === session)
        XCTAssertTrue(interceptor.tasksCompleted[3].task === taskWithURL)
        XCTAssertEqual((interceptor.tasksCompleted[3].error! as NSError).localizedDescription, "some error")
    }
}
