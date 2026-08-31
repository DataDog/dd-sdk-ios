/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

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

    override func setUp() {
        super.setUp()
        coreDir = temporaryUniqueCoreDirectory()
        coreDir.create()
    }

    override func tearDown() {
        coreDir.delete()
        super.tearDown()
    }

    private func makeProvider(
        id: String = "test-id",
        httpClient: HTTPClient = HTTPClientMock(),
        notificationCenter: NotificationCenter = NotificationCenter(),
        dateProvider: DateProvider = SystemDateProvider(),
        start: Bool = true
    ) -> RemoteConfigurationProvider {
        let provider = RemoteConfigurationProvider(
            id: id,
            site: .us1,
            directory: coreDir.coreDirectory,
            httpClient: httpClient,
            notificationCenter: notificationCenter,
            dateProvider: dateProvider
        )
        if start {
            provider.start { _ in }
        }
        return provider
    }

    /// Raw CDN response payload for a remote configuration fetch.
    private func remoteConfigurationData(applicationID: String = "application-id") -> Data {
        Data("{\"rum\":{\"applicationId\":\"\(applicationID)\"}}".utf8)
    }

    /// Encodes a `RemoteConfigurationCache` as it would be persisted on disk, for pre-seeding
    /// the cache file in tests.
    private func cacheData(
        etag: String? = nil,
        versionId: String? = nil,
        lastModified: Date? = nil,
        lastSynced: Date? = nil,
        syncId: String? = nil,
        firstApplied: Date? = nil,
        applicationID: String? = nil
    ) throws -> Data {
        let metadata: RemoteConfigurationCache.Metadata? = versionId != nil || lastModified != nil || lastSynced != nil || syncId != nil || firstApplied != nil
            ? RemoteConfigurationCache.Metadata(versionId: versionId, lastModified: lastModified, lastSynced: lastSynced, syncId: syncId, firstApplied: firstApplied)
            : nil
        let configurationData = try applicationID.map { try JSONEncoder().encode(RemoteConfiguration(rum: .init(applicationId: $0))) }
        return try JSONEncoder().encode(RemoteConfigurationCache(etag: etag, metadata: metadata, configurationData: configurationData))
    }

    private func readCache(fileName: String = "test-id.json") -> RemoteConfigurationCache? {
        guard let data = try? Data(contentsOf: coreDir.coreDirectory.url.appendingPathComponent(fileName)) else {
            return nil
        }
        return try? JSONDecoder().decode(RemoteConfigurationCache.self, from: data)
    }

    /// Decodes the `RemoteConfiguration` cached under `fileName`, re-decoding `configurationData`
    /// fresh on every call, matching how `RemoteConfigurationProvider.readCache` reads the cache.
    private func readConfiguration(fileName: String = "test-id.json") -> RemoteConfiguration? {
        guard let data = readCache(fileName: fileName)?.configurationData else {
            return nil
        }
        return try? JSONDecoder().decode(RemoteConfiguration.self, from: data)
    }

    private func waitForPersistedConfiguration(
        applicationID: String,
        fileName: String = "test-id.json"
    ) {
        let expectation = expectation(description: "remote configuration is persisted")
        wait(until: {
            self.readConfiguration(fileName: fileName)?.rum?.applicationId == applicationID
        }, andThenFulfill: expectation)
        wait(for: [expectation], timeout: 2)
    }

    private func waitForTelemetryError(_ telemetry: TelemetryMock, messagePrefix: String) {
        let expectation = expectation(description: "telemetry error '\(messagePrefix)' is reported")
        wait(until: {
            telemetry.messages.contains {
                $0.asError?.message.hasPrefix(messagePrefix) == true
            }
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
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try cacheData(applicationID: "cached-application-id").write(to: fileURL, options: .atomic)

        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let expectation = expectation(description: "cached remote configuration is returned")

        rc.start { remoteConfiguration in
            if remoteConfiguration.rum?.applicationId == "cached-application-id" {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        withExtendedLifetime(rc) {}
    }

    func testStartReportsTelemetryErrorWhenCachedFileCannotBeRead() throws {
        try FileManager.default.createDirectory(
            at: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            withIntermediateDirectories: false
        )
        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let telemetry = TelemetryMock()

        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to read cached remote configuration")
        withExtendedLifetime(rc) {}
    }

    func testStartReportsTelemetryErrorWhenCachedFileCannotBeDecoded() throws {
        try Data("this is not json".utf8).write(
            to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            options: .atomic
        )
        let rc = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let telemetry = TelemetryMock()

        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to read cached remote configuration")
        withExtendedLifetime(rc) {}
    }

    // MARK: Initial sync

    func testInitSyncReturnsSuccessAndPersistsConfiguration() {
        let payload = remoteConfigurationData(applicationID: "fetched-application-id")
        let rc = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: payload))

        waitForPersistedConfiguration(applicationID: "fetched-application-id")
        withExtendedLifetime(rc) {}
    }

    func testInitSyncPersistsConfigurationAcrossInstances() throws {
        let payload = remoteConfigurationData(applicationID: "persisted-application-id")
        let rc = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: payload))
        waitForPersistedConfiguration(applicationID: "persisted-application-id")

        let cachedProvider = makeProvider(httpClient: NeverHTTPClient(), start: false)
        let expectation = expectation(description: "persisted remote configuration is returned")
        cachedProvider.start { remoteConfiguration in
            if remoteConfiguration.rum?.applicationId == "persisted-application-id" {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        withExtendedLifetime(rc) {}
        withExtendedLifetime(cachedProvider) {}
    }

    func testInitSyncNetworkErrorReportsTelemetryAndLeavesNoPersistedConfiguration() {
        let telemetry = TelemetryMock()
        let rc = makeProvider(httpClient: HTTPClientMock(error: URLError(.networkConnectionLost)), start: false)

        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to sync remote configuration")

        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        withExtendedLifetime(rc) {}
    }

    func testInitSyncNon2xxReportsTelemetryAndPreservesPersistedConfiguration() throws {
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try cacheData(applicationID: "existing-application-id").write(to: fileURL, options: .atomic)

        let telemetry = TelemetryMock()
        let rc = makeProvider(httpClient: HTTPClientMock(responseCode: 500), start: false)
        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to sync remote configuration")

        XCTAssertEqual(readConfiguration()?.rum?.applicationId, "existing-application-id", "Existing configuration must be preserved after non-2xx")
        withExtendedLifetime(rc) {}
    }

    func testInitSyncEmptyBodyReportsTelemetryAndLeavesNoPersistedConfiguration() {
        let telemetry = TelemetryMock()
        let rc = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: Data()), start: false)

        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to sync remote configuration")

        XCTAssertNil(readCache()?.configurationData, "An empty response body must never be cached as a configuration")
        withExtendedLifetime(rc) {}
    }

    func testInitSyncInvalidJSONBodyReportsTelemetryAndPreservesPersistedConfiguration() throws {
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try cacheData(applicationID: "existing-application-id").write(to: fileURL, options: .atomic)

        let telemetry = TelemetryMock()
        let nonJSON = Data("this is not json".utf8)
        let rc = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: nonJSON), start: false)
        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to sync remote configuration")

        XCTAssertEqual(readConfiguration()?.rum?.applicationId, "existing-application-id", "Existing configuration must be preserved after decoding error")
        withExtendedLifetime(rc) {}
    }

    func testInitSyncDiskWriteFailureReportsTelemetry() {
        let missingDir = Directory(url: URL(fileURLWithPath: "/no/such/path/"))
        let rc = RemoteConfigurationProvider(
            id: "test-id",
            site: .us1,
            directory: missingDir,
            httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: Data("{}".utf8)),
            notificationCenter: NotificationCenter()
        )
        let telemetry = TelemetryMock()

        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to sync remote configuration")
    }

    // MARK: ETag persistence

    func testInitSyncPersistsETagAfterSuccessfulFetch() {
        let response = HTTPURLResponse(
            url: URL(string: "https://sdk-configuration.browser-intake-datadoghq.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["ETag": "abc123"]
        )!
        let provider = makeProvider(httpClient: HTTPClientMock(response: response, data: Data("{}".utf8)))

        let expectation = expectation(description: "etag is stored in cache")
        wait(until: {
            self.readCache()?.etag == "abc123"
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        withExtendedLifetime(provider) {}
    }

    func testInitSyncPersistsETagEvenWhenBodyCannotBeDecoded() {
        let response = HTTPURLResponse(
            url: URL(string: "https://sdk-configuration.browser-intake-datadoghq.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["ETag": "abc123"]
        )!
        let telemetry = TelemetryMock()
        let rc = makeProvider(httpClient: HTTPClientMock(response: response, data: Data("this is not json".utf8)), start: false)
        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to sync remote configuration")

        XCTAssertEqual(readCache()?.etag, "abc123", "ETag must be persisted from the response even when the body cannot be decoded")
        withExtendedLifetime(rc) {}
    }

    func testInitSyncOverwritesStaleETagWhenResponseHasNoETag() throws {
        // Given — a stale etag from a previous fetch
        try cacheData(etag: "old-etag")
            .write(to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"), options: .atomic)

        // When — server returns 200 with new data but no ETag header
        let provider = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: Data("{}".utf8)))

        // Then — the stale etag must be overwritten so it is never sent as If-None-Match again
        let expectation = expectation(description: "stale etag is cleared")
        wait(until: {
            self.readCache()?.etag == nil
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        withExtendedLifetime(provider) {}
    }

    func testInitSyncSendsIfNoneMatchWhenETagStoredEvenWithoutConfiguration() throws {
        // Given — a cache with an ETag but no configuration. This happens when a previous fetch
        // returned a payload we could not decode: we keep its ETag on purpose so we can skip
        // re-downloading the known-bad payload.
        try cacheData(etag: "abc123")
            .write(to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"), options: .atomic)

        let httpClient = HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: Data("{}".utf8))
        let provider = makeProvider(httpClient: httpClient)
        let expectation = expectation(description: "request is sent")
        wait(until: {
            !httpClient.requestsSent().isEmpty
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        XCTAssertEqual(
            httpClient.requestsSent().first?.value(forHTTPHeaderField: "If-None-Match"),
            "abc123",
            "If-None-Match must be sent whenever an ETag is stored, so a known-bad payload is not re-fetched"
        )
        withExtendedLifetime(provider) {}
    }

    func testInitSyncSendsIfNoneMatchHeaderWhenETagStored() throws {
        try cacheData(etag: "abc123")
            .write(to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"), options: .atomic)

        let httpClient = HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: Data("{}".utf8))
        let provider = makeProvider(httpClient: httpClient)
        let expectation = expectation(description: "request is sent")
        wait(until: {
            !httpClient.requestsSent().isEmpty
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        XCTAssertEqual(httpClient.requestsSent().first?.value(forHTTPHeaderField: "If-None-Match"), "abc123")
        withExtendedLifetime(provider) {}
    }

    func testSyncReportsTelemetryErrorWhenCachedFileCannotBeRead() throws {
        try FileManager.default.createDirectory(
            at: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"),
            withIntermediateDirectories: false
        )
        let telemetry = TelemetryMock()
        let httpClient = HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: Data("{}".utf8))
        let rc = makeProvider(httpClient: httpClient, start: false)
        rc.start({ _ in }, telemetry: telemetry)

        waitForTelemetryError(telemetry, messagePrefix: "[RemoteConfig] Failed to read cached metadata etag")
        withExtendedLifetime(rc) {}
    }

    func test304ResponsePreservesCache() throws {
        // Given — pre-populate persisted configuration
        let existing = try cacheData(applicationID: "existing-application-id")
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("test-id.json")
        try existing.write(to: fileURL, options: .atomic)

        let httpClient = HTTPClientMock(response: .mockResponseWith(statusCode: 304))

        // completion is called once synchronously from cache; NOT again after CDN 304
        let cacheExpectation = expectation(description: "cached config returned once from start")
        let rc = makeProvider(httpClient: httpClient, start: false)
        rc.start { config in
            if config.rum?.applicationId == "existing-application-id" {
                cacheExpectation.fulfill()
            }
        }

        let requestExpectation = expectation(description: "CDN request is sent")
        wait(until: {
            !httpClient.requestsSent().isEmpty
        }, andThenFulfill: requestExpectation)

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
        let httpClient = HTTPClientMock { _ in
            requestLock.lock()
            defer { requestLock.unlock() }
            requestCount += 1
            let payload = requestCount == 1 ? initialPayload : foregroundPayload
            return .success((.mockResponseWith(statusCode: 200), payload))
        }
        let rc = makeProvider(httpClient: httpClient, notificationCenter: notificationCenter, dateProvider: dateProvider)
        waitForPersistedConfiguration(applicationID: "initial-application-id")

        // Advance past TTL so the foreground sync is not suppressed
        dateProvider.advance(bySeconds: 360)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        waitForPersistedConfiguration(applicationID: "foreground-application-id")
        withExtendedLifetime(rc) {}
    }

    func testWillEnterForegroundCallsCompletionAgain() {
        let notificationCenter = NotificationCenter()
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0)
        let initialPayload = remoteConfigurationData(applicationID: "initial-application-id")
        let foregroundPayload = remoteConfigurationData(applicationID: "foreground-application-id")
        let requestLock = NSLock()
        var requestCount = 0
        let httpClient = HTTPClientMock { _ in
            requestLock.lock()
            defer { requestLock.unlock() }
            requestCount += 1
            let payload = requestCount == 1 ? initialPayload : foregroundPayload
            return .success((.mockResponseWith(statusCode: 200), payload))
        }

        let completionExpectation = expectation(description: "completion is called for each sync")
        completionExpectation.expectedFulfillmentCount = 2
        let rc = makeProvider(httpClient: httpClient, notificationCenter: notificationCenter, dateProvider: dateProvider, start: false)
        rc.start { _ in
            completionExpectation.fulfill()
        }
        waitForPersistedConfiguration(applicationID: "initial-application-id")

        // Advance past TTL so the foreground sync is not suppressed
        dateProvider.advance(bySeconds: 360)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)
        waitForPersistedConfiguration(applicationID: "foreground-application-id")

        wait(for: [completionExpectation], timeout: 2)
        withExtendedLifetime(rc) {}
    }

    func testForegroundSyncsWhenLastSyncDateIsNil() {
        // Given — init sync fails, lastSyncDate stays nil
        let notificationCenter = NotificationCenter()
        let foregroundPayload = remoteConfigurationData(applicationID: "foreground-application-id")
        var didFailInitialSync = false
        let httpClient = HTTPClientMock { _ in
            // Invoked on the mock's serial queue, so this state needs no lock.
            // Fail the first (init) sync so lastSyncDate stays nil, then succeed.
            guard didFailInitialSync else {
                didFailInitialSync = true
                return .failure(URLError(.networkConnectionLost))
            }
            return .success((.mockResponseWith(statusCode: 200), foregroundPayload))
        }
        let rc = makeProvider(httpClient: httpClient, notificationCenter: notificationCenter)

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
        var servedInitial = false
        let httpClient = HTTPClientMock { _ in
            // Invoked on the mock's serial queue, so this state needs no lock.
            guard servedInitial else {
                servedInitial = true
                return .success((.mockResponseWith(statusCode: 200), initialPayload))
            }
            return .success((.mockResponseWith(statusCode: 200), foregroundPayload))
        }
        let rc = makeProvider(httpClient: httpClient, notificationCenter: notificationCenter, dateProvider: dateProvider)
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
        let httpClient = HTTPClientMock { _ in
            .success((.mockResponseWith(statusCode: 200), initialPayload))
        }
        let rc = makeProvider(httpClient: httpClient, notificationCenter: notificationCenter, dateProvider: dateProvider)
        waitForPersistedConfiguration(applicationID: "initial-application-id")

        let countAfterInit = httpClient.requestsSent().count

        // When — only 1 minute passes and foreground fires
        dateProvider.advance(bySeconds: 60)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        // Then — no additional sync fires within TTL
        let noSyncExpectation = expectation(description: "no foreground sync within TTL")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(httpClient.requestsSent().count, countAfterInit, "No sync should fire within TTL")
            noSyncExpectation.fulfill()
        }
        waitForExpectations(timeout: 2)
        withExtendedLifetime(rc) {}
    }

    func testForegroundDoesNotSyncAfter304WithinTTL() throws {
        // Given — init sync returns 304, TTL not elapsed
        let notificationCenter = NotificationCenter()
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0)
        try cacheData(applicationID: "cached-application-id")
            .write(to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"), options: .atomic)
        let httpClient = HTTPClientMock { _ in
            .success((.mockResponseWith(statusCode: 304), nil))
        }
        let rc = makeProvider(httpClient: httpClient, notificationCenter: notificationCenter, dateProvider: dateProvider)

        // Wait for init sync (304)
        let initExpectation = expectation(description: "init sync completes")
        wait(until: { httpClient.requestsSent().count == 1 }, andThenFulfill: initExpectation)
        waitForExpectations(timeout: 2)

        // When — foreground fires within TTL
        dateProvider.advance(bySeconds: 60)
        notificationCenter.post(name: ApplicationNotifications.willEnterForeground, object: nil)

        // Then — no additional request fires
        let noSyncExpectation = expectation(description: "no foreground sync after 304 within TTL")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(httpClient.requestsSent().count, 1, "No sync should fire within TTL after 304")
            noSyncExpectation.fulfill()
        }
        waitForExpectations(timeout: 2)
        withExtendedLifetime(rc) {}
    }

#endif

    func testDifferentIDsUseDifferentFiles() throws {
        let payload1 = remoteConfigurationData(applicationID: "application-id-one")
        let payload2 = remoteConfigurationData(applicationID: "application-id-two")

        let rc1 = makeProvider(id: "id-one", httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: payload1))
        waitForPersistedConfiguration(applicationID: "application-id-one", fileName: "id-one.json")

        let rc2 = makeProvider(id: "id-two", httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: payload2))
        waitForPersistedConfiguration(applicationID: "application-id-two", fileName: "id-two.json")

        let cachedProvider1 = makeProvider(id: "id-one", httpClient: NeverHTTPClient(), start: false)
        let cachedProvider2 = makeProvider(id: "id-two", httpClient: NeverHTTPClient(), start: false)
        let expectation1 = expectation(description: "first cached configuration is returned")
        let expectation2 = expectation(description: "second cached configuration is returned")

        cachedProvider1.start { remoteConfiguration in
            if remoteConfiguration.rum?.applicationId == "application-id-one" {
                expectation1.fulfill()
            }
        }
        cachedProvider2.start { remoteConfiguration in
            if remoteConfiguration.rum?.applicationId == "application-id-two" {
                expectation2.fulfill()
            }
        }
        waitForExpectations(timeout: 2)

        withExtendedLifetime(rc1) {}
        withExtendedLifetime(rc2) {}
        withExtendedLifetime(cachedProvider1) {}
        withExtendedLifetime(cachedProvider2) {}
    }

    // MARK: Configuration telemetry

    func testGenuineFetchPersistsSyncIdAndLastSyncedWithoutFirstApplied() {
        let response = HTTPURLResponse(
            url: URL(string: "https://sdk-configuration.browser-intake-datadoghq.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["x-amz-version-id": "v1", "last-modified": "Mon, 01 Jan 2026 00:00:00 GMT"]
        )!
        let provider = makeProvider(httpClient: HTTPClientMock(response: response, data: Data("{}".utf8)))

        let expectation = expectation(description: "metadata is persisted with syncId and lastSynced")
        wait(until: {
            let metadata = self.readCache()?.metadata
            return metadata?.syncId != nil && metadata?.lastSynced != nil
        }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        XCTAssertNil(readCache()?.metadata?.firstApplied, "A freshly fetched version has not been applied yet")
        withExtendedLifetime(provider) {}
    }

    func testNoTelemetryIsReportedWhenNothingWasCached() {
        let telemetry = TelemetryMock()
        let payload = remoteConfigurationData(applicationID: "fetched-application-id")
        let provider = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 200), data: payload), start: false)

        provider.start({ _ in }, telemetry: telemetry)
        waitForPersistedConfiguration(applicationID: "fetched-application-id")

        XCTAssertNil(telemetry.messages.firstConfiguration(), "Nothing was applied from cache on first launch, so nothing should be reported")
        withExtendedLifetime(provider) {}
    }

    func testCachedVersionIsReportedOnConfigurationTelemetryWithFirstAppliedStamped() throws {
        let lastModified = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
        let lastSynced = Date(timeIntervalSince1970: 1_767_312_000) // 2026-01-02T00:00:00Z
        try cacheData(
            versionId: "v1",
            lastModified: lastModified,
            lastSynced: lastSynced,
            syncId: "sync-1",
            applicationID: "cached-application-id"
        )
        .write(to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"), options: .atomic)

        let telemetry = TelemetryMock()
        let provider = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 304)), start: false)

        provider.start({ _ in }, telemetry: telemetry)

        let expectation = expectation(description: "configuration telemetry is reported")
        wait(until: { telemetry.messages.firstConfiguration()?.remoteConfiguration != nil }, andThenFulfill: expectation)
        waitForExpectations(timeout: 2)

        let reported = try XCTUnwrap(telemetry.messages.firstConfiguration()?.remoteConfiguration)
        XCTAssertEqual(reported.configId, "test-id")
        XCTAssertEqual(reported.versionId, "v1")
        XCTAssertEqual(reported.lastModified, lastModified)
        XCTAssertEqual(reported.lastSynced, lastSynced)
        XCTAssertEqual(reported.syncId, "sync-1")
        XCTAssertNotNil(reported.firstApplied, "firstApplied must be stamped the first time this version is observed as applied")
        withExtendedLifetime(provider) {}
    }

    func testFirstAppliedIsStampedOnceAndReusedAcrossSessions() throws {
        try cacheData(versionId: "v1", syncId: "sync-1", applicationID: "cached-application-id")
            .write(to: coreDir.coreDirectory.url.appendingPathComponent("test-id.json"), options: .atomic)

        let firstSessionTelemetry = TelemetryMock()
        let firstSession = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 304)), start: false)
        firstSession.start({ _ in }, telemetry: firstSessionTelemetry)

        let firstExpectation = expectation(description: "first session reports configuration telemetry")
        wait(until: { firstSessionTelemetry.messages.firstConfiguration()?.remoteConfiguration != nil }, andThenFulfill: firstExpectation)
        waitForExpectations(timeout: 2)
        let firstApplied = try XCTUnwrap(firstSessionTelemetry.messages.firstConfiguration()?.remoteConfiguration?.firstApplied)

        let secondSessionTelemetry = TelemetryMock()
        let secondSession = makeProvider(httpClient: HTTPClientMock(response: .mockResponseWith(statusCode: 304)), start: false)
        secondSession.start({ _ in }, telemetry: secondSessionTelemetry)

        let secondExpectation = expectation(description: "second session reports configuration telemetry")
        wait(until: { secondSessionTelemetry.messages.firstConfiguration()?.remoteConfiguration != nil }, andThenFulfill: secondExpectation)
        waitForExpectations(timeout: 2)
        let secondFirstApplied = try XCTUnwrap(secondSessionTelemetry.messages.firstConfiguration()?.remoteConfiguration?.firstApplied)

        XCTAssertEqual(firstApplied, secondFirstApplied, "firstApplied must be stable across sessions running on the same version")
        withExtendedLifetime(firstSession) {}
        withExtendedLifetime(secondSession) {}
    }
}
