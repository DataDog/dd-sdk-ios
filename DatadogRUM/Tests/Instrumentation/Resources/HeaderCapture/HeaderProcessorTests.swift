/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

class HeaderProcessorTests: XCTestCase {
    // MARK: - Disabled Configuration

    func testWhenDisabled_itReturnsEmptyHeaders() {
        // Given
        let processor = HeaderProcessor(config: .disabled)

        // When
        let result = processor.process(
            requestHeaders: ["content-type": "application/json"],
            responseHeaders: ["content-type": "text/html"]
        )

        // Then
        XCTAssertTrue(result.request.isEmpty)
        XCTAssertTrue(result.response.isEmpty)
    }

    // MARK: - Defaults Configuration

    func testWhenDefaults_itCapturesDefaultRequestHeaders() {
        // Given
        let processor = HeaderProcessor(config: .defaults)

        // When
        let result = processor.process(
            requestHeaders: [
                "cache-control": "no-cache",
                "content-type": "application/json",
                "authorization": "Bearer secret",
                "accept": "text/html"
            ],
            responseHeaders: [:]
        )

        // Then
        XCTAssertEqual(result.request, [
            "cache-control": "no-cache",
            "content-type": "application/json"
        ])
    }

    func testWhenDefaults_itCapturesDefaultResponseHeaders() {
        // Given
        let processor = HeaderProcessor(config: .defaults)

        // When
        let result = processor.process(
            requestHeaders: [:],
            responseHeaders: [
                "cache-control": "max-age=3600",
                "etag": "\"abc123\"",
                "age": "120",
                "expires": "Thu, 01 Dec 2025 16:00:00 GMT",
                "content-type": "application/json",
                "content-encoding": "gzip",
                "content-length": "1024",
                "vary": "Accept-Encoding",
                "server-timing": "db;dur=53",
                "x-cache": "HIT",
                "x-custom-header": "should-not-appear",
                "set-cookie": "session=abc"
            ]
        )

        // Then
        XCTAssertEqual(result.response.count, 10)
        XCTAssertEqual(result.response["cache-control"], "max-age=3600")
        XCTAssertEqual(result.response["etag"], "\"abc123\"")
        XCTAssertEqual(result.response["age"], "120")
        XCTAssertEqual(result.response["expires"], "Thu, 01 Dec 2025 16:00:00 GMT")
        XCTAssertEqual(result.response["content-type"], "application/json")
        XCTAssertEqual(result.response["content-encoding"], "gzip")
        XCTAssertEqual(result.response["content-length"], "1024")
        XCTAssertEqual(result.response["vary"], "Accept-Encoding")
        XCTAssertEqual(result.response["server-timing"], "db;dur=53")
        XCTAssertEqual(result.response["x-cache"], "HIT")
        XCTAssertNil(result.response["x-custom-header"])
        XCTAssertNil(result.response["set-cookie"])
    }

    // MARK: - Custom Configuration

    func testWhenCustomMatchHeaders_itCapturesOnlySpecifiedHeaders() {
        // Given
        let processor = HeaderProcessor(config: .custom([.matchHeaders(["x-request-id"])]))

        // When
        let result = processor.process(
            requestHeaders: [
                "x-request-id": "abc-123",
                "content-type": "application/json"
            ],
            responseHeaders: [
                "x-request-id": "abc-123",
                "content-type": "text/html"
            ]
        )

        // Then
        XCTAssertEqual(result.request, ["x-request-id": "abc-123"])
        XCTAssertEqual(result.response, ["x-request-id": "abc-123"])
    }

