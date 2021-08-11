/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class UploadURLTests: XCTestCase {
    func testDDSourceQueryItem() {
        let item: UploadURL.QueryItem = .ddsource(source: "abc")

        XCTAssertEqual(item.urlQueryItem.name, "ddsource")
        XCTAssertEqual(item.urlQueryItem.value, "abc")
    }

    func testItBuildsValidURLUsingNoQueryItems() throws {
        let urlProvider = UploadURL(
            url: URL(string: "https://api.example.com/v1/endpoint/abc")!,
            queryItems: []
        )

        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/abc"))
    }

    func testItBuildsValidURLUsingAllQueryItems() throws {
        let urlProvider = UploadURL(
            url: URL(string: "https://api.example.com/v1/endpoint/feature")!,
            queryItems: [.ddsource(source: "abc"), .ddtags(tags: ["abc:def"])]
        )

        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/feature?ddsource=abc&ddtags=abc:def"))
        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/feature?ddsource=abc&ddtags=abc:def"))
    }

    func testItEscapesWhitespacesInQueryItems() throws {
        let urlProvider = UploadURL(
            url: URL(string: "https://api.example.com/v1/endpoint/feature")!,
            queryItems: [.ddtags(tags: ["some string with whitespace"])]
        )

        XCTAssertEqual(urlProvider.url, URL(string: "https://api.example.com/v1/endpoint/feature?ddtags=some%20string%20with%20whitespace"))
    }
}

extension DataUploadStatus: EquatableInTests {}

class DataUploaderTests: XCTestCase {
    func testWhenUploadCompletesWithSuccess_itReturnsExpectedUploadStatus() {
        // Given
        let randomResponse: HTTPURLResponse = .mockResponseWith(statusCode: (100...599).randomElement()!)
        let randomRequestIDOrNil: String? = Bool.random() ? .mockRandom() : nil
        let requestIDHeaderOrNil: HTTPHeadersProvider.HTTPHeader? = randomRequestIDOrNil.flatMap { randomRequestID in
            .init(field: HTTPHeadersProvider.HTTPHeader.ddRequestIDHeaderField, value: .constant(randomRequestID))
        }

        let server = ServerMock(delivery: .success(response: randomResponse))
        let uploader = DataUploader(
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            uploadURL: .mockAny(),
            httpHeadersProvider: .init(headers: requestIDHeaderOrNil.map { [$0] } ?? [])
        )

        // When
        let uploadStatus = uploader.upload(data: .mockAny())

        // Then
        let expectedUploadStatus = DataUploadStatus(httpResponse: randomResponse, ddRequestID: randomRequestIDOrNil)

        XCTAssertEqual(uploadStatus, expectedUploadStatus)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenUploadCompletesWithFailure_itReturnsExpectedUploadStatus() {
        // Given
        let randomErrorDescription: String = .mockRandom()
        let randomError = NSError(domain: .mockRandom(), code: .mockRandom(), userInfo: [NSLocalizedDescriptionKey: randomErrorDescription])

        let server = ServerMock(delivery: .failure(error: randomError))
        let uploader = DataUploader(
            httpClient: HTTPClient(session: server.getInterceptedURLSession()),
            uploadURL: .mockAny(),
            httpHeadersProvider: .init(headers: [])
        )

        // When
        let uploadStatus = uploader.upload(data: .mockAny())

        // Then
        let expectedUploadStatus = DataUploadStatus(networkError: randomError)

        XCTAssertEqual(uploadStatus, expectedUploadStatus)
        server.waitFor(requestsCompletion: 1)
    }
}
