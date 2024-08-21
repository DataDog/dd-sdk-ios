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

    private let alertingStatusCodes: Set = [
        400, // BAD REQUEST
        401, // UNAUTHORIZED
        403, // FORBIDDEN
        413, // PAYLOAD TOO LARGE
        408, // REQUEST TIMEOUT
        429, // TOO MANY REQUESTS
    ]

    func testWhenUploadFinishesWithResponse_andStatusCodeIs401_itCreatesError() {
        let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: 401), ddRequestID: nil, attempt: 0)
        XCTAssertEqual(status.error, .unauthorized)
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeIsDifferentThan401_itDoesNotCreateAnyError() {
        Set((100...599)).subtracting(alertingStatusCodes).forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil, attempt: 0)
            XCTAssertNil(status.error)
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeMeansSDKIssue_itCreatesHTTPError() {
        alertingStatusCodes.subtracting([401, 403]).forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: .mockRandom(), attempt: 01)

            guard case let .httpError(statusCode: receivedStatusCode) = status.error else {
                return XCTFail("Upload status error should be created for status code: \(statusCode)")
            }

            XCTAssertEqual(receivedStatusCode, statusCode)
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeMeansClientIssue_itDoesNotCreateHTTPError() {
        let clientIssueStatusCodes = Set(expectedStatusCodes.keys).subtracting(Set(alertingStatusCodes))
        clientIssueStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil, attempt: 0)
            XCTAssertNil(status.error, "Upload status error should not be created for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithResponse_andUnexpectedStatusCodeMeansClientIssue_itDoesNotCreateHTTPError() {
        let unexpectedStatusCodes = Set((100...599)).subtracting(Set(expectedStatusCodes.keys))
        unexpectedStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil, attempt: 0)
            XCTAssertNil(status.error)
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

    func testWhenUploadFinishesWithError_andErrorCodeMeansExternalFactors_itDoesNotCreateNetworkError() {
        let notAlertingNSURLErrorCode = NSURLErrorNetworkConnectionLost
        let status = DataUploadStatus(networkError: NSError(domain: NSURLErrorDomain, code: notAlertingNSURLErrorCode, userInfo: nil), attempt: 0)
        XCTAssertNil(status.error, "Upload status error should not be created for NSURLError code: \(notAlertingNSURLErrorCode)")
    }

    // MARK: - Test Response Code

    func testWhenUploadFinishesWithResponse_itSetsResponseCode() {
        let randomCode: Int = .mockRandom(min: 1, max: 999)
        let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: randomCode), ddRequestID: nil, attempt: 0)
        XCTAssertEqual(status.responseCode, randomCode)
    }
}
