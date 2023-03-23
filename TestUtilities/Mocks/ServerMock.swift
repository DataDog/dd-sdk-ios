/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

/// An utility header, added to each request by the `ServerMock` and removed while intercepting through `ServerMockProtocol`.
/// It transmits an unique identifier of the `URLSession` instance obtained from `ServerMock`. It is used for consistency check
/// installed in `ServerMockProtocol`, to ensure that the request completion is delivered to the right instance of `ServerMock`.
///
/// Added in RUMM-1381 to fix a range of flakiness caused by leaking asynchronous upload tasks.
private let ddURLSessionUUIDHeaderField = "dd-urlsession-uuid"

public class ServerMockProtocol: URLProtocol {
    override public class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override public class func canonicalRequest(for request: URLRequest) -> URLRequest {
        // By the time this `canonicalRequest(for:)` is called, the original `URLRequest` is
        // already transformed in `URLSession` by encoding `httpBody` into a stream and
        // setting `Content-Length` HTTP header. This means that the `request` is not the one
        // that we originally sent. Here, we transform it back from `httpBodyStream` to `httpBody`.
        if let httpBodyStream = request.httpBodyStream {
            let contentLength = Int(request.allHTTPHeaderFields!["Content-Length"]!)!

            var canonicalRequest = URLRequest(url: request.url!)
            canonicalRequest.httpMethod = request.httpMethod
            canonicalRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
            canonicalRequest.httpBody = httpBodyStream.readAllBytes(expectedSize: contentLength)
            return canonicalRequest
        } else {
            return request
        }
    }

    /// An instance of the `ServerMock` configured to intercept request processed by this `URLProtocol`.
    private weak var server: ServerMock?

    override public init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
        // Capture the active instance of `ServerMock`
        server = ServerMock.activeInstance

        // Get utility header value to match it with an active instance of `ServerMock`
        let urlSessionUUID = UUID(uuidString: request.allHTTPHeaderFields![ddURLSessionUUIDHeaderField]!)!

        super.init(
            request: request.removing(httpHeaderField: ddURLSessionUUIDHeaderField), // remove utility header
            cachedResponse: cachedResponse,
            client: client
        )

        // Assert that the request will be intercepted by the right instance of `ServerMock`.
        precondition(
            server?.urlSessionUUID == urlSessionUUID,
            """
            ⚠️ Request to \(request.url?.absoluteString ?? "null") was sent to `ServerMock` with `urlSessionUUID`: \(urlSessionUUID.uuidString),
            but it was received by the `ServerMock` with `urlSessionUUID`: \(server?.urlSessionUUID.uuidString ?? "<deallocated>")).
            This indicates lack of test synchronization or cleanup and must be fixed, otherwise the test will become flaky.
            """
        )
    }

    override public func startLoading() {
        if let response = server?.mockedResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data = server?.mockedData {
            client?.urlProtocol(self, didLoad: data)
        }
        if let error = server?.mockedError {
            client?.urlProtocol(self, didFailWithError: error)
        }

        client?.urlProtocolDidFinishLoading(self)

        server?.record(newRequest: request)
    }

    override public func stopLoading() {
        // No-op. This method must be defined as this method is made abstract in a base class (`URLProtocol`).
    }
}

public class ServerMock {
    public static weak var activeInstance: ServerMock?

    /// An unique identifier of the `URLSession` produced by this instance of `ServerMock`.
    public let urlSessionUUID = UUID()
    private let queue: DispatchQueue

    fileprivate let mockedResponse: HTTPURLResponse?
    fileprivate let mockedData: Data?
    fileprivate let mockedError: NSError?

    public enum Delivery {
        case success(response: HTTPURLResponse, data: Data = .mockAny())
        case failure(error: NSError)
    }

    public init(delivery: Delivery) {
        switch delivery {
        case let .success(response: response, data: data):
            self.mockedResponse = response
            self.mockedData = data
            self.mockedError = nil
        case let .failure(error):
            self.mockedResponse = nil
            self.mockedData = nil
            self.mockedError = error
        }
        precondition(Thread.isMainThread, "`ServerMock` should be initialized on the main thread.")
        precondition(ServerMock.activeInstance == nil, "Only one active instance of `ServerMock` is allowed at a time.")
        self.queue = DispatchQueue(label: "com.datadoghq.ServerMock-\(urlSessionUUID.uuidString)")

        ServerMock.activeInstance = self
    }

    deinit {
        /// Following precondition will fail when `ServerMock` instance was retained ONLY by existing HTTP request callback.
        /// Such case means a programmer error, because the existing callback can impact result of the next unit test, causing a flakiness.
        ///
        /// If that happens, make sure the `ServerMock` processes all callbacks before it gets deallocated:
        ///
        ///     func testXYZ() {
        ///        let server = ServerMock(...)
        ///
        ///        // ... testing
        ///
        ///        server.waitFor(requestsCompletion:)
        ///        // <-- no reference to `server` exists and it processed all callbacks, so it will be safely deallocated
        ///     }
        ///
        /// NOTE: one of the `wait*` methods **must be called** within the test using `ServerMock`.
        ///
        precondition(Thread.isMainThread, "`ServerMock` should be deinitialized on the main thread.")
    }

