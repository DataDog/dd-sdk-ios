/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore

class DataUploaderTests: XCTestCase {
    // swiftlint:disable opening_brace
    func testGivenValidRequest_whenUploadCompletesWithStatusCode_itReturnsUploadStatus() throws {
        // Given
        let randomResponse: HTTPURLResponse = .mockResponseWith(statusCode: (100...599).randomElement()!)
        let randomRequest: URLRequest = oneOf([
            { .mockWith(headers: [:]) },
            { .mockWith(headers: ["DD-REQUEST-ID": String.mockRandom()]) }
        ])

        let uploader = DataUploader(
            httpClient: HTTPClientMock(response: randomResponse),
            requestBuilder: FeatureRequestBuilderMock(request: randomRequest)
        )

        // When
        let uploadStatus = try uploader.upload(
            events: .mockAny(),
            context: .mockAny(),
            previous: nil
        )

        // Then
        let expectedUploadStatus = DataUploadStatus(
            httpResponse: randomResponse,
            ddRequestID: randomRequest.value(forHTTPHeaderField: "DD-REQUEST-ID"),
            attempt: 0
        )

        DDAssertReflectionEqual(uploadStatus, expectedUploadStatus)
    }
    // swiftlint:enable opening_brace

    func testGivenValidRequest_whenUploadCompletesWithError_itReturnsUploadStatus() throws {
        // Given
        let randomErrorDescription: String = .mockRandom()
        let randomError = NSError(domain: .mockRandom(), code: .mockRandom(), userInfo: [NSLocalizedDescriptionKey: randomErrorDescription])
        let randomRequest: URLRequest = .mockAny()

        let uploader = DataUploader(
            httpClient: HTTPClientMock(error: randomError),
            requestBuilder: FeatureRequestBuilderMock(request: randomRequest)
        )

        // When
        let uploadStatus = try uploader.upload(
            events: .mockAny(),
            context: .mockAny(),
            previous: nil
        )

        // Then
        let expectedUploadStatus = DataUploadStatus(networkError: randomError, attempt: 0)

        DDAssertReflectionEqual(uploadStatus, expectedUploadStatus)
    }

    func testWhenRequestCannotBeCreated_itThrows() throws {
        // Given
        let error = ErrorMock()

        let uploader = DataUploader(
            httpClient: HTTPClientMock(),
            requestBuilder: FailingRequestBuilderMock(error: error)
        )

        // When & Then
        XCTAssertThrowsError(try uploader.upload(events: .mockAny(), context: .mockAny(), previous: nil)) { error in
            XCTAssertTrue(error is ErrorMock)
        }
    }
}
