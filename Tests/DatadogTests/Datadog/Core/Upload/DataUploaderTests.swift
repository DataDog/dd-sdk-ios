/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

extension DataUploadStatus: EquatableInTests {}

class DataUploaderTests: XCTestCase {
    func testWhenUploadCompletesWithSuccess_itReturnsExpectedUploadStatus() {
        // Given
        let randomResponse: HTTPURLResponse = .mockResponseWith(statusCode: (100...599).randomElement()!)
        let randomRequestIDOrNil: String? = Bool.random() ? .mockRandom() : nil
        let requestIDHeaderOrNil: URLRequestBuilder.HTTPHeader? = randomRequestIDOrNil.flatMap { randomRequestID in
                .init(field: URLRequestBuilder.HTTPHeader.ddRequestIDHeaderField, value: { randomRequestID })
        }

        let server = ServerMock(delivery: .success(response: randomResponse))
        let httpClient = HTTPClient(session: server.getInterceptedURLSession())

        let uploader = DataUploader(
            httpClient: httpClient,
            requestBuilder: FeatureRequestBuilderMock(headers: requestIDHeaderOrNil.map { [$0] } ?? [])
        )

        // When
        let uploadStatus = uploader.upload(
            events: .mockAny(),
            context: .mockAny()
        )

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
        let httpClient = HTTPClient(session: server.getInterceptedURLSession())

        let uploader = DataUploader(
            httpClient: httpClient,
            requestBuilder: FeatureRequestBuilderMock()
        )

        // When
        let uploadStatus = uploader.upload(
            events: .mockAny(),
            context: .mockAny()
        )

        // Then
        let expectedUploadStatus = DataUploadStatus(networkError: randomError)

        XCTAssertEqual(uploadStatus, expectedUploadStatus)
        server.waitFor(requestsCompletion: 1)
    }
}
