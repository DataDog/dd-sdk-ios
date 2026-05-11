/*
 * Unless explicitly stated otherwise all files in this repository are licensed
 * under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore

// MARK: MockURLProtocol

private class MockURLProtocol: URLProtocol {
    /// Set this before each test to control what the mock returns.
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

// MARK: Helper

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func okResponse(for url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

private func errorResponse(for url: URL, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

// MARK: Tests

class RemoteConfigurationFetcherTests: XCTestCase {
    private var coreDir: CoreDirectory! // swiftlint:disable:this implicitly_unwrapped_optional
    private var cache: RemoteConfigurationCache! // swiftlint:disable:this implicitly_unwrapped_optional
    private let endpoint = URL(string: "https://example.com/remote-config")!

    override func setUp() {
        coreDir = temporaryUniqueCoreDirectory()
        coreDir.create()
        cache = RemoteConfigurationCache(directory: coreDir.coreDirectory)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        coreDir.delete()
    }

    // MARK: Success path

    func testSuccessfulFetchWritesToCache() {
        let payload = Data("{\"session_sample_rate\":50}".utf8)

        let expectedEndpoint = endpoint
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, expectedEndpoint)
            return (okResponse(for: request.url!), payload)
        }

        let telemetry = TelemetryMock()
        let expectation = expectation(description: "fetch completes")
        let fetcher = RemoteConfigurationFetcher(cache: cache, telemetry: telemetry, session: mockSession())

        fetcher.fetch(from: endpoint, didComplete: { expectation.fulfill() })
        wait(for: [expectation], timeout: 2)

        let freshCache = RemoteConfigurationCache(directory: coreDir.coreDirectory)
        XCTAssertEqual(freshCache.data, payload, "Cache must contain the CDN response")
        XCTAssertFalse(
            telemetry.messages.contains { if case .error = $0 { return true }; return false },
            "No telemetry errors expected on success"
        )
    }

    // MARK: Failure paths cache must not be overwritten

    func testNetworkErrorDoesNotOverwriteExistingCache() {
        let existing = Data("{\"v\":1}".utf8)
        cache.save(existing)

        MockURLProtocol.requestHandler = { _ in throw URLError(.networkConnectionLost) }

        let telemetry = TelemetryMock()
        let expectation = expectation(description: "fetch completes")
        let fetcher = RemoteConfigurationFetcher(cache: cache, telemetry: telemetry, session: mockSession())
        fetcher.fetch(from: endpoint, didComplete: { expectation.fulfill() })
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(
            RemoteConfigurationCache(directory: coreDir.coreDirectory).data,
            existing,
            "Existing cache must be preserved after a network error"
        )
        XCTAssertTrue(
            telemetry.messages.contains { if case .error = $0 { return true }; return false },
            "A telemetry error must be reported"
        )
    }

    func testNon2xxResponseDoesNotOverwriteExistingCache() {
        let existing = Data("{\"v\":1}".utf8)
        cache.save(existing)

        MockURLProtocol.requestHandler = { request in
            (errorResponse(for: request.url!, status: 500), nil)
        }

        let telemetry = TelemetryMock()
        let expectation = expectation(description: "fetch completes")
        let fetcher = RemoteConfigurationFetcher(cache: cache, telemetry: telemetry, session: mockSession())
        fetcher.fetch(from: endpoint, didComplete: { expectation.fulfill() })
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(RemoteConfigurationCache(directory: coreDir.coreDirectory).data, existing)
        XCTAssertTrue(
            telemetry.messages.contains { if case .error = $0 { return true }; return false },
            "A telemetry error must be reported"
        )
    }

    func testEmptyBodyDoesNotOverwriteExistingCache() {
        let existing = Data("{\"v\":1}".utf8)
        cache.save(existing)

        MockURLProtocol.requestHandler = { request in
            (okResponse(for: request.url!), Data())   // empty body
        }

        let telemetry = TelemetryMock()
        let expectation = expectation(description: "fetch completes")
        let fetcher = RemoteConfigurationFetcher(cache: cache, telemetry: telemetry, session: mockSession())
        fetcher.fetch(from: endpoint, didComplete: { expectation.fulfill() })
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(RemoteConfigurationCache(directory: coreDir.coreDirectory).data, existing)
        XCTAssertTrue(
            telemetry.messages.contains { if case .error = $0 { return true }; return false },
            "A telemetry error must be reported"
        )
    }

    func testInvalidJSONDoesNotOverwriteExistingCache() {
        let existing = Data("{\"v\":1}".utf8)
        cache.save(existing)

        MockURLProtocol.requestHandler = { request in
            (okResponse(for: request.url!), Data("this is not json".utf8))
        }

        let telemetry = TelemetryMock()
        let expectation = expectation(description: "fetch completes")
        let fetcher = RemoteConfigurationFetcher(cache: cache, telemetry: telemetry, session: mockSession())
        fetcher.fetch(from: endpoint, didComplete: { expectation.fulfill() })
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(RemoteConfigurationCache(directory: coreDir.coreDirectory).data, existing)
        XCTAssertTrue(
            telemetry.messages.contains { if case .error = $0 { return true }; return false },
            "A telemetry error must be reported"
        )
    }
}
