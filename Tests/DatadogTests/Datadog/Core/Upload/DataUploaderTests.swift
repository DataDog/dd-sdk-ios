/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataUploadURLProviderTests: XCTestCase {
    func testDDSourceQueryItem() {
        let item: UploadURLProvider.QueryItemProvider = .ddsource(source: "abc")

        XCTAssertEqual(item.value().name, "ddsource")
        XCTAssertEqual(item.value().value, "abc")
    }

    func testItBuildsValidURLUsingNoQueryItems() throws {
        let urlProvider = UploadURLProvider(
            urlWithClientToken: URL(string: "https://api.example.com/v1/endpoint/abc")!,
            queryItemProviders: []
        )

        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/abc"))
    }

    func testItBuildsValidURLUsingAllQueryItems() throws {
        let urlProvider = UploadURLProvider(
            urlWithClientToken: URL(string: "https://api.example.com/v1/endpoint/abc")!,
            queryItemProviders: [.ddsource(source: "abc"), .ddtags(tags: ["abc:def"])]
        )

        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddsource=abc&ddtags=abc:def"))
        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddsource=abc&ddtags=abc:def"))
    }

    func testItEscapesWhitespacesInQueryItems() throws {
        let urlProvider = UploadURLProvider(
            urlWithClientToken: URL(string: "https://api.example.com/v1/endpoint/abc")!,
            queryItemProviders: [.ddtags(tags: ["some string with whitespace"])]
        )

        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddtags=some%20string%20with%20whitespace"))
    }
}

class DataUploaderTests: XCTestCase {
    // MARK: - Upload Status

    func testWhenDataIsSentWith200Code_itReturnsDataUploadStatus_success() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .success)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenDataIsSentWith300Code_itReturnsDataUploadStatus_redirection() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 300)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .redirection)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenDataIsSentWith400Code_itReturnsDataUploadStatus_clientError() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 400)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .clientError)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenDataIsSentWith403Code_itReturnsDataUploadStatus_clientTokenError() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 403)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .clientTokenError)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenDataIsSentWith500Code_itReturnsDataUploadStatus_serverError() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 500)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .serverError)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenDataIsNotSentDueToNetworkError_itReturnsDataUploadStatus_networkError() {
        let mockError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "network error"])
        let server = ServerMock(delivery: .failure(error: mockError))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .networkError)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenDataIsNotSentDueToUnknownStatusCode_itReturnsDataUploadStatus_unknown() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: -1)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: .serverMockURLSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .unknown)
        server.waitFor(requestsCompletion: 1)
    }
}
