/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataUploadURLProviderTests: XCTestCase {
    func testItBuildsValidURL() throws {
        let dateProvider = RelativeDateProvider(using: Date.mockDecember15th2019At10AMUTC())
        let urlProvider = UploadURLProvider(
            urlWithClientToken: URL(string: "https://api.example.com/v1/endpoint/abc")!,
            dateProvider: dateProvider
        )
        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddsource=ios&batch_time=1576404000000"))
        dateProvider.advance(bySeconds: 9.999)
        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddsource=ios&batch_time=1576404009999"))
    }
}

class DataUploaderTests: XCTestCase {
    // MARK: - Upload Status

    func testWhenDataIsSentWith200Code_itReturnsDataUploadStatus_success() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.urlSession),
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
            httpClient: HTTPClient(session: server.urlSession),
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
            httpClient: HTTPClient(session: server.urlSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .clientError)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenDataIsSentWith500Code_itReturnsDataUploadStatus_serverError() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 500)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.urlSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .serverError)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenDataIsNotSentDueToNetworkError_itReturnsDataUploadStatus_networkError() {
        let server = ServerMock(delivery: .failure(error: ErrorMock("network error")))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.urlSession),
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
            httpClient: HTTPClient(session: server.urlSession),
            httpHeaders: .mockAny()
        )
        let status = uploader.upload(data: .mockAny())

        XCTAssertEqual(status, .unknown)
        server.waitFor(requestsCompletion: 1)
    }

    // MARK: - HTTP Headers

    func testItSendsCustomHTTPHeaders() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let uploader = DataUploader(
            urlProvider: .mockAny(),
            httpClient: HTTPClient(session: server.urlSession),
            httpHeaders: HTTPHeaders(
                appName: "app-name",
                appVersion: "1.0.0",
                device: .mockWith(model: "iPhone", osName: "iOS", osVersion: "13.3.1")
            )
        )

        _ = uploader.upload(data: .mockAny())

        let request = server.waitAndReturnRequests(count: 1)[0]
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")
        XCTAssertEqual(request.allHTTPHeaderFields?["User-Agent"], "app-name/1.0.0 CFNetwork (iPhone; iOS/13.3.1)")
    }
}
