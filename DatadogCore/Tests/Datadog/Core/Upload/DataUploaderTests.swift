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

        let httpClient = HTTPClientMock(error: randomError)
        let uploader = DataUploader(
            httpClient: httpClient,
            requestBuilder: FeatureRequestBuilderMock(request: randomRequest)
        )

        // When
        let firstUploadStatus = try uploader.upload(
            events: .mockAny(),
            context: .mockAny(),
            previous: nil
        )

        // Then
        let expectedFirstUploadStatus = DataUploadStatus(networkError: randomError, attempt: 0)

        DDAssertReflectionEqual(firstUploadStatus, expectedFirstUploadStatus)
        XCTAssertNotNil(httpClient.requestsSent().last)
        let firstRequest = httpClient.requestsSent().last!
        XCTAssertEqual(firstRequest.url?.queryItem("ddtags")?.value, "retry_count:1")

        // When
        let secondUploadStatus = try uploader.upload(
            events: .mockAny(),
            context: .mockAny(),
            previous: firstUploadStatus
        )

        // Then
        let expectedSecondUploadStatus = DataUploadStatus(networkError: randomError, attempt: 1)

        DDAssertReflectionEqual(secondUploadStatus, expectedSecondUploadStatus)
        XCTAssertNotNil(httpClient.requestsSent().last)
        let secondRequest = httpClient.requestsSent().last!
        XCTAssertEqual(secondRequest.url?.queryItem("ddtags")?.value, "retry_count:2,last_failure_status:\(randomError.code)")
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
