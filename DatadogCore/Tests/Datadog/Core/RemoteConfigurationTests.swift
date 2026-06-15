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

    private func makeProvider(
        id: String = "test-id",
        telemetry: Telemetry = NOPTelemetry()
    ) -> RemoteConfigurationProvider {
        RemoteConfigurationProvider(
            id: id,
            site: .us1,
            directory: coreDir.coreDirectory,
            httpClient: httpClient,
            telemetry: telemetry
        )
    }

    private func remoteConfigurationData(applicationID: String = "application-id") -> Data {
        Data("{\"rum\":{\"applicationId\":\"\(applicationID)\"}}".utf8)
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
        let rc = makeProvider()
        guard case .failure = rc.cache else {
            return XCTFail("Expected cache to be .failure on first launch")
        }
    }

    func testInitReadsCacheFromPreviousLaunch() throws {
        let payload = remoteConfigurationData(applicationID: "cached-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try payload.write(to: fileURL, options: .atomic)

        let rc = makeProvider()
        XCTAssertEqual(try rc.cache.get().rum?.applicationId, "cached-application-id")
    }

    func testInitCacheIsFailureWhenNoFileExists() {
        // No .json file on disk — cache must be .failure (first launch)
        let rc = makeProvider()
        guard case .failure = rc.cache else {
            return XCTFail("Expected cache to be .failure when no file exists on disk")
        }
    }

    func testInitCacheDiskReadFailureReportsTelemetry() throws {
        try FileManager.default.createDirectory(
            at: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            withIntermediateDirectories: false
        )
        let telemetry = TelemetryMock()

        let rc = makeProvider(telemetry: telemetry)

        XCTAssertTrue(telemetry.messages.firstError()?.message.hasPrefix("[RemoteConfig] Cache read failed") == true)
        guard case .failure(.diskError) = rc.cache else {
            return XCTFail("Expected cache to be .failure when cached file cannot be read")
        }
    }

    func testInitCacheIsFailureWhenFileCannotBeDecoded() throws {
        try Data("this is not json".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            options: .atomic
        )

        let rc = makeProvider()
        guard case .failure(.decodingError) = rc.cache else {
            return XCTFail("Expected cache to be .failure when file cannot be decoded")
        }
    }

    // MARK: sync()

    func testSyncReturnsSuccessAndPopulatesCache() {
        let payload = remoteConfigurationData(applicationID: "fetched-application-id")
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeProvider()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            XCTAssertEqual(try? result.get().rum?.applicationId, "fetched-application-id")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(try? rc.cache.get().rum?.applicationId, "fetched-application-id")
        XCTAssertEqual(try? Data(contentsOf: coreDir.coreDirectory.url.appendingPathComponent("test-id.json")), payload)
    }

    func testSyncPersistsCacheAcrossInstances() throws {
        let payload = remoteConfigurationData(applicationID: "persisted-application-id")
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeProvider()
        let expectation = expectation(description: "sync completes")
        rc.sync { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(try? makeProvider().cache.get().rum?.applicationId, "persisted-application-id")
    }

    func testSyncNetworkErrorReturnsFailureAndLeavesCache() {
        let error = URLError(.networkConnectionLost)
        let rc = RemoteConfigurationProvider(
            id: "test-id",
            site: .us1,
            directory: coreDir.coreDirectory,
            httpClient: HTTPClientMock(error: error)
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
        let existing = remoteConfigurationData(applicationID: "existing-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
        }
        let rc = makeProvider()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            guard case .failure = result else {
                return XCTFail("Expected failure on non-2xx")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(
            try? makeProvider().cache.get().rum?.applicationId,
            "existing-application-id",
            "Existing cache must be preserved after non-2xx"
        )
        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "Existing file must be preserved after non-2xx")
    }

    func testSyncEmptyBodyReturnsFailureAndLeavesCache() {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        let rc = makeProvider()
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

    func testSyncInvalidJSONBodyReturnsFailureAndPreservesCache() throws {
        let existing = remoteConfigurationData(applicationID: "existing-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)

        let nonJSON = Data("this is not json".utf8)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nonJSON)
        }
        let rc = makeProvider()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            guard case .failure(.decodingError) = result else {
                return XCTFail("Expected decoding failure")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(
            try? rc.cache.get().rum?.applicationId,
            "existing-application-id",
            "Existing cache must be preserved after decoding error"
        )
        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "Existing file must be preserved after decoding error")
    }

    func testSyncDiskWriteFailureReturnsFailure() {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let missingDir = Directory(url: URL(fileURLWithPath: "/no/such/path/"))
        let rc = RemoteConfigurationProvider(
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
        let rc = makeProvider()
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
        let rc = makeProvider()
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

        let rc = makeProvider()
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

        let rc = makeProvider()
        let expectation = expectation(description: "sync completes")

        rc.sync { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "If-None-Match"), "abc123")
    }

    func test304ResponsePreservesCacheAndReportsSuccess() throws {
        // Given — pre-populate cache
        let existing = remoteConfigurationData(applicationID: "existing-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, nil)
        }
        let rc = makeProvider()
        let expectation = expectation(description: "sync completes")

        rc.sync { result in
            XCTAssertEqual(try? result.get().rum?.applicationId, "existing-application-id", "304 must return existing cached configuration")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(try? rc.cache.get().rum?.applicationId, "existing-application-id", "Cache must be unchanged after 304")
        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "File must be unchanged after 304")
    }

    func test304ResponseCallsCompletionEvenWhenCacheIsFailure() {
        // Given — no .json file, so cache is .failure

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, nil)
        }
        let rc = makeProvider()
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
        let payload1 = remoteConfigurationData(applicationID: "application-id-one")
        let payload2 = remoteConfigurationData(applicationID: "application-id-two")

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload1)
        }
        let rc1 = makeProvider(id: "id-one")
        let exp1 = expectation(description: "sync 1 completes")
        rc1.sync { _ in exp1.fulfill() }
        wait(for: [exp1], timeout: 2)

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload2)
        }
        let rc2 = makeProvider(id: "id-two")
        let exp2 = expectation(description: "sync 2 completes")
        rc2.sync { _ in exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        XCTAssertEqual(try? makeProvider(id: "id-one").cache.get().rum?.applicationId, "application-id-one")
        XCTAssertEqual(try? makeProvider(id: "id-two").cache.get().rum?.applicationId, "application-id-two")
    }
}
