/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class URLSessionSwizzlerTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: SingleFeatureCoreMock<NetworkInstrumentationFeature>!
    private var handler: URLSessionHandlerMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()

        core = SingleFeatureCoreMock()
        handler = URLSessionHandlerMock()

        try core.register(urlSessionHandler: handler)
    }

    override func tearDown() {
        core = nil
        handler = nil
        super.tearDown()
    }

    // MARK: - Binding

    func testBindings() throws {
        func AssertSwizzlingEnable() {
            XCTAssertNotNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion)
            XCTAssertNotNil(URLSessionSwizzler.dataTaskWithURLRequest)
            if #available(iOS 13.0, *) {
                XCTAssertNotNil(URLSessionSwizzler.dataTaskWithURLAndCompletion)
                XCTAssertNotNil(URLSessionSwizzler.dataTaskWithURL)
            }
        }

        func AssertSwizzlingDisable() {
            XCTAssertEqual(URLSessionSwizzler.bindingsCount, 0)
            XCTAssertNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion)
            XCTAssertNil(URLSessionSwizzler.dataTaskWithURLRequest)
            XCTAssertNil(URLSessionSwizzler.dataTaskWithURLAndCompletion)
            XCTAssertNil(URLSessionSwizzler.dataTaskWithURL)
        }

        // binding from `core`
        XCTAssertEqual(URLSessionSwizzler.bindingsCount, 1)
        AssertSwizzlingEnable()

        try URLSessionSwizzler.bind()
        XCTAssertEqual(URLSessionSwizzler.bindingsCount, 2)
        AssertSwizzlingEnable()

        URLSessionSwizzler.unbind()
        XCTAssertEqual(URLSessionSwizzler.bindingsCount, 1)
        AssertSwizzlingEnable()

        URLSessionSwizzler.unbind()
        AssertSwizzlingDisable()

        URLSessionSwizzler.unbind()
        XCTAssertEqual(URLSessionSwizzler.bindingsCount, 0)
        AssertSwizzlingDisable()
    }

    // MARK: - Interception Flow

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURLRequestAndCompletion_itNotifiesCreationAndCompletionAndModifiesTheRequest() throws {
        let notifyRequestMutation = expectation(description: "Notify request mutation")
        let notifyInterceptionStart = expectation(description: "Notify interception did start")
        let notifyInterceptionComplete = expectation(description: "Notify intercepion did complete")
        let completionHandlerCalled = expectation(description: "Call completion handler")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        handler.modifiedRequest = URLRequest(url: .mockRandom())
        handler.onRequestMutation = { _, _ in notifyRequestMutation.fulfill() }
        handler.onInterceptionStart = { _ in notifyInterceptionStart.fulfill() }
        handler.onInterceptionComplete = { _ in notifyInterceptionComplete.fulfill() }

        // Given
        let url: URL = .mockRandom()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        session
            .dataTask(with: URLRequest(url: url)) { _, _, _ in completionHandlerCalled.fulfill() }
            .resume()

        // Then
        wait(for: [completionHandlerCalled], timeout: 1)
        wait(
            for: [
                notifyRequestMutation,
                notifyInterceptionStart,
                notifyInterceptionComplete
            ],
            timeout: 1,
            enforceOrder: true
        )

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(requestSent, handler.modifiedRequest, "The request should be modified")
    }

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURLAndCompletion_itNotifiesTaskCreationAndCompletionAndModifiesTheRequestOnlyPriorToIOS13() throws {
        let notifyRequestMutation = expectation(description: "Notify request mutation")
        if #available(iOS 13.0, *) {
            notifyRequestMutation.isInverted = true
        }
        let notifyInterceptionStart = expectation(description: "Notify interception did start")
        let notifyInterceptionComplete = expectation(description: "Notify intercepion did complete")
        let completionHandlerCalled = expectation(description: "Call completion handler")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        handler.modifiedRequest = URLRequest(url: .mockRandom())
        handler.onRequestMutation = { _, _ in notifyRequestMutation.fulfill() }
        handler.onInterceptionStart = { _ in notifyInterceptionStart.fulfill() }
        handler.onInterceptionComplete = { _ in notifyInterceptionComplete.fulfill() }

        // Given
        let url: URL = .mockRandom()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        session
            .dataTask(with: url) { _, _, _ in completionHandlerCalled.fulfill() }
            .resume()

        // Then
        wait(for: [completionHandlerCalled], timeout: 1)
        wait(
            for: [
                notifyRequestMutation,
                notifyInterceptionStart,
                notifyInterceptionComplete
            ],
            timeout: 2,
            enforceOrder: true
        )

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        if #available(iOS 13.0, *) {
            XCTAssertNotEqual(requestSent, handler.modifiedRequest, "The request should not be modified on iOS 13.0 and above.")
        } else {
            XCTAssertEqual(requestSent, handler.modifiedRequest, "The request should be modified prior to iOS 13.0.")
        }
    }

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURLRequest_itNotifiesCreationAndCompletionAndModifiesTheRequest() throws {
        let notifyRequestMutation = expectation(description: "Notify request mutation")
        let notifyInterceptionStart = expectation(description: "Notify interception did start")
        let notifyInterceptionComplete = expectation(description: "Notify intercepion did complete")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        handler.modifiedRequest = URLRequest(url: .mockRandom())
        handler.onRequestMutation = { _, _ in notifyRequestMutation.fulfill() }
        handler.onInterceptionStart = { _ in notifyInterceptionStart.fulfill() }
        handler.onInterceptionComplete = { _ in notifyInterceptionComplete.fulfill() }

        // Given
        let url: URL = .mockAny()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URLRequest(url: url))
        task.resume()

        // Then
        wait(
            for: [
                notifyRequestMutation,
                notifyInterceptionStart,
                notifyInterceptionComplete
            ],
            timeout: 2,
            enforceOrder: true
        )

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertEqual(requestSent, handler.modifiedRequest, "The request should be modified.")
    }

    func testGivenURLSessionWithDDURLSessionDelegate_whenUsingTaskWithURL_itNotifiesCreationAndCompletionAndDoesNotModifyTheRequest() throws {
        let notifyRequestMutation = expectation(description: "Notify request mutation")
        notifyRequestMutation.isInverted = true
        let notifyInterceptionStart = expectation(description: "Notify interception did start")
        let notifyInterceptionComplete = expectation(description: "Notify intercepion did complete")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        handler.modifiedRequest = URLRequest(url: .mockRandom())
        handler.onRequestMutation = { _, _ in notifyRequestMutation.fulfill() }
        handler.onInterceptionStart = { _ in notifyInterceptionStart.fulfill() }
        handler.onInterceptionComplete = { _ in notifyInterceptionComplete.fulfill() }

        // Given
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URL.mockRandom())
        task.resume()

        // Then
        wait(
            for: [
                notifyRequestMutation,
                notifyInterceptionStart,
                notifyInterceptionComplete
            ],
            timeout: 2,
            enforceOrder: true
        )

        let requestSent = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)
        XCTAssertNotEqual(requestSent, handler.modifiedRequest, "The request should not be modified.")
    }

    func testGivenNonInterceptedSession_itDoesntCallInterceptor() throws {
        let doNotModifyRequest = expectation(description: "Do not notify request modification")
        doNotModifyRequest.isInverted = true
        let doNotNotifyStart = expectation(description: "Do not notify task creation")
        doNotNotifyStart.isInverted = true

        handler.onRequestMutation = { _, _ in doNotModifyRequest.fulfill() }
        handler.onInterceptionStart = { _ in doNotNotifyStart.fulfill() }

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
        let notifyTaskCompleted = expectation(description: "Notify 4 tasks completion")
        notifyTaskCompleted.expectedFulfillmentCount = 4

        handler.onInterceptionComplete = { _ in notifyTaskCompleted.fulfill() }

        // Given
        let expectedResponse: HTTPURLResponse = .mockResponseWith(statusCode: 200)
        let expectedData: Data = .mockRandom()
        let server = ServerMock(delivery: .success(response: expectedResponse, data: expectedData))
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let url1: URL = .mockRandom()
        session.dataTask(with: URLRequest(url: url1)) { data, response, error in
            XCTAssertEqual(data, expectedData)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, expectedResponse.statusCode)
            XCTAssertNil(error)
            completionHandlersCalled.fulfill()
        }
        .resume()

        let url2: URL = .mockRandom()
        session.dataTask(with: url2) { data, response, error in
            XCTAssertEqual(data, expectedData)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, expectedResponse.statusCode)
            XCTAssertNil(error)
            completionHandlersCalled.fulfill()
        }
        .resume()

        let url3: URL = .mockRandom()
        session
            .dataTask(with: URLRequest(url: url3))
            .resume()

        let url4: URL = .mockRandom()
        session
            .dataTask(with: url4)
            .resume()

        // Then
        waitForExpectations(timeout: 2, handler: nil)

        _ = server.waitAndReturnRequests(count: 4)
        XCTAssertEqual(handler.interceptions.count, 4, "Interceptor should record 4 tasks")

        try [url1, url2, url3, url4].forEach { url in
            let interception = try handler.interception(for: url).unwrapOrThrow()
            XCTAssertEqual(interception.data, expectedData)
            XCTAssertNotNil(interception.completion)
            XCTAssertNil(interception.completion?.error)
        }
    }

    func testGivenFailedTask_whenUsingSwizzledAPIs_itPassesAllValuesToTheInterceptor() throws {
        let completionHandlersCalled = expectation(description: "Call 2 completion handlers")
        completionHandlersCalled.expectedFulfillmentCount = 2
        let notifyTaskCompleted = expectation(description: "Notify 4 tasks completion")
        notifyTaskCompleted.expectedFulfillmentCount = 4

        handler.onInterceptionComplete = { _ in notifyTaskCompleted.fulfill() }

        // Given
        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let server = ServerMock(delivery: .failure(error: expectedError))
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let url1: URL = .mockRandom()
        session.dataTask(with: URLRequest(url: url1)) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error! as NSError).localizedDescription, "some error")
            completionHandlersCalled.fulfill()
        }
        .resume()

        let url2: URL = .mockRandom()
        session.dataTask(with: url2) { data, response, error in
            XCTAssertNil(data)
            XCTAssertNil(response)
            XCTAssertEqual((error! as NSError).localizedDescription, "some error")
            completionHandlersCalled.fulfill()
        }
        .resume()

        let url3: URL = .mockRandom()
        session
            .dataTask(with: URLRequest(url: url3))
            .resume()

        let url4: URL = .mockRandom()
        session
            .dataTask(with: url4)
            .resume()

        // Then
        waitForExpectations(timeout: 2, handler: nil)

        _ = server.waitAndReturnRequests(count: 4)
        XCTAssertEqual(handler.interceptions.count, 4, "Interceptor should record completion of 4 tasks")

        try [url1, url2, url3, url4].forEach { url in
            let interception = try handler.interception(for: url).unwrapOrThrow()
            XCTAssertNil(interception.data, "Data should not be recorded for \(url)")
            XCTAssertEqual((interception.completion?.error as? NSError)?.localizedDescription, "some error")
        }
    }

    // MARK: - Thread Safety

    func testConcurrentBinding() throws {
        // swiftlint:disable opening_brace trailing_closure
        callConcurrently(
            closures: [
                { try? URLSessionSwizzler.bind() },
                { URLSessionSwizzler.unbind() },
                { try? URLSessionSwizzler.bind() },
                { URLSessionSwizzler.unbind() }
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }
}
