/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class HTTPHeadersProviderTests: XCTestCase {
    // MARK: - Header Values

    func testUsingContentTypeHeader() {
        var provider = HTTPHeadersProvider(headers: [.contentTypeHeader(contentType: .textPlainUTF8)])
        XCTAssertEqual(provider.headers["Content-Type"], "text/plain;charset=UTF-8")

        provider = HTTPHeadersProvider(headers: [.contentTypeHeader(contentType: .applicationJSON)])
        XCTAssertEqual(provider.headers["Content-Type"], "application/json")
    }

    func testUsingUserAgentHeader() {
        let provider = HTTPHeadersProvider(
            headers: [
                .userAgentHeader(
                    appName: "FoobarApp",
                    appVersion: "1.2.3",
                    device: .mockWith(
                        model: "iPhone",
                        osName: "iOS",
                        osVersion: "13.3.1"
                    )
                )
            ]
        )

        XCTAssertEqual(provider.headers["User-Agent"], "FoobarApp/1.2.3 CFNetwork (iPhone; iOS/13.3.1)")
    }

    func testUsingDDAPIKeyHeader() {
        let randomClientToken: String = .mockRandom()
        let provider = HTTPHeadersProvider(headers: [.ddAPIKeyHeader(clientToken: randomClientToken)])

        XCTAssertEqual(provider.headers["DD-API-KEY"], randomClientToken)
    }

    func testUsingDDEVPOriginHeader() {
        let randomSource: String = .mockRandom()
        let provider = HTTPHeadersProvider(headers: [.ddEVPOriginHeader(source: randomSource)])

        XCTAssertEqual(provider.headers["DD-EVP-ORIGIN"], randomSource)
    }

    func testUsingDDEVPOriginVersionHeader() {
        let provider = HTTPHeadersProvider(headers: [.ddEVPOriginVersionHeader()])
        XCTAssertEqual(provider.headers["DD-EVP-ORIGIN-VERSION"], sdkVersion)
    }

    func testUsingDDRequestIDHeader() throws {
        let provider = HTTPHeadersProvider(headers: [.ddRequestIDHeader()])

        let requestID1 = try XCTUnwrap(provider.headers["DD-REQUEST-ID"])
        let requestID2 = try XCTUnwrap(provider.headers["DD-REQUEST-ID"])
        let requestID3 = try XCTUnwrap(provider.headers["DD-REQUEST-ID"])

        let allIDs = Set([requestID1, requestID2, requestID3])
        XCTAssertEqual(allIDs.count, 3, "Each `DD-REQUEST-ID` must produce unique ID")
        allIDs.forEach { id in
            XCTAssertTrue(id.matches(regex: .uuidRegex), "Each `DD-REQUEST-ID` must be an UUID string")
        }
    }

    // MARK: - Headers Composition

    func testWhenMultipleHeadersAreConfigured_itReturnsThemAll() {
        let provider = HTTPHeadersProvider(
            headers: [
                .contentTypeHeader(contentType: .textPlainUTF8),
                .userAgentHeader(appName: .mockAny(), appVersion: .mockAny(), device: .mockAny()),
                .ddAPIKeyHeader(clientToken: .mockAny()),
                .ddEVPOriginHeader(source: .mockAny()),
                .ddEVPOriginVersionHeader(),
                .ddRequestIDHeader(),
            ]
        )

        XCTAssertNotNil(provider.headers["Content-Type"])
        XCTAssertNotNil(provider.headers["User-Agent"])
        XCTAssertNotNil(provider.headers["DD-API-KEY"])
        XCTAssertNotNil(provider.headers["DD-EVP-ORIGIN"])
        XCTAssertNotNil(provider.headers["DD-EVP-ORIGIN-VERSION"])
        XCTAssertNotNil(provider.headers["DD-REQUEST-ID"])
        XCTAssertEqual(provider.headers.count, 6)
    }
}
