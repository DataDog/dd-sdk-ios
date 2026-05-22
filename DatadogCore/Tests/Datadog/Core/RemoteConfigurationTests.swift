/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

// MARK: - Tests

class RemoteConfigurationTests: XCTestCase {
    private var coreDir: CoreDirectory! // swiftlint:disable:this implicitly_unwrapped_optional
    private var session: URLSession?

    override func setUp() {
        super.setUp()
        coreDir = temporaryUniqueCoreDirectory()
        coreDir.create()
        session = mockSession()
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        session?.invalidateAndCancel()
        session = nil
        coreDir.delete()
        super.tearDown()
    }

    // MARK: endpoint(for:host:)

    func testEndpointBuildsCorrectURL() {
        let url = RemoteConfigurationSynchronizer.endpoint(for: "abc-123", host: "sdk-configuration.browser-intake-datadoghq.com")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/abc-123.json")
    }

    func testEndpointPercentEncodesSpacesInID() {
        let url = RemoteConfigurationSynchronizer.endpoint(for: "hello world", host: "sdk-configuration.browser-intake-datadoghq.com")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/hello%20world.json")
    }

    func testEndpointEncodesSlashSoItDoesNotProduceExtraPathSegments() {
        let url = RemoteConfigurationSynchronizer.endpoint(for: "a/b", host: "sdk-configuration.browser-intake-datadoghq.com")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/a%2Fb.json")
    }

    func testEndpointEncodesQuestionMarkSoItDoesNotProduceQueryString() {
        let url = RemoteConfigurationSynchronizer.endpoint(for: "id?query", host: "sdk-configuration.browser-intake-datadoghq.com")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/id%3Fquery.json")
    }

    func testEndpointEncodesHashSoItDoesNotProduceFragment() {
        let url = RemoteConfigurationSynchronizer.endpoint(for: "id#section", host: "sdk-configuration.browser-intake-datadoghq.com")
        XCTAssertEqual(url?.absoluteString, "https://sdk-configuration.browser-intake-datadoghq.com/v1/id%23section.json")
    }

    // MARK: Init

    func testInitCreatesCacheForGivenID() {
        let rc = RemoteConfigurationSynchronizer(id: "abc", directory: coreDir.coreDirectory)
        // Cache is created — no data yet on first launch, no error either.
        XCTAssertNil(rc.cache.data)
        XCTAssertNil(rc.cache.loadError)
    }

    // MARK: start()

    func testStartReportsLoadErrorViaTelemetry() throws {
        // Given — write a file then revoke read permission so the cache init fails to read it.
        let id = "error-id"
        let fileURL = coreDir.coreDirectory.url.appendingPathComponent("\(id).json")
        try Data("{\"v\":1}".utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path) }

        let rc = RemoteConfigurationSynchronizer(id: id, directory: coreDir.coreDirectory)
        XCTAssertNotNil(rc.cache.loadError, "Precondition: cache must have a loadError")

        // When
        let telemetry = TelemetryMock()
        rc.start(from: URL(string: "https://example.com")!, connectionProxyDictionary: nil, telemetry: telemetry, session: session)

        // Then
        XCTAssertTrue(
            telemetry.messages.contains {
                if case .error = $0 {
                    return true
                }
                return false
            },
            "start() must report the load error via telemetry"
        )
    }

    func testStartWithNoLoadErrorReportsNoTelemetryError() {
        // Given — fresh cache, no previous file on disk.
        // Return a successful response so the async fetch never reports an error regardless of timing.
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let rc = RemoteConfigurationSynchronizer(id: "clean-id", directory: coreDir.coreDirectory)
        XCTAssertNil(rc.cache.loadError, "Precondition: no load error expected")

        // When
        let telemetry = TelemetryMock()
        rc.start(from: URL(string: "https://example.com")!, connectionProxyDictionary: nil, telemetry: telemetry, session: session)

        // Then — no telemetry error from the load path
        XCTAssertFalse(
            telemetry.messages.contains {
                if case .error = $0 {
                    return true
                }
                return false
            },
            "start() must not report a telemetry error when there is no load error"
        )
    }

    func testStartFetchesAndPopulatesCache() {
        // Given
        let payload = Data("{\"session_sample_rate\":50}".utf8)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }
        let rc = RemoteConfigurationSynchronizer(id: "fetch-id", directory: coreDir.coreDirectory)
        let expectation = expectation(description: "fetch completes")

        // When
        rc.start(
            from: URL(string: "https://example.com")!,
            connectionProxyDictionary: nil,
            telemetry: TelemetryMock(),
            session: session,
            didComplete: { expectation.fulfill() }
        )
        wait(for: [expectation], timeout: 2)

        // Then — the fetched payload must be written to cache
        XCTAssertEqual(rc.cache.data, payload, "cache.data must be populated after a successful fetch")
    }
}
