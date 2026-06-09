/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

// MARK: - MockURLProtocol

private class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private final class FetchHTTPClientMock: HTTPClient {
    let result: Result<(HTTPURLResponse, Data), Error>

    init(result: Result<(HTTPURLResponse, Data), Error>) {
        self.result = result
    }

    func send(request: URLRequest, delegate: URLSessionTaskDelegate?, completion: @escaping (Result<HTTPURLResponse, Error>) -> Void) {
        completion(.failure(URLSessionTransportInconsistencyException()))
    }

    func fetch(request: URLRequest, completion: @escaping (Result<(HTTPURLResponse, Data), Error>) -> Void) {
        completion(result)
    }
}

// MARK: - Tests

class RemoteConfigurationTests: XCTestCase {
    private var coreDir: CoreDirectory! // swiftlint:disable:this implicitly_unwrapped_optional
    private var httpClient: URLSessionClient! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        coreDir = temporaryUniqueCoreDirectory()
        coreDir.create()
        httpClient = URLSessionClient(session: mockSession())
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        httpClient.session.invalidateAndCancel()
        httpClient = nil
        coreDir.delete()
        super.tearDown()
    }

    private func makeSynchronizer(id: String = "test-id") -> RemoteConfigurationSynchronizer {
        RemoteConfigurationSynchronizer(
            id: id,
            site: .us1,
            directory: coreDir.coreDirectory,
            httpClient: httpClient
        )
    }

    // MARK: endpoint URL construction

    func testEndpointBuildsCorrectURL() {
        let url = DatadogSite.us1.remoteConfigurationEndpoint
            .appendingPathComponent("v1")
            .appendingPathComponent("abc-123")
            .appendingPathExtension("json")
        XCTAssertEqual(url.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/abc-123.json")
    }

    func testEndpointPercentEncodesSpacesInID() {
        let url = DatadogSite.us1.remoteConfigurationEndpoint
            .appendingPathComponent("v1")
            .appendingPathComponent("hello world")
            .appendingPathExtension("json")
        XCTAssertEqual(url.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/hello%20world.json")
    }

    func testEndpointEncodesQuestionMarkSoItDoesNotProduceQueryString() {
        let url = DatadogSite.us1.remoteConfigurationEndpoint
            .appendingPathComponent("v1")
            .appendingPathComponent("id?query")
            .appendingPathExtension("json")
        XCTAssertEqual(url.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/id%3Fquery.json")
    }

    func testEndpointEncodesHashSoItDoesNotProduceFragment() {
        let url = DatadogSite.us1.remoteConfigurationEndpoint
            .appendingPathComponent("v1")
            .appendingPathComponent("id#section")
            .appendingPathExtension("json")
        XCTAssertEqual(url.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/id%23section.json")
    }

    // MARK: Init

    func testInitCacheIsEmptyOnFirstLaunch() {
        let rc = makeSynchronizer()
        guard case .failure = rc.cache else {
            return XCTFail("Expected cache to be .failure on first launch")
        }
    }

    func testInitReadsCacheFromPreviousLaunch() throws {
        let payload = Data("{\"session_sample_rate\":50}".utf8)
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try payload.write(to: fileURL, options: .atomic)

        let rc = makeSynchronizer()
        XCTAssertEqual(try rc.cache.get(), payload)
    }

    func testInitCacheIsFailureWhenNoFileExists() {
        // No .json file on disk — cache must be .failure (first launch)
        let rc = makeSynchronizer()
        guard case .failure = rc.cache else {
            return XCTFail("Expected cache to be .failure when no file exists on disk")
        }
    }

    // MARK: sync()

    func testSyncReturnsSuccessAndPopulatesCache() {
        let payload = Data("{\"session_sample_rate\":50}".utf8)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            XCTAssertEqual(try? result.get(), payload)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(try? rc.cache.get(), payload)
    }

    func testSyncPersistsCacheAcrossInstances() throws {
        let payload = Data("{\"session_sample_rate\":50}".utf8)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")
        rc.sync { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(try? makeSynchronizer().cache.get(), payload)
    }

    func testSyncNetworkErrorReturnsFailureAndLeavesCache() {
        let error = URLError(.networkConnectionLost)
        let rc = RemoteConfigurationSynchronizer(
            id: "test-id",
            site: .us1,
            directory: coreDir.coreDirectory,
            httpClient: FetchHTTPClientMock(result: .failure(error))
        )
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            guard case .failure(.networkError(let receivedError as URLError)) = result else {
                return XCTFail("Expected failure on network error")
            }
            XCTAssertEqual(receivedError.code, error.code)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        guard case .failure = rc.cache else {
            return XCTFail("Cache must remain .failure after network error")
        }
    }

    func testSyncNon2xxReturnsFailureAndPreservesCache() throws {
        let existing = Data("{\"v\":1}".utf8)
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            guard case .failure = result else {
                return XCTFail("Expected failure on non-2xx")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(try? makeSynchronizer().cache.get(), existing, "Existing cache must be preserved after non-2xx")
    }

    func testSyncEmptyBodyReturnsFailureAndLeavesCache() {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            guard case .failure = result else {
                return XCTFail("Expected failure on empty body")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        guard case .failure = rc.cache else {
            return XCTFail("Cache must remain .failure after empty body response")
        }
    }

    func testSyncNonJSONBodyIsSavedToCache() {
        // JSON schema validation is deferred (TODO RUM-16387), so any non-empty 2xx
        // body is accepted and written to cache as-is.
        let nonJSON = Data("this is not json".utf8)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nonJSON)
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            XCTAssertEqual(try? result.get(), nonJSON)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(try? rc.cache.get(), nonJSON)
        XCTAssertEqual(try? Data(contentsOf: coreDir.coreDirectory.url.appendingPathComponent("test-id.json")), nonJSON)
    }

    func testSyncDiskWriteFailureReturnsFailure() {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let missingDir = Directory(url: URL(fileURLWithPath: "/no/such/path/"))
        let rc = RemoteConfigurationSynchronizer(
            id: "test-id",
            site: .us1,
            directory: missingDir,
            httpClient: httpClient
        )
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            guard case .failure = result else {
                return XCTFail("Expected failure on disk write error")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        guard case .failure = rc.cache else {
            return XCTFail("Cache must remain .failure after disk write error")
        }
    }

    // MARK: ETag

    func testSyncStoresETagAfterSuccessfulFetch() {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "abc123"])!, Data("{}".utf8))
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        let etagFileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.etag")
        let storedETag = try? String(data: Data(contentsOf: etagFileURL), encoding: .utf8)
        XCTAssertEqual(storedETag, "abc123")
    }

    func testSyncDeletesStaleETagWhenResponseHasNoETag() throws {
        // Given — a stale ETag file from a previous fetch
        try Data("old-etag".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.etag"),
            options: .atomic
        )

        // When — server returns 200 with new data but no ETag header
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")
        rc.sync { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        // Then — stale ETag file must be deleted so it is never sent as If-None-Match
        let etagFileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.etag")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: etagFileURL.path),
            "Stale ETag must be deleted when 200 response carries no ETag"
        )
    }

    func testSyncDoesNotSendIfNoneMatchWhenCacheIsFailure() throws {
        // Given — ETag file exists but JSON cache is unreadable (cache is .failure)
        try Data("abc123".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.etag"),
            options: .atomic
        )
        // No .json file → cache will be .failure after init

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }

        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertNil(
            capturedRequest?.value(forHTTPHeaderField: "If-None-Match"),
            "Must not send If-None-Match when cache is .failure — a 304 would leave us with no data"
        )
    }

    func testSyncSendsIfNoneMatchHeaderWhenETagStored() throws {
        // Given — store an ETag from a previous fetch
        try Data("abc123".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.etag"),
            options: .atomic
        )

        // Pre-populate .json so cache is .success (required to send If-None-Match)
        try Data("{}".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            options: .atomic
        )

        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }

        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "If-None-Match"), "abc123")
    }

    func test304ResponsePreservesCacheAndReportsSuccess() throws {
        // Given — pre-populate cache
        let existing = Data("{\"v\":1}".utf8)
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, nil)
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            // 304 returns the current cache — .success with existing data
            XCTAssertEqual(try? result.get(), existing, "304 must return existing cached data")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(try? rc.cache.get(), existing, "Cache must be unchanged after 304")
    }

    func test304ResponseCallsCompletionEvenWhenCacheIsFailure() {
        // Given — no .json file, so cache is .failure

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, nil)
        }
        let rc = makeSynchronizer()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            // completionHandler must always be called — even when 304 + cache is .failure
            guard case .failure = result else {
                return XCTFail("Expected .failure when 304 + unreadable cache")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    func testDifferentIDsUseDifferentFiles() throws {
        let payload1 = Data("{\"v\":1}".utf8)
        let payload2 = Data("{\"v\":2}".utf8)

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload1)
        }
        let rc1 = makeSynchronizer(id: "id-one")
        let exp1 = expectation(description: "sync 1 completes")
        rc1.sync { _ in exp1.fulfill() }
        wait(for: [exp1], timeout: 2)

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload2)
        }
        let rc2 = makeSynchronizer(id: "id-two")
        let exp2 = expectation(description: "sync 2 completes")
        rc2.sync { _ in exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        XCTAssertEqual(try? makeSynchronizer(id: "id-one").cache.get(), payload1)
        XCTAssertEqual(try? makeSynchronizer(id: "id-two").cache.get(), payload2)
    }
}
