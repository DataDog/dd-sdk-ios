/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RequestBuilderTests: XCTestCase {
    // MARK: - Request URL

    func testBuildingRequestWithURLAndQueryItems() throws {
        let randomURL: URL = .mockRandom()
        let builder = RequestBuilder(
            url: randomURL,
            queryItems: [.ddsource(source: "abc"), .ddtags(tags: ["abc:def"])],
            headers: .mockRandom()
        )
        let request = builder.uploadRequest(with: .mockRandom())
        XCTAssertEqual(request.url?.absoluteString, "\(randomURL.absoluteString)?ddsource=abc&ddtags=abc:def")
    }

    func testWhenBuildingRequestWithURLAndQueryItems_itEscapesWhitespacesInQuery() throws {
        let randomURL: URL = .mockRandom()
        let builder = RequestBuilder(
            url: randomURL,
            queryItems: [.ddsource(source: "source with whitespace"), .ddtags(tags: ["tag with whitespace"])],
            headers: .mockRandom()
        )
        let request = builder.uploadRequest(with: .mockRandom())
        XCTAssertEqual(request.url?.absoluteString, "\(randomURL.absoluteString)?ddsource=source%20with%20whitespace&ddtags=tag%20with%20whitespace")
    }

    // MARK: - Request Headers

    func testBuildingRequestWithContentTypeHeader() {
        var builder = RequestBuilder(url: .mockRandom(), queryItems: .mockRandom(), headers: [.contentTypeHeader(contentType: .textPlainUTF8)])
        var request = builder.uploadRequest(with: .mockAny())
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "text/plain;charset=UTF-8")

        builder = RequestBuilder(url: .mockRandom(), queryItems: .mockRandom(), headers: [.contentTypeHeader(contentType: .applicationJSON)])
        request = builder.uploadRequest(with: .mockAny())
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
    }

    func testBuildingRequestWithUserAgentHeader() {
        let builder = RequestBuilder(
            url: .mockRandom(),
            queryItems: .mockRandom(),
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
        let request = builder.uploadRequest(with: .mockRandom())
        XCTAssertEqual(request.allHTTPHeaderFields?["User-Agent"], "FoobarApp/1.2.3 CFNetwork (iPhone; iOS/13.3.1)")
    }

    func testBuildingRequestWithDDAPIKeyHeader() {
        let randomClientToken: String = .mockRandom()
        let builder = RequestBuilder(url: .mockRandom(), queryItems: .mockRandom(), headers: [.ddAPIKeyHeader(clientToken: randomClientToken)])
        let request = builder.uploadRequest(with: .mockRandom())
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-API-KEY"], randomClientToken)
    }

    func testBuildingRequestWithDDEVPOriginHeader() {
        let randomSource: String = .mockRandom()
        let builder = RequestBuilder(url: .mockRandom(), queryItems: .mockRandom(), headers: [.ddEVPOriginHeader(source: randomSource)])
        let request = builder.uploadRequest(with: .mockRandom())
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"], randomSource)
    }

    func testBuildingRequestWithDDEVPOriginVersionHeader() {
        let builder = RequestBuilder(url: .mockRandom(), queryItems: .mockRandom(), headers: [.ddEVPOriginVersionHeader()])
        let request = builder.uploadRequest(with: .mockRandom())
        XCTAssertEqual(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"], sdkVersion)
    }

    func testBuildingRequestWithDDRequestIDHeader() throws {
        let builder = RequestBuilder(url: .mockRandom(), queryItems: .mockRandom(), headers: [.ddRequestIDHeader()])

        let request1 = builder.uploadRequest(with: .mockRandom())
        let request2 = builder.uploadRequest(with: .mockRandom())
        let request3 = builder.uploadRequest(with: .mockRandom())

        let requestID1 = try XCTUnwrap(request1.allHTTPHeaderFields?["DD-REQUEST-ID"])
        let requestID2 = try XCTUnwrap(request2.allHTTPHeaderFields?["DD-REQUEST-ID"])
        let requestID3 = try XCTUnwrap(request3.allHTTPHeaderFields?["DD-REQUEST-ID"])

        let allIDs = Set([requestID1, requestID2, requestID3])
        XCTAssertEqual(allIDs.count, 3, "Each `DD-REQUEST-ID` must produce unique ID")
        allIDs.forEach { id in
            XCTAssertTrue(id.matches(regex: .uuidRegex), "Each `DD-REQUEST-ID` must be an UUID string")
        }
    }

    func testBuildingRequestWithMultipleHeaders() {
        let builder = RequestBuilder(
            url: .mockRandom(),
            queryItems: .mockRandom(),
            headers: [
                .contentTypeHeader(contentType: .textPlainUTF8),
                .userAgentHeader(appName: .mockAny(), appVersion: .mockAny(), device: .mockAny()),
                .ddAPIKeyHeader(clientToken: .mockAny()),
                .ddEVPOriginHeader(source: .mockAny()),
                .ddEVPOriginVersionHeader(),
                .ddRequestIDHeader(),
            ]
        )

        let request = builder.uploadRequest(with: .mockRandom())
        XCTAssertNotNil(request.allHTTPHeaderFields?["Content-Type"])
        XCTAssertNotNil(request.allHTTPHeaderFields?["User-Agent"])
        XCTAssertNotNil(request.allHTTPHeaderFields?["DD-API-KEY"])
        XCTAssertNotNil(request.allHTTPHeaderFields?["DD-EVP-ORIGIN"])
        XCTAssertNotNil(request.allHTTPHeaderFields?["DD-EVP-ORIGIN-VERSION"])
        XCTAssertNotNil(request.allHTTPHeaderFields?["DD-REQUEST-ID"])
        XCTAssertEqual(request.allHTTPHeaderFields?.count, 6)
    }

    // MARK: - Request Method

    func testItUsesPOSTMethodForProducedReqest() {
        let builder = RequestBuilder(url: .mockRandom(), queryItems: .mockRandom(), headers: .mockRandom())
        let request = builder.uploadRequest(with: .mockRandom())
        XCTAssertEqual(request.httpMethod, "POST")
    }

    // MARK: - Request Data

    func testItSetsDataAsHTTPBodyInProducedRequest() {
        let randomData: Data = .mockRandom()
        let builder = RequestBuilder(url: .mockRandom(), queryItems: .mockRandom(), headers: .mockRandom())
        let request = builder.uploadRequest(with: randomData)
        XCTAssertEqual(request.httpBody, randomData)
    }
}