    fileprivate func record(newRequest: URLRequest) {
        queue.async {
            self.requests.append(newRequest)
            self.waitAndReturnRequestsExpectation?.fulfill()
        }
    }

    private var requests: [URLRequest] = []
    private var waitAndReturnRequestsExpectation: XCTestExpectation?

    // MARK: - Obtaining URLSession

    private var doesInterceptSession = false

    /// Produces `URLSession` intercepted by this instance of `ServerMock`. The session will use `delegate` if it's provided.
    /// Requests sent to this session can be obtained later with using `serverMock.wait...()` APIs.
    public func getInterceptedURLSession(delegate: URLSessionDelegate? = nil) -> URLSession {
        precondition(!doesInterceptSession, "This instance of `ServerMock` already intercepts the `URLSession`. Re-use the existing one.")
        doesInterceptSession = true

        let configuration = URLSessionConfiguration.ephemeral
        // Set utility header so we can identify this request in `ServerMockProtocol`.
        configuration.httpAdditionalHeaders = [ddURLSessionUUIDHeaderField: urlSessionUUID.uuidString]
        configuration.protocolClasses = [ServerMockProtocol.self]
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Waiting for total number of requests

    /// Waits until given number of request callbacks is completed (in total for this instance of `ServerMock`) and returns that requests.
    /// Passing no `timeout` will result with picking the recommended timeout for unit tests.
    /// Calling this method guarantees also that no callbacks are leaked inside `URLSession`, which prevents tests flakiness.
    public func waitAndReturnRequests(count: UInt, timeout: TimeInterval? = nil, file: StaticString = #file, line: UInt = #line) -> [URLRequest] {
        precondition(waitAndReturnRequestsExpectation == nil, "The `ServerMock` is already waiting on `waitAndReturnRequests`.")

        let expectation = XCTestExpectation(description: "Receive \(count) requests.")
        if count > 0 {
            expectation.expectedFulfillmentCount = Int(count)
        } else {
            expectation.isInverted = true
        }

        queue.sync {
            self.waitAndReturnRequestsExpectation = expectation
            self.requests.forEach { _ in expectation.fulfill() } // fulfill already recorded
        }

        let timeout = timeout ?? recommendedTimeoutFor(numberOfRequestsMade: max(count, 1))
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        switch result {
        case .completed:
            break
        case .incorrectOrder, .interrupted:
            fatalError("Can't happen.")
        case .timedOut:
            XCTFail("Exceeded timeout of \(timeout)s with receiving \(requests.count) out of \(count) expected requests.", file: file, line: line)
            // Return array of dummy requests, so the crash will happen later in the test code, properly
            // printing the above error.
            return Array(repeating: .mockAny(), count: Int(count))
        case .invertedFulfillment:
            XCTFail("\(requests.count) requests were sent, but not expected.", file: file, line: line)
            // Return array of dummy requests, so the crash will happen later in the test code, properly
            // printing the above error.
            return queue.sync { requests.map(decompress) }
        @unknown default:
            fatalError()
        }

        return queue.sync { requests.map(decompress) }
    }

    /// Waits until given number of request callbacks is completed (in total for this instance of `ServerMock`).
    /// Passing no `timeout` will result with picking the recommended timeout for unit tests.
    /// Calling this method guarantees that no callbacks are leaked inside `URLSession`, which prevents tests flakiness.
    public func waitFor(requestsCompletion requestsCount: UInt, timeout: TimeInterval? = nil, file: StaticString = #file, line: UInt = #line) {
        _ = waitAndReturnRequests(count: requestsCount, timeout: timeout)
    }

    /// Waits an arbitrary amount of time and asserts that no requests were sent to `ServerMock`. 
    public func waitAndAssertNoRequestsSent(file: StaticString = #file, line: UInt = #line) {
        waitFor(requestsCompletion: 0)
    }

    // MARK: - Utils

    /// Returns recommended timeout for delivering given number of requests if test-tuned values are used for `PerformancePreset`.
    private func recommendedTimeoutFor(numberOfRequestsMade: UInt) -> TimeInterval {
        let uploadPerformanceForTests = UploadPerformanceMock.veryQuick
        // Set the timeout to 40 times more than expected.
        // In `RUMM-311` we observed 0.66% of flakiness for 150 test runs on CI with arbitrary value of `20`.
        return uploadPerformanceForTests.initialUploadDelay * Double(numberOfRequestsMade) * 40
    }

    private func decompress(_ request: URLRequest) -> URLRequest {
        guard
            let body = request.httpBody,
            request.allHTTPHeaderFields?["Content-Encoding"] == "deflate",
            let data = zlib.decode(body)
        else {
            // Returns the untouched request if the request body is not compressed
            // using `deflate` algorithm, or if decompressing the body fails.
            return request
        }

        var request = request
        request.httpBody = data
        return request
    }
}
