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
        dateProvider: DateProvider = SystemDateProvider(),
        start: Bool = true
    ) -> RemoteConfigurationProvider {
        let provider = RemoteConfigurationProvider(
            id: id,
            site: .us1,
            directory: coreDir.coreDirectory,
            httpClient: httpClient ?? self.httpClient,
            notificationCenter: notificationCenter,
            dateProvider: dateProvider
        )
        if start {
            provider.start { _ in }
        }
        return provider
    }

    private func remoteConfigurationData(applicationID: String = "application-id") -> Data {
        Data("{\"rum\":{\"applicationId\":\"\(applicationID)\"}}".utf8)
    }

    private func waitForPersistedConfiguration(
        applicationID: String,
        fileData: Data? = nil,
        fileName: String = "test-id.json"
    ) {
        let expectation = expectation(description: "remote configuration is persisted")
        wait(until: {
            let fileURL = self.coreDir.coreDirectory.url.appendingPathComponent(fileName)
            guard let persistedData = try? Data(contentsOf: fileURL),
                  (try? JSONDecoder().decode(RemoteConfiguration.self, from: persistedData).rum?.applicationId) == applicationID else {
                return false
            }

            guard let fileData else {
                return true
            }

            return persistedData == fileData
        }, andThenFulfill: expectation)
        wait(for: [expectation], timeout: 2)
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

    func testStartDoesNotReadCacheOnFirstLaunch() {
        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let expectation = expectation(description: "completion is not called without cache or network response")
        expectation.isInverted = true

        rc.start { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 0.1)

        withExtendedLifetime(rc) {}
    }

    func testStartReadsCacheFromPreviousLaunch() throws {
        let payload = remoteConfigurationData(applicationID: "cached-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try payload.write(to: fileURL, options: .atomic)

        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let expectation = expectation(description: "cached remote configuration is returned")

        rc.start { result in
            if case .success(let remoteConfiguration) = result,
               remoteConfiguration.rum?.applicationId == "cached-application-id" {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        withExtendedLifetime(rc) {}
    }

    func testStartDoesNotCallCompletionWhenNoFileExists() {
        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let expectation = expectation(description: "completion is not called when no cache exists")
        expectation.isInverted = true

        rc.start { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 0.1)

        withExtendedLifetime(rc) {}
    }

    func testStartReturnsFailureWhenFileCannotBeRead() throws {
        try FileManager.default.createDirectory(
            at: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            withIntermediateDirectories: false
        )

        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let expectation = expectation(description: "cache read failure is returned")

        rc.start { result in
            if case .failure(.diskError) = result {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        withExtendedLifetime(rc) {}
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
    }

    func testStartReturnsFailureWhenFileCannotBeDecoded() throws {
        try Data("this is not json".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            options: .atomic
        )

        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let expectation = expectation(description: "cache decoding failure is returned")

        rc.start { result in
            if case .failure(.decodingError) = result {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        withExtendedLifetime(rc) {}
    }

    // MARK: Initial sync

    func testInitSyncReturnsSuccessAndPersistsConfiguration() {
        let payload = remoteConfigurationData(applicationID: "fetched-application-id")
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeProvider()

        waitForPersistedConfiguration(applicationID: "fetched-application-id", fileData: payload)
        withExtendedLifetime(rc) {}
    }

    func testInitSyncPersistsConfigurationAcrossInstances() throws {
        let payload = remoteConfigurationData(applicationID: "persisted-application-id")
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = makeProvider()
        waitForPersistedConfiguration(applicationID: "persisted-application-id", fileData: payload)

        let cachedProvider = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let expectation = expectation(description: "persisted remote configuration is returned")
        cachedProvider.start { result in
            if case .success(let remoteConfiguration) = result,
               remoteConfiguration.rum?.applicationId == "persisted-application-id" {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        withExtendedLifetime(rc) {}
        withExtendedLifetime(cachedProvider) {}
    }

    func testInitSyncNetworkErrorReturnsFailureAndLeavesNoPersistedConfiguration() {
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

        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testInitSyncNon2xxReturnsFailureAndPreservesPersistedConfiguration() throws {
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

        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "Existing file must be preserved after non-2xx")
        withExtendedLifetime(rc) {}
    }

    func testInitSyncEmptyBodyReturnsFailureAndLeavesNoPersistedConfiguration() {
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

        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testInitSyncInvalidJSONBodyReturnsFailureAndPreservesPersistedConfiguration() throws {
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

        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "Existing file must be preserved after decoding error")
        withExtendedLifetime(rc) {}
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

    func testInitSyncDoesNotSendIfNoneMatchWhenPersistedConfigurationIsMissing() throws {
        // Given — ETag file exists but JSON configuration is missing.
        try Data("abc123".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.etag"),
            options: .atomic
        )
        // No .json file means a 304 response would leave the caller with no configuration.

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
            "Must not send If-None-Match when persisted configuration is missing — a 304 would leave us with no data"
        )
        withExtendedLifetime(provider) {}
    }

    func testInitSyncSendsIfNoneMatchHeaderWhenETagStored() throws {
        // Given — store an ETag from a previous fetch
        try Data("abc123".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.etag"),
            options: .atomic
        )

        // Pre-populate .json so persisted configuration is available (required to send If-None-Match)
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
        // Given — pre-populate persisted configuration
        let existing = remoteConfigurationData(applicationID: "existing-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)

        let requestExpectation = expectation(description: "CDN request is sent")
        MockURLProtocol.requestHandler = { request in
            requestExpectation.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, nil as Data?)
        }

        // completion is called once synchronously from cache; NOT again after CDN 304
        let cacheExpectation = expectation(description: "cached config returned once from start")
        let rc = makeProvider(start: false)
        rc.start { result in
            if case .success(let config) = result, config.rum?.applicationId == "existing-application-id" {
                cacheExpectation.fulfill()
            }
        }

        wait(for: [requestExpectation, cacheExpectation], timeout: 2)
        XCTAssertEqual(try? Data(contentsOf: fileURL), existing, "File must be unchanged after 304")
        withExtendedLifetime(rc) {}
    }

    func test304ResponseWithoutCacheDoesNotCallCompletion() {
        // Given — no persisted configuration, CDN returns 304 (unusual server-side scenario)
        let rc = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 304)), start: false)

        // No cache → no synchronous completion. CDN 304 → no completion either.
        let unexpectedCompletion = expectation(description: "completion should not be called")
        unexpectedCompletion.isInverted = true
        rc.start { _ in
            unexpectedCompletion.fulfill()
        }
        waitForExpectations(timeout: 0.5)

        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        withExtendedLifetime(rc) {}
    }

#if canImport(UIKit)
    func testWillEnterForegroundSyncsRemoteConfiguration() {
        let notificationCenter = NotificationCenter()
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0)
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
        let rc = makeProvider(notificationCenter: notificationCenter, dateProvider: dateProvider)
        waitForPersistedConfiguration(applicationID: "initial-application-id", fileData: initialPayload)

        // Advance past TTL so the foreground sync is not suppressed
        dateProvider.advance(bySeconds: 360)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        waitForPersistedConfiguration(applicationID: "foreground-application-id", fileData: foregroundPayload)
        withExtendedLifetime(rc) {}
    }

    func testWillEnterForegroundCallsCompletionAgain() {
        let notificationCenter = NotificationCenter()
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0)
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
        let completionExpectation = expectation(description: "completion is called for each sync")
        completionExpectation.expectedFulfillmentCount = 2
        let rc = makeProvider(notificationCenter: notificationCenter, dateProvider: dateProvider, start: false)
        rc.start { result in
            guard case .success = result else {
                return
            }

            completionLock.lock()
            completionCount += 1
            completionLock.unlock()

            completionExpectation.fulfill()
        }
        waitForPersistedConfiguration(applicationID: "initial-application-id", fileData: initialPayload)

        // Advance past TTL so the foreground sync is not suppressed
        dateProvider.advance(bySeconds: 360)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        waitForPersistedConfiguration(applicationID: "foreground-application-id", fileData: foregroundPayload)

        wait(for: [completionExpectation], timeout: 2)
        XCTAssertEqual(completionLock.withLock { completionCount }, 2)
        withExtendedLifetime(rc) {}
    }

    func testForegroundSyncsWhenLastSyncDateIsNil() {
        // Given — init sync fails, lastSyncDate stays nil
        let notificationCenter = NotificationCenter()
        let foregroundPayload = remoteConfigurationData(applicationID: "foreground-application-id")
        let requestLock = NSLock()
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            let count = requestCount
            requestLock.unlock()
            if count == 1 {
                throw URLError(.networkConnectionLost)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, foregroundPayload)
        }
        let rc = makeProvider(notificationCenter: notificationCenter)

        // When — foreground fires immediately after a failed init sync
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        // Then — sync fires because lastSyncDate is nil
        waitForPersistedConfiguration(applicationID: "foreground-application-id")
        withExtendedLifetime(rc) {}
    }

    func testForegroundSyncsWhenTTLElapsed() {
        // Given — init sync succeeds, then TTL elapses
        let notificationCenter = NotificationCenter()
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0)
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
        let rc = makeProvider(notificationCenter: notificationCenter, dateProvider: dateProvider)
        waitForPersistedConfiguration(applicationID: "initial-application-id")

        // When — TTL elapses and foreground fires
        dateProvider.advance(bySeconds: 360)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        // Then — sync fires
        waitForPersistedConfiguration(applicationID: "foreground-application-id")
        withExtendedLifetime(rc) {}
    }

    func testForegroundDoesNotSyncWhenTTLNotElapsed() {
        // Given — init sync succeeds, TTL not elapsed
        let notificationCenter = NotificationCenter()
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0)
        let initialPayload = remoteConfigurationData(applicationID: "initial-application-id")
        let requestLock = NSLock()
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            requestLock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, initialPayload)
        }
        let rc = makeProvider(notificationCenter: notificationCenter, dateProvider: dateProvider)
        waitForPersistedConfiguration(applicationID: "initial-application-id")

        let countAfterInit = requestLock.withLock { requestCount }

        // When — only 1 minute passes and foreground fires
        dateProvider.advance(bySeconds: 60)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        // Then — no additional sync fires within TTL
        let noSyncExpectation = expectation(description: "no foreground sync within TTL")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(requestLock.withLock { requestCount }, countAfterInit, "No sync should fire within TTL")
            noSyncExpectation.fulfill()
        }
        waitForExpectations(timeout: 2)
        withExtendedLifetime(rc) {}
    }

    func testForegroundDoesNotSyncAfter304WithinTTL() throws {
        // Given — init sync returns 304, TTL not elapsed
        let notificationCenter = NotificationCenter()
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0)
        let cachedPayload = remoteConfigurationData(applicationID: "cached-application-id")
        try cachedPayload.write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            options: .atomic
        )
        let requestLock = NSLock()
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestLock.lock()
            requestCount += 1
            requestLock.unlock()
            return (HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, nil)
        }
        let rc = makeProvider(notificationCenter: notificationCenter, dateProvider: dateProvider)

        // Wait for init sync (304)
        let initExpectation = expectation(description: "init sync completes")
        wait(until: { requestLock.withLock { requestCount } == 1 }, andThenFulfill: initExpectation)
        waitForExpectations(timeout: 2)

        // When — foreground fires within TTL
        dateProvider.advance(bySeconds: 60)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        // Then — no additional request fires
        let noSyncExpectation = expectation(description: "no foreground sync after 304 within TTL")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(requestLock.withLock { requestCount }, 1, "No sync should fire within TTL after 304")
            noSyncExpectation.fulfill()
        }
        waitForExpectations(timeout: 2)
        withExtendedLifetime(rc) {}
    }

