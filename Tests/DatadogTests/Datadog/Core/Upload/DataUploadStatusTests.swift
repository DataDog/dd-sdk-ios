/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class DataUploadStatusTests: XCTestCase {
    // MARK: - Test `.needsRetry`

    private let statusCodesExpectingNoRetry = [
        202, // ACCEPTED
        400, // BAD REQUEST
        401, // UNAUTHORIZED
        403, // FORBIDDEN
        413, // PAYLOAD TOO LARGE
    ]

    private let statusCodesExpectingRetry = [
        408, // REQUEST TIMEOUT
        429, // TOO MANY REQUESTS
        500, // INTERNAL SERVER ERROR
        503, // SERVICE UNAVAILABLE
    ]

    private lazy var expectedStatusCodes = statusCodesExpectingNoRetry + statusCodesExpectingRetry

    func testWhenUploadFinishesWithResponse_andStatusCodeNeedsNoRetry_itSetsNeedsRetryFlagToFalse() {
        statusCodesExpectingNoRetry.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: .mockAny())
            XCTAssertFalse(status.needsRetry, "Upload should not be retried for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeNeedsRetry_itSetsNeedsRetryFlagToTrue() {
        statusCodesExpectingRetry.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: .mockAny())
            XCTAssertTrue(status.needsRetry, "Upload should be retried for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeIsUnexpected_itSetsNeedsRetryFlagToFalse() {
        let allStatusCodes = Set((100...599))
        let unexpectedStatusCodes = allStatusCodes.subtracting(Set(expectedStatusCodes))

        unexpectedStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: .mockAny())
            XCTAssertFalse(status.needsRetry, "Upload should not be retried for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithError_itSetsNeedsRetryFlagToTrue() {
        let status = DataUploadStatus(networkError: ErrorMock())
        XCTAssertTrue(status.needsRetry, "Upload should be retried if it finished with error")
    }

    // MARK: - Test `.userDebugDescription`

    func testWhenUploadFinishesWithResponse_andRequestIDIsAvailable_itCreatesUserDebugDescription() {
        expectedStatusCodes.forEach { statusCode in
            let requestID: String = .mockRandom(among: .alphanumerics)
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: requestID)
            XCTAssertTrue(
                status.userDebugDescription.matches(
                    regex: "\\[response code: [0-9]{3} \\([a-zA-Z]+\\), request ID: \(requestID)\\]"
                ),
                "'\(status.userDebugDescription)' is not an expected description for status code '\(statusCode)' and request id '\(requestID)'"
            )
        }
    }

    func testWhenUploadFinishesWithResponse_andRequestIDIsNotAvailable_itCreatesUserDebugDescription() {
        expectedStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil)
            XCTAssertTrue(
                status.userDebugDescription.matches(
                    regex: "\\[response code: [0-9]{3} \\([a-zA-Z]+\\), request ID: \\(\\?\\?\\?\\)\\]"
                ),
                "'\(status.userDebugDescription)' is not an expected description for status code '\(statusCode)' and no request id"
            )
        }
    }

    func testWhenUploadFinishesWithError_itCreatesUserDebugDescription() {
        let randomErrorDescription: String = .mockRandom()
        let status = DataUploadStatus(networkError: ErrorMock(randomErrorDescription))
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
        let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: 401), ddRequestID: nil)
        XCTAssertEqual(status.error, .unauthorized)
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeIsDifferentThan401_itDoesNotCreateAnyError() {
        Set((100...599)).subtracting(alertingStatusCodes).forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil)
            XCTAssertNil(status.error)
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeMeansSDKIssue_itCreatesHTTPError() {
        alertingStatusCodes.subtracting([401, 403]).forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: .mockRandom())

            guard case let .httpError(statusCode: receivedStatusCode) = status.error else {
                return XCTFail("Upload status error should be created for status code: \(statusCode)")
            }

            XCTAssertEqual(receivedStatusCode, statusCode)
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeMeansClientIssue_itDoesNotCreateHTTPError() {
        let clientIssueStatusCodes = Set(expectedStatusCodes).subtracting(Set(alertingStatusCodes))
        clientIssueStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil)
            XCTAssertNil(status.error, "Upload status error should not be created for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithResponse_andUnexpectedStatusCodeMeansClientIssue_itDoesNotCreateHTTPError() {
        let unexpectedStatusCodes = Set((100...599)).subtracting(Set(expectedStatusCodes))
        unexpectedStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil)
            XCTAssertNil(status.error)
        }
    }

    func testWhenUploadFinishesWithError_andErrorCodeMeansSDKIssue_itCreatesNetworkError() throws {
        let alertingNSURLErrorCode = NSURLErrorBadURL
        let status = DataUploadStatus(networkError: NSError(domain: NSURLErrorDomain, code: alertingNSURLErrorCode, userInfo: nil))

        guard case let .networkError(error: nserror) = status.error else {
            return XCTFail("Upload status error should be created for NSURLError code: \(alertingNSURLErrorCode)")
        }

        XCTAssertEqual(nserror.code, alertingNSURLErrorCode)
    }

    func testWhenUploadFinishesWithError_andErrorCodeMeansExternalFactors_itDoesNotCreateNetworkError() {
        let notAlertingNSURLErrorCode = NSURLErrorNetworkConnectionLost
        let status = DataUploadStatus(networkError: NSError(domain: NSURLErrorDomain, code: notAlertingNSURLErrorCode, userInfo: nil))
        XCTAssertNil(status.error, "Upload status error should not be created for NSURLError code: \(notAlertingNSURLErrorCode)")
    }
}
