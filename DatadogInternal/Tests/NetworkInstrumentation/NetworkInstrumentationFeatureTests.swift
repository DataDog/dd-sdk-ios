/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class NetworkInstrumentationFeatureTests: XCTestCase {
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
        let notifyInterceptionStart = expectation(description: "Notify interception did start")
        let notifyInterceptionComplete = expectation(description: "Notify intercepion did complete")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.onInterceptionStart = { _ in notifyInterceptionStart.fulfill() }
        interceptor.onInterceptionComplete = { _ in notifyInterceptionComplete.fulfill() }

        // Given
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let task = session.dataTask(with: URL.mockAny())
        task.resume()

        // Then
        wait(
            for: [
                notifyInterceptionStart,
                notifyInterceptionComplete
            ],
            timeout: 0.5,
            enforceOrder: true
        )
        _ = server.waitAndReturnRequests(count: 1)
    }

    func testGivenURLSessionWithDatadogDelegate_whenUsingTaskWithURLRequest_itNotifiesInterceptor() {
        let notifyRequestMutation  = expectation(description: "Notify request mutation")
        let notifyInterceptionStart = expectation(description: "Notify interception did start")
        let notifyInterceptionComplete = expectation(description: "Notify intercepion did complete")
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: .mock(ofSize: 10)))

        interceptor.onRequestMutation = { _, _ in notifyRequestMutation.fulfill() }
        interceptor.onInterceptionStart = { _ in notifyInterceptionStart.fulfill() }
        interceptor.onInterceptionComplete = { _ in notifyInterceptionComplete.fulfill() }

        // Given
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        session
            .dataTask(with: URLRequest.mockAny())
            .resume()

        // Then
        wait(
            for: [
                notifyRequestMutation,
                notifyInterceptionStart,
                notifyInterceptionComplete
            ],
            timeout: 0.5,
            enforceOrder: true
        )
        _ = server.waitAndReturnRequests(count: 1)
    }

    // MARK: - Interception Values

    func testGivenURLSessionWithDatadogDelegate_whenTaskCompletesWithFailure_itPassesAllValuesToTheInterceptor() throws {
        let notifyInterceptionStart = expectation(description: "Notify interception did start")
        let notifyInterceptionComplete = expectation(description: "Notify intercepion did complete")
        notifyInterceptionStart.expectedFulfillmentCount = 2
        notifyInterceptionComplete.expectedFulfillmentCount = 2

        let expectedError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "some error"])
        let server = ServerMock(delivery: .failure(error: expectedError))

        interceptor.onInterceptionStart = { _ in notifyInterceptionStart.fulfill() }
        interceptor.onInterceptionComplete = { _ in notifyInterceptionComplete.fulfill() }

        let dateBeforeAnyRequests = Date()

        // Given
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let url1: URL = .mockRandom()
        session
            .dataTask(with: url1)
            .resume()

        let url2: URL = .mockRandom()
        session
            .dataTask(with: URLRequest(url: url2))
            .resume()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)

        let dateAfterAllRequests = Date()

        XCTAssertEqual(interceptor.interceptions.count, 2, "Interceptor should record metrics for 2 tasks")

        try [url1, url2].forEach { url in
            let interception = try interceptor.interception(for: url).unwrapOrThrow()
            XCTAssertGreaterThan(interception.metrics!.fetch.start, dateBeforeAnyRequests)
            XCTAssertLessThan(interception.metrics!.fetch.end, dateAfterAllRequests)
            XCTAssertNil(interception.data, "Data should not be recorded for \(url)")
            XCTAssertEqual((interception.completion?.error as? NSError)?.localizedDescription, "some error")
        }
    }

    func testGivenURLSessionWithDatadogDelegate_whenTaskCompletesWithSuccess_itPassesAllValuesToTheInterceptor() throws {
        let notifyInterceptionStart = expectation(description: "Notify interception did start")
        let notifyInterceptionComplete = expectation(description: "Notify intercepion did complete")
        notifyInterceptionStart.expectedFulfillmentCount = 2
        notifyInterceptionComplete.expectedFulfillmentCount = 2

        let randomData: Data = .mockRandom()
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200), data: randomData))

        interceptor.onInterceptionStart = { _ in notifyInterceptionStart.fulfill() }
        interceptor.onInterceptionComplete = { _ in notifyInterceptionComplete.fulfill() }

        let dateBeforeAnyRequests = Date()

        // Given
        let delegate = DatadogURLSessionDelegate(in: core)
        let session = server.getInterceptedURLSession(delegate: delegate)

        // When
        let url1 = URL.mockRandom()
        session
            .dataTask(with: url1)
            .resume()

        let url2 = URL.mockRandom()
        session
            .dataTask(with: URLRequest(url: url2))
            .resume()

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        _ = server.waitAndReturnRequests(count: 1)

        let dateAfterAllRequests = Date()

        XCTAssertEqual(interceptor.interceptions.count, 2, "Interceptor should record metrics for 2 tasks")

        try [url1, url2].forEach { url in
            let interception = try interceptor.interception(for: url).unwrapOrThrow()
            XCTAssertGreaterThan(interception.metrics!.fetch.start, dateBeforeAnyRequests)
            XCTAssertLessThan(interception.metrics!.fetch.end, dateAfterAllRequests)
            XCTAssertEqual(interception.data, randomData)
            XCTAssertNotNil(interception.completion)
            XCTAssertNil(interception.completion?.error)
        }
    }

    // MARK: - Usage

    func testItCanBeInitializedBeforeInitializingDefaultSDKCore() throws {
        // Given
        let delegate1 = DatadogURLSessionDelegate()
        let delegate2 = DatadogURLSessionDelegate(additionalFirstPartyHosts: [])
        let delegate3 = DatadogURLSessionDelegate(additionalFirstPartyHostsWithHeaderTypes: [:])

        // When
        defaultDatadogCore = core
        defer { defaultDatadogCore = NOPDatadogCore() }

        // Then
        XCTAssertNotNil(delegate1.feature)
        XCTAssertNotNil(delegate2.feature)
        XCTAssertNotNil(delegate3.feature)
    }

    func testItCanBeInitializedAfterInitializingDefaultSDKCore() throws {
        // Given
        defaultDatadogCore = core
        defer { defaultDatadogCore = NOPDatadogCore() }

        // When
        let delegate1 = DatadogURLSessionDelegate()
        let delegate2 = DatadogURLSessionDelegate(additionalFirstPartyHosts: [])
        let delegate3 = DatadogURLSessionDelegate(additionalFirstPartyHostsWithHeaderTypes: [:])

        // Then
        XCTAssertNotNil(delegate1.feature)
        XCTAssertNotNil(delegate2.feature)
        XCTAssertNotNil(delegate3.feature)
    }

    func testItOnlyKeepsInstrumentationWhileSDKCoreIsAvailableInMemory() throws {
        // Given
        var core: DatadogCoreProtocol? = SingleFeatureCoreMock<NetworkInstrumentationFeature>()
        try core?.register(urlSessionInterceptor: interceptor)

        // When
        let delegate = DatadogURLSessionDelegate(in: core)
        // Then
        XCTAssertNotNil(delegate.feature)

        // When (deinitialize core)
        core = nil
        // Then
        XCTAssertNil(delegate.feature)
    }
}
