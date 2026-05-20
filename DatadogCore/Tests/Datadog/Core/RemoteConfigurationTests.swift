/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
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

    // MARK: Init

    func testInitCreatesCacheForGivenID() {
        let rc = RemoteConfiguration(id: "abc", directory: coreDir.coreDirectory)
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

        let rc = RemoteConfiguration(id: id, directory: coreDir.coreDirectory)
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
        let rc = RemoteConfiguration(id: "clean-id", directory: coreDir.coreDirectory)
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
}
