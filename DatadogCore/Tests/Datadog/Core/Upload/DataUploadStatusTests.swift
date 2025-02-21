/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class DataUploadStatusTests: XCTestCase {
    // MARK: - Test `.needsRetry`

    private let statusCodesExpectingNoRetry: [Int: String] = [
        202: "accepted",
        400: "badRequest",
        401: "unauthorized",
        403: "forbidden",
        413: "payloadTooLarge",
    ]

    private let statusCodesExpectingRetry: [Int: String] = [
        408: "requestTimeout",
        429: "tooManyRequests",
        500: "internalServerError",
        502: "badGateway",
        503: "serviceUnavailable",
        504: "gatewayTimeout",
        507: "insufficientStorage",
    ]

    private lazy var expectedStatusCodes = statusCodesExpectingNoRetry + statusCodesExpectingRetry

    func testWhenUploadFinishesWithResponse_andStatusCodeNeedsNoRetry_itSetsNeedsRetryFlagToFalse() {
        statusCodesExpectingNoRetry.forEach { statusCode, _ in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: .mockAny(), attempt: 0)
            XCTAssertFalse(status.needsRetry, "Upload should not be retried for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeNeedsRetry_itSetsNeedsRetryFlagToTrue() {
        statusCodesExpectingRetry.forEach { statusCode, _ in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: .mockAny(), attempt: 0)
            XCTAssertTrue(status.needsRetry, "Upload should be retried for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeIsUnexpected_itSetsNeedsRetryFlagToFalse() {
        let allStatusCodes = Set((100...599))
        let unexpectedStatusCodes = allStatusCodes.subtracting(Set(expectedStatusCodes.keys))

        unexpectedStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: .mockAny(), attempt: 0)
            XCTAssertFalse(status.needsRetry, "Upload should not be retried for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithError_itSetsNeedsRetryFlagToTrue() {
        let status = DataUploadStatus(networkError: ErrorMock(), attempt: 0)
        XCTAssertTrue(status.needsRetry, "Upload should be retried if it finished with error")
    }

    // MARK: - Test `.userDebugDescription`

    func testWhenUploadFinishesWithResponse_andRequestIDIsAvailable_itCreatesUserDebugDescription() {
        expectedStatusCodes.forEach { statusCode, message in
            let requestID: String = .mockRandom(among: .alphanumerics)
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: requestID, attempt: 0)
            XCTAssertEqual(status.userDebugDescription, "[response code: \(statusCode) (\(message)), request ID: \(requestID)")
        }
    }

    func testWhenUploadFinishesWithResponse_andRequestIDIsNotAvailable_itCreatesUserDebugDescription() {
        expectedStatusCodes.forEach { statusCode, message in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil, attempt: 0)
            XCTAssertEqual(status.userDebugDescription, "[response code: \(statusCode) (\(message)), request ID: (???)")
        }
    }

    func testWhenUploadFinishesWithError_itCreatesUserDebugDescription() {
        let randomErrorDescription: String = .mockRandom()
        let status = DataUploadStatus(networkError: ErrorMock(randomErrorDescription), attempt: 0)
        XCTAssertEqual(status.userDebugDescription, "[error: \(randomErrorDescription)]")
    }

    // MARK: - Test Upload Error

    private let errorStatusCodes: Set = [
        400, // BAD REQUEST
        401, // UNAUTHORIZED
        403, // FORBIDDEN
        408, // REQUEST TIMEOUT
        413, // PAYLOAD TOO LARGE
        429, // TOO MANY REQUESTS
        500, // INTERNAL SERVER ERROR
        502, // BAD GATEWAY
        503, // SERVICE UNAVAILABLE
        504, // GATEWAY TIMEOUT
        507, // INSUFFICIENT STORAGE
    ]

    func testWhenUploadFinishesWithResponse_andStatusCodeIs401_itCreatesError() {
        let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: 401), ddRequestID: nil, attempt: 0)
        XCTAssertEqual(status.error, DataUploadError.httpError(statusCode: .unauthorized))
    }

    func testWhenUploadFinishesWithErrorStatusCode_itCreatesAnError() {
        errorStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil, attempt: 0)
            guard case let .httpError(statusCode: receivedStatusCode) = status.error else {
                return XCTFail("Upload status error should be created for status code: \(statusCode)")
            }

            XCTAssertEqual(receivedStatusCode.rawValue, statusCode)
        }
    }

    func testWhenUploadFinishesWithError_andErrorCodeMeansSDKIssue_itCreatesNetworkError() throws {
        let alertingNSURLErrorCode = NSURLErrorBadURL
        let status = DataUploadStatus(networkError: NSError(domain: NSURLErrorDomain, code: alertingNSURLErrorCode, userInfo: nil), attempt: 0)

        guard case let .networkError(error: nserror) = status.error else {
            return XCTFail("Upload status error should be created for NSURLError code: \(alertingNSURLErrorCode)")
        }

        XCTAssertEqual(nserror.code, alertingNSURLErrorCode)
    }

    // MARK: - Test Response Code

    func testWhenUploadFinishesWithResponse_itSetsResponseCode() {
        let randomCode: Int = .mockRandom(min: 1, max: 999)
        let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: randomCode), ddRequestID: nil, attempt: 0)
        XCTAssertEqual(status.responseCode, randomCode)
    }
}
