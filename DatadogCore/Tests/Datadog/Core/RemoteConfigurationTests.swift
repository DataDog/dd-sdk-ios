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

private final class NeverHTTPClient: HTTPClient {
    func send(
        request: URLRequest,
        delegate: URLSessionTaskDelegate?,
        completion: @escaping (Result<(HTTPURLResponse, Data?), Error>) -> Void
    ) {}
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
        httpClient: HTTPClient? = nil,
        notificationCenter: NotificationCenter = NotificationCenter(),
        start: Bool = true
    ) -> RemoteConfigurationProvider {
        let provider = RemoteConfigurationProvider(
            id: id,
            site: .us1,
            directory: coreDir.coreDirectory,
            httpClient: httpClient ?? self.httpClient,
            notificationCenter: notificationCenter
        )
        if start {
            provider.start { _ in }
        }
        return provider
    }

    private func remoteConfigurationData(applicationID: String = "application-id") -> Data {
        Data("{\"rum\":{\"applicationId\":\"\(applicationID)\"}}".utf8)
    }

    private func waitForCache(
        in provider: RemoteConfigurationProvider,
        applicationID: String,
        fileData: Data? = nil,
        fileName: String = "test-id.json"
    ) {
        let expectation = expectation(description: "remote configuration cache is updated")
        wait(until: {
            let cachedApplicationID = try? provider.cache.get().rum?.applicationId
            guard cachedApplicationID == applicationID else {
                return false
            }

            guard let fileData else {
                return true
            }

            let fileURL = self.coreDir.coreDirectory.url.appendingPathComponent(fileName)
            return (try? Data(contentsOf: fileURL)) == fileData
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)
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
        let rc = makeProvider(httpClient: NeverHTTPClient())
        guard case .failure(.diskError) = rc.cache else {
            return XCTFail("Expected cache to be .failure on first launch")
        }
    }

    func testInitReadsCacheFromPreviousLaunch() throws {
        let payload = remoteConfigurationData(applicationID: "cached-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try payload.write(to: fileURL, options: .atomic)

        let rc = makeProvider(httpClient: NeverHTTPClient())
        XCTAssertEqual(try rc.cache.get().rum?.applicationId, "cached-application-id")
    }

    func testInitCacheIsFailureWhenNoFileExists() {
        // No .json file on disk — cache must be .failure (first launch)
        let rc = makeProvider(httpClient: NeverHTTPClient())
        guard case .failure(.diskError) = rc.cache else {
            return XCTFail("Expected cache to be .failure when no file exists on disk")
        }
    }

    func testInitCacheIsFailureWhenFileCannotBeRead() throws {
        try FileManager.default.createDirectory(
            at: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            withIntermediateDirectories: false
        )

        let rc = makeProvider(httpClient: NeverHTTPClient())

        guard case .failure(.diskError) = rc.cache else {
            return XCTFail("Expected cache to be .failure when cached file cannot be read")
        }
    }

    func testStartCacheReadFailureCanBeReportedToTelemetryByCaller() throws {
        try FileManager.default.createDirectory(
            at: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            withIntermediateDirectories: false
        )
        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let telemetry = TelemetryMock()

        let expectation = expectation(description: "cache read failure is returned")
        rc.start { result in
            if case .failure(let error) = result {
                telemetry.error("[RemoteConfig] Load failed", error: error)
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        XCTAssertTrue(telemetry.messages.firstError()?.message.hasPrefix("[RemoteConfig] Load failed") == true)
        guard case .failure(.diskError) = rc.cache else {
            return XCTFail("Expected cache to be .failure when cached file cannot be read")
        }
    }

    func testInitCacheIsFailureWhenFileCannotBeDecoded() throws {
        try Data("this is not json".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            options: .atomic
        )

        let rc = makeProvider(httpClient: NeverHTTPClient())
        guard case .failure(.decodingError) = rc.cache else {
            return XCTFail("Expected cache to be .failure when file cannot be decoded")
        }
    }

    // MARK: Initial sync

    func testInitSyncReturnsSuccessAndPopulatesCache() {
        let payload = remoteConfigurationData(applicationID: "fetched-application-id")
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeProvider()

        waitForCache(in: rc, applicationID: "fetched-application-id", fileData: payload)
    }

    func testInitSyncPersistsCacheAcrossInstances() throws {
        let payload = remoteConfigurationData(applicationID: "persisted-application-id")
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeProvider()
        waitForCache(in: rc, applicationID: "persisted-application-id", fileData: payload)

        XCTAssertEqual(
            try? makeProvider(httpClient: NeverHTTPClient()).cache.get().rum?.applicationId,
            "persisted-application-id"
        )
    }

    func testInitSyncNetworkErrorReturnsFailureAndLeavesCache() {
        let error = URLError(.networkConnectionLost)
        let rc = RemoteConfigurationProvider(
            id: "test-id",
            site: .us1,
            directory: coreDir.coreDirectory,
            httpClient: HTTPClientMock(error: error),
            notificationCenter: NotificationCenter()
        )

        let expectation = expectation(description: "sync fails")
        rc.start { result in
            if case .failure(.networkError) = result {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        guard case .failure = rc.cache else {
            return XCTFail("Cache must remain .failure after network error")
        }
    }

    func testInitSyncNon2xxReturnsFailureAndPreservesCache() throws {
        let existing = remoteConfigurationData(applicationID: "existing-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)
        let requestExpectation = expectation(description: "request completes")

        MockURLProtocol.requestHandler = { request in
            requestExpectation.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil as Data?)
        }
        let rc = makeProvider()
        wait(for: [requestExpectation], timeout: 2)

        XCTAssertEqual(
            try? rc.cache.get().rum?.applicationId,
            "existing-application-id",
            "Existing cache must be preserved after non-2xx"
        )
        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "Existing file must be preserved after non-2xx")
    }

    func testInitSyncEmptyBodyReturnsFailureAndLeavesCache() {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        let rc = makeProvider(start: false)

        let expectation = expectation(description: "sync fails")
        rc.start { result in
            if case .failure(.emptyBody) = result {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        guard case .failure = rc.cache else {
            return XCTFail("Cache must remain .failure after empty body response")
        }
    }

    func testInitSyncInvalidJSONBodyReturnsFailureAndPreservesCache() throws {
        let existing = remoteConfigurationData(applicationID: "existing-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)
        let requestExpectation = expectation(description: "request completes")

        let nonJSON = Data("this is not json".utf8)
        MockURLProtocol.requestHandler = { request in
            requestExpectation.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nonJSON)
        }
        let rc = makeProvider()
        wait(for: [requestExpectation], timeout: 2)

        XCTAssertEqual(
            try? rc.cache.get().rum?.applicationId,
            "existing-application-id",
            "Existing cache must be preserved after decoding error"
        )
        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "Existing file must be preserved after decoding error")
    }

    func testInitSyncDiskWriteFailureReturnsFailure() {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let missingDir = Directory(url: URL(fileURLWithPath: "/no/such/path/"))
        let rc = RemoteConfigurationProvider(
            id: "test-id",
            site: .us1,
            directory: missingDir,
            httpClient: httpClient,
            notificationCenter: NotificationCenter()
        )

        let expectation = expectation(description: "sync fails")
        rc.start { result in
            if case .failure(.diskError) = result {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        guard case .failure(.diskError) = rc.cache else {
            return XCTFail("Cache must remain .failure after disk write error")
        }
    }

    // MARK: ETag

    func testInitSyncStoresETagAfterSuccessfulFetch() {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "abc123"])!, Data("{}".utf8))
        }
        let provider = makeProvider()

        let expectation = expectation(description: "etag is stored")
        let etagFileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.etag")
        wait(until: {
            (try? String(data: Data(contentsOf: etagFileURL), encoding: .utf8)) == "abc123"
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        let storedETag = try? String(data: Data(contentsOf: etagFileURL), encoding: .utf8)
        XCTAssertEqual(storedETag, "abc123")
        withExtendedLifetime(provider) {}
    }

    func testInitSyncDeletesStaleETagWhenResponseHasNoETag() throws {
        // Given — a stale ETag file from a previous fetch
        try Data("old-etag".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.etag"),
            options: .atomic
        )

        // When — server returns 200 with new data but no ETag header
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let provider = makeProvider()

        // Then — stale ETag file must be deleted so it is never sent as If-None-Match
        let expectation = expectation(description: "stale etag is deleted")
        let etagFileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.etag")
        wait(until: {
            !FileManager.default.fileExists(atPath: etagFileURL.path)
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: etagFileURL.path),
            "Stale ETag must be deleted when 200 response carries no ETag"
        )
        withExtendedLifetime(provider) {}
    }

    func testInitSyncDoesNotSendIfNoneMatchWhenCacheIsFailure() throws {
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

        let provider = makeProvider()
        let expectation = expectation(description: "request is sent")
        wait(until: {
            capturedRequest != nil
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        XCTAssertNil(
            capturedRequest?.value(forHTTPHeaderField: "If-None-Match"),
            "Must not send If-None-Match when cache is .failure — a 304 would leave us with no data"
        )
        withExtendedLifetime(provider) {}
    }

    func testInitSyncSendsIfNoneMatchHeaderWhenETagStored() throws {
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

        let provider = makeProvider()
        let expectation = expectation(description: "request is sent")
        wait(until: {
            capturedRequest != nil
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "If-None-Match"), "abc123")
        withExtendedLifetime(provider) {}
    }

    func test304ResponsePreservesCache() throws {
        // Given — pre-populate cache
        let existing = remoteConfigurationData(applicationID: "existing-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)
        let requestExpectation = expectation(description: "request completes")

        MockURLProtocol.requestHandler = { request in
            requestExpectation.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, nil as Data?)
        }
        let rc = makeProvider()
        wait(for: [requestExpectation], timeout: 2)

        XCTAssertEqual(try? rc.cache.get().rum?.applicationId, "existing-application-id", "Cache must be unchanged after 304")
        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "File must be unchanged after 304")
    }

    func test304ResponseWithoutCacheReturnsHTTPError() {
        let rc = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 304)), start: false)

        let expectation = expectation(description: "sync returns http error")
        rc.start { result in
            if case .failure(.httpError(304)) = result {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        guard case .failure(.diskError) = rc.cache else {
            return XCTFail("Cache must remain .failure when 304 is returned without existing cache")
        }
    }

#if canImport(UIKit)
    func testWillEnterForegroundSyncsRemoteConfiguration() {
        let notificationCenter = NotificationCenter()
        let initialPayload = remoteConfigurationData(applicationID: "initial-application-id")
        let foregroundPayload = remoteConfigurationData(applicationID: "foreground-application-id")
        let requestLock = NSLock()
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            let payload = requestCount == 1 ? initialPayload : foregroundPayload
            requestLock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeProvider(notificationCenter: notificationCenter)
        waitForCache(in: rc, applicationID: "initial-application-id", fileData: initialPayload)

        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        waitForCache(in: rc, applicationID: "foreground-application-id", fileData: foregroundPayload)
    }

    func testWillEnterForegroundDoesNotCallStartCompletionAgain() {
        let notificationCenter = NotificationCenter()
        let initialPayload = remoteConfigurationData(applicationID: "initial-application-id")
        let foregroundPayload = remoteConfigurationData(applicationID: "foreground-application-id")
        let requestLock = NSLock()
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            let payload = requestCount == 1 ? initialPayload : foregroundPayload
            requestLock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }

        let completionLock = NSLock()
        var completionCount = 0
        let startCompletion = expectation(description: "start completion is called")
        let rc = makeProvider(notificationCenter: notificationCenter, start: false)
        rc.start { _ in
            completionLock.lock()
            completionCount += 1
            let count = completionCount
            completionLock.unlock()

            if count == 1 {
                startCompletion.fulfill()
            }
        }
        wait(for: [startCompletion], timeout: 2)
        waitForCache(in: rc, applicationID: "initial-application-id", fileData: initialPayload)

        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        waitForCache(in: rc, applicationID: "foreground-application-id", fileData: foregroundPayload)

        XCTAssertEqual(completionLock.withLock { completionCount }, 1)
    }

#endif

    func testDifferentIDsUseDifferentFiles() throws {
        let payload1 = remoteConfigurationData(applicationID: "application-id-one")
        let payload2 = remoteConfigurationData(applicationID: "application-id-two")

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload1)
        }
        let rc1 = makeProvider(id: "id-one")
        waitForCache(in: rc1, applicationID: "application-id-one", fileData: payload1, fileName: "id-one.json")

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload2)
        }
        let rc2 = makeProvider(id: "id-two")
        waitForCache(in: rc2, applicationID: "application-id-two", fileData: payload2, fileName: "id-two.json")

        XCTAssertEqual(try? makeProvider(id: "id-one", httpClient: NeverHTTPClient()).cache.get().rum?.applicationId, "application-id-one")
        XCTAssertEqual(try? makeProvider(id: "id-two", httpClient: NeverHTTPClient()).cache.get().rum?.applicationId, "application-id-two")
    }
}