    func testWhenCustomWithDefaultsAndMatchHeaders_itMergesBoth() {
        // Given
        let processor = HeaderProcessor(config: .custom([.defaults, .matchHeaders(["x-request-id"])]))

        // When
        let result = processor.process(
            requestHeaders: [
                "cache-control": "no-cache",
                "content-type": "application/json",
                "x-request-id": "abc-123",
                "accept": "text/html"
            ],
            responseHeaders: [
                "x-request-id": "abc-123",
                "content-type": "text/html"
            ]
        )

        // Then
        XCTAssertEqual(result.request, [
            "cache-control": "no-cache",
            "content-type": "application/json",
            "x-request-id": "abc-123"
        ])
        XCTAssertEqual(result.response, [
            "x-request-id": "abc-123",
            "content-type": "text/html"
        ])
    }

    // MARK: - Security Filtering

    func testItNeverCapturesSensitiveHeaders() {
        // Given
        let sensitiveNames = [
            "authorization",
            "proxy-authorization",
            "x-api-key",
            "x-access-token",
            "x-auth-token",
            "x-session-token",
            "cookie",
            "set-cookie",
            "x-forwarded-for",
            "x-real-ip",
            "cf-connecting-ip",
            "true-client-ip",
            "x-csrf-token",
            "x-xsrf-token",
            "x-security-token"
        ]
        let processor = HeaderProcessor(config: .custom([.matchHeaders(sensitiveNames)]))

        // When
        let result = processor.process(
            requestHeaders: [
                "authorization": "Bearer secret",
                "proxy-authorization": "Basic abc",
                "x-api-key": "key123",
                "x-access-token": "token",
                "x-auth-token": "auth",
                "x-session-token": "session",
                "cookie": "id=abc",
                "x-forwarded-for": "1.2.3.4",
                "x-real-ip": "1.2.3.4",
                "cf-connecting-ip": "1.2.3.4",
                "true-client-ip": "1.2.3.4",
                "x-csrf-token": "csrf",
                "x-xsrf-token": "xsrf",
                "x-security-token": "sec"
            ],
            responseHeaders: [
                "set-cookie": "session=abc"
            ]
        )

        // Then
        XCTAssertTrue(result.request.isEmpty)
        XCTAssertTrue(result.response.isEmpty)
    }

    func testItFiltersHeadersMatchingSecurityPattern() {
        // Given
        let sensitiveNames = [
            "x-custom-token",
            "my-secret-header",
            "x-app-key",
            "x-bearer-auth",
            "x-password-hash",
            "x-credential-id",
            "content-type"
        ]
        let processor = HeaderProcessor(config: .custom([.matchHeaders(sensitiveNames)]))

        // When
        let result = processor.process(
            requestHeaders: [
                "x-custom-token": "value",
                "my-secret-header": "value",
                "x-app-key": "value",
                "x-bearer-auth": "value",
                "x-password-hash": "value",
                "x-credential-id": "value",
                "content-type": "application/json"
            ],
            responseHeaders: [:]
        )

        // Then
        XCTAssertEqual(result.request, ["content-type": "application/json"])
    }

    // MARK: - Reserved Request Headers

    func testItFiltersReservedHeadersFromRequest() {
        // Given
        let reservedNames = [
            "content-length",
            "connection",
            "host",
            "proxy-authenticate",
            "www-authenticate",
            "content-type"
        ]
        let processor = HeaderProcessor(config: .custom([.matchHeaders(reservedNames)]))

        // When
        let result = processor.process(
            requestHeaders: [
                "Content-Length": "1024",
                "Connection": "keep-alive",
                "Host": "example.com",
                "Proxy-Authenticate": "Basic",
                "WWW-Authenticate": "Bearer",
                "Content-Type": "application/json"
            ],
            responseHeaders: [:]
        )

        // Then - Only content-type should pass (others are reserved for requests)
        XCTAssertEqual(result.request.count, 1)
        XCTAssertNotNil(result.request.first(where: { $0.key.lowercased() == "content-type" }))
    }

    func testItDoesNotFilterReservedHeadersFromResponse() {
        // Given
        let headerNames = [
            "content-length",
            "content-type"
        ]
        let processor = HeaderProcessor(config: .custom([.matchHeaders(headerNames)]))

        // When
        let result = processor.process(
            requestHeaders: [:],
            responseHeaders: [
                "Content-Length": "1024",
                "Content-Type": "application/json"
            ]
        )

        // Then - Content-Length is valid in responses
        XCTAssertEqual(result.response.count, 2)
    }

