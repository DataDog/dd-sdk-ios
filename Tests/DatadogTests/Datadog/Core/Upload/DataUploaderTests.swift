/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DataUploadURLProviderTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: Date.mockDecember15th2019At10AMUTC())

    func testItBuildsValidURL() throws {
        let validURL1 = try UploadURLProvider(endpointURL: "https://api.example.com/v1/endpoint", clientToken: "abc", dateProvider: dateProvider)
        XCTAssertEqual(validURL1.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddsource=mobile&batch_time=1576404000000"))

        dateProvider.advance(bySeconds: 9.999)

        let validURL2 = try UploadURLProvider(endpointURL: "https://api.example.com/v1/endpoint/", clientToken: "abc", dateProvider: dateProvider)
        XCTAssertEqual(validURL2.url, URL(string: "https://api.example.com/v1/endpoint/abc?ddsource=mobile&batch_time=1576404009999"))
    }

    func testWhenClientTokenIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try UploadURLProvider(endpointURL: "https://api.example.com/v1/endpoint", clientToken: "", dateProvider: dateProvider)) { error in
            XCTAssertEqual((error as? ProgrammerError)?.description, "🔥 Datadog SDK usage error: `clientToken` cannot be empty.")
        }
    }

    func testWhenEndpointURLIsInvalid_itThrowsProgrammerError() {
        XCTAssertThrowsError(try UploadURLProvider(endpointURL: "", clientToken: "abc", dateProvider: dateProvider)) { error in
            XCTAssertEqual((error as? ProgrammerError)?.description, "🔥 Datadog SDK usage error: `endpointURL` cannot be empty.")
        }
    }

    // MARK: - Logs endpoint

    func testUSLogsEndpoint() {
        let urlUS = Datadog.Configuration.LogsEndpoint.us.url
        let urlProvider = try! UploadURLProvider(
            endpointURL: urlUS,
            clientToken: "abc",
            dateProvider: dateProvider
        )
        XCTAssertEqual(urlProvider.url.host, "mobile-http-intake.logs.datadoghq.com")
    }

    func testEULogsEndpoint() {
        let urlEU = Datadog.Configuration.LogsEndpoint.eu.url
        let urlProvider = try! UploadURLProvider(
            endpointURL: urlEU,
            clientToken: "abc",
            dateProvider: dateProvider
        )
        XCTAssertEqual(urlProvider.url.host, "mobile-http-intake.logs.datadoghq.eu")
    }

    func testCustomLogsEndpoint() {
        let urlCustom = Datadog.Configuration.LogsEndpoint.custom(url: "scheme://foo.bar").url
        let urlProvider = try! UploadURLProvider(
            endpointURL: urlCustom,
            clientToken: "abc",
            dateProvider: dateProvider
        )
        XCTAssertEqual(urlProvider.url.host, "foo.bar")
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
}
