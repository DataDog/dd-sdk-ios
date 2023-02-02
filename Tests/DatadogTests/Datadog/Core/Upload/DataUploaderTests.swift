/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class DataUploaderTests: XCTestCase {
    func testWhenUploadCompletesWithSuccess_itReturnsExpectedUploadStatus() throws {
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
        let uploadStatus = try uploader.upload(
            events: .mockAny(),
            context: .mockAny()
        )

        // Then
        let expectedUploadStatus = DataUploadStatus(httpResponse: randomResponse, ddRequestID: randomRequestIDOrNil)

        DDAssertReflectionEqual(uploadStatus, expectedUploadStatus)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenUploadCompletesWithFailure_itReturnsExpectedUploadStatus() throws {
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
        let uploadStatus = try uploader.upload(
            events: .mockAny(),
            context: .mockAny()
        )

        // Then
        let expectedUploadStatus = DataUploadStatus(networkError: randomError)

        DDAssertReflectionEqual(uploadStatus, expectedUploadStatus)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenUploadCannotBeInitiated_itThrows() throws {
        // Given
        let error = ErrorMock()

        let uploader = DataUploader(
            httpClient: .mockAny(),
            requestBuilder: FailingRequestBuilderMock(error: error)
        )

        // When & Then
        XCTAssertThrowsError(try uploader.upload(events: .mockAny(), context: .mockAny())) { error in
            XCTAssertTrue(error is ErrorMock)
        }
    }
}