    // MARK: - Case Sensitivity

    func testItMatchesHeadersCaseInsensitively() {
        // Given
        let processor = HeaderProcessor(config: .custom([.matchHeaders(["Content-Type"])]))

        // When
        let result = processor.process(
            requestHeaders: ["content-type": "application/json"],
            responseHeaders: ["CONTENT-TYPE": "text/html"]
        )

        // Then
        XCTAssertEqual(result.request.count, 1)
        XCTAssertEqual(result.request.first(where: { $0.key.lowercased() == "content-type" })?.value, "application/json")
        XCTAssertEqual(result.response.count, 1)
        XCTAssertEqual(result.response.first(where: { $0.key.lowercased() == "content-type" })?.value, "text/html")
    }

    // MARK: - Value Truncation

    func testItTruncatesValuesExceeding128Bytes() throws {
        // Given
        let processor = HeaderProcessor(config: .custom([.matchHeaders(["x-long-header"])]))
        let longValue = String(repeating: "a", count: 200)

        // When
        let result = processor.process(
            requestHeaders: ["x-long-header": longValue],
            responseHeaders: [:]
        )

        // Then
        let capturedValue = try XCTUnwrap(result.request["x-long-header"])
        XCTAssertLessThanOrEqual(capturedValue.utf8.count, 128)
    }

    // MARK: - Header Count Limit

    func testItLimitsTo100Headers() {
        // Given
        var headerNames: [String] = []
        var requestHeaders: [String: String] = [:]
        for i in 0..<150 {
            let name = "x-header-\(i)"
            headerNames.append(name)
            requestHeaders[name] = "value-\(i)"
        }
        let processor = HeaderProcessor(config: .custom([.matchHeaders(headerNames)]))

        // When
        let result = processor.process(
            requestHeaders: requestHeaders,
            responseHeaders: [:]
        )

        // Then
        XCTAssertLessThanOrEqual(result.request.count, 100)
    }

    // MARK: - Total Size Limit

    func testItEnforces2KBTotalSizeLimit() {
        // Given
        var headerNames: [String] = []
        var requestHeaders: [String: String] = [:]
        for i in 0..<50 {
            let name = "x-header-\(i)"
            headerNames.append(name)
            // Each value is 100 bytes, 50 headers = ~5KB > 2KB limit
            requestHeaders[name] = String(repeating: "x", count: 100)
        }
        let processor = HeaderProcessor(config: .custom([.matchHeaders(headerNames)]))

        // When
        let result = processor.process(
            requestHeaders: requestHeaders,
            responseHeaders: [:]
        )

        // Then - Total size should be at most 2KB
        let totalSize = result.request.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        XCTAssertLessThanOrEqual(totalSize, 2_048)
    }

    // MARK: - Nil Input

    func testWhenInputIsNil_itReturnsEmptyHeaders() {
        // Given
        let processor = HeaderProcessor(config: .defaults)

        // When
        let result = processor.process(
            requestHeaders: nil,
            responseHeaders: nil
        )

        // Then
        XCTAssertTrue(result.request.isEmpty)
        XCTAssertTrue(result.response.isEmpty)
    }

    // MARK: - Response AnyHashable Cast

    func testItHandlesResponseHeadersWithAnyHashableKeys() {
        // Given
        let processor = HeaderProcessor(config: .defaults)
        let responseHeaders: [AnyHashable: Any] = [
            "content-type": "application/json",
            "cache-control": "no-cache",
            42: "should-be-ignored" // non-String key
        ]

        // When
        let result = processor.process(
            requestHeaders: [:],
            responseHeaders: responseHeaders
        )

        // Then
        XCTAssertEqual(result.response["content-type"], "application/json")
        XCTAssertEqual(result.response["cache-control"], "no-cache")
    }
}