#endif

    func testDifferentIDsUseDifferentFiles() throws {
        let payload1 = remoteConfigurationData(applicationID: "application-id-one")
        let payload2 = remoteConfigurationData(applicationID: "application-id-two")

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload1)
        }
        let rc1 = makeProvider(id: "id-one")
        waitForPersistedConfiguration(applicationID: "application-id-one", fileData: payload1, fileName: "id-one.json")

        MockURLProtocol.requestHandler = { _ in
            (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload2)
        }
        let rc2 = makeProvider(id: "id-two")
        waitForPersistedConfiguration(applicationID: "application-id-two", fileData: payload2, fileName: "id-two.json")

        let cachedProvider1 = makeProvider(id: "id-one", httpClient: NeverHTTPClient(), start: false)
        let cachedProvider2 = makeProvider(id: "id-two", httpClient: NeverHTTPClient(), start: false)
        let expectation1 = expectation(description: "first cached configuration is returned")
        let expectation2 = expectation(description: "second cached configuration is returned")

        cachedProvider1.start { result in
            if case .success(let remoteConfiguration) = result,
               remoteConfiguration.rum?.applicationId == "application-id-one" {
                expectation1.fulfill()
            }
        }
        cachedProvider2.start { result in
            if case .success(let remoteConfiguration) = result,
               remoteConfiguration.rum?.applicationId == "application-id-two" {
                expectation2.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        withExtendedLifetime(rc1) {}
        withExtendedLifetime(rc2) {}
        withExtendedLifetime(cachedProvider1) {}
        withExtendedLifetime(cachedProvider2) {}
    }
}
