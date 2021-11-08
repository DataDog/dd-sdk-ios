/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
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

    // MARK: - Test `.userErrorMessage`

    func testWhenUploadFinishesWithResponse_andStatusCodeIs401_itCreatesClientTokenErrorMessage() {
        let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: 401), ddRequestID: nil)
        XCTAssertEqual(status.userErrorMessage, "⚠️ The client token you provided seems to be invalid.")
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeIsDifferentThan401_itDoesNotCreateAnyUserErrorMessage() {
        let statusCodes = Set((100...599)).subtracting([401])
        statusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil)
            XCTAssertNil(status.userErrorMessage)
        }
    }

    func testWhenUploadFinishesWithError_itDoesNotCreateAnyUserErrorMessage() {
        let status = DataUploadStatus(networkError: ErrorMock(.mockRandom()))
        XCTAssertNil(status.userErrorMessage)
    }

    // MARK: - Test `.internalMonitoringError`

    private let alertingStatusCodes = [
        400, // BAD REQUEST
        413, // PAYLOAD TOO LARGE
        408, // REQUEST TIMEOUT
        429, // TOO MANY REQUESTS
    ]

    func testWhenUploadFinishesWithResponse_andStatusCodeMeansSDKIssue_itCreatesInternalMonitoringError() throws {
        try alertingStatusCodes.forEach { statusCode in
            let requestID: String = .mockRandom()
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: requestID)
            let error = try XCTUnwrap(status.internalMonitoringError, "Internal Monitoring error should be created for status code \(statusCode)")
            XCTAssertEqual(error.message, "Data upload finished with status code: \(statusCode)")
            XCTAssertEqual(error.attributes?["dd_request_id"], requestID)
        }
    }

    func testWhenUploadFinishesWithResponse_andStatusCodeMeansClientIssue_itDoesNotCreateInternalMonitoringError() {
        let clientIssueStatusCodes = Set(expectedStatusCodes).subtracting(Set(alertingStatusCodes))
        clientIssueStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil)
            XCTAssertNil(status.internalMonitoringError, "Internal Monitoring error should not be created for status code \(statusCode)")
        }
    }

    func testWhenUploadFinishesWithResponse_andUnexpectedStatusCodeMeansClientIssue_itDoesNotCreateInternalMonitoringError() {
        let unexpectedStatusCodes = Set((100...599)).subtracting(Set(expectedStatusCodes))
        unexpectedStatusCodes.forEach { statusCode in
            let status = DataUploadStatus(httpResponse: .mockResponseWith(statusCode: statusCode), ddRequestID: nil)
            XCTAssertNil(status.internalMonitoringError)
        }
    }

    func testWhenUploadFinishesWithError_andErrorCodeMeansSDKIssue_itCreatesInternalMonitoringError() throws {
        let alertingNSURLErrorCode = NSURLErrorBadURL
        let status = DataUploadStatus(networkError: NSError(domain: NSURLErrorDomain, code: alertingNSURLErrorCode, userInfo: nil))

        let error = try XCTUnwrap(status.internalMonitoringError, "Internal Monitoring error should be created for NSURLError code: \(alertingNSURLErrorCode)")
        XCTAssertEqual(error.message, "Data upload finished with error")
        let nsError = try XCTUnwrap(error.error) as NSError
        XCTAssertEqual(nsError.code, alertingNSURLErrorCode)
    }

    func testWhenUploadFinishesWithError_andErrorCodeMeansExternalFactors_itDoesNotCreateInternalMonitoringError() {
        let notAlertingNSURLErrorCode = NSURLErrorNetworkConnectionLost
        let status = DataUploadStatus(networkError: NSError(domain: NSURLErrorDomain, code: notAlertingNSURLErrorCode, userInfo: nil))
        XCTAssertNil(status.internalMonitoringError, "Internal Monitoring error should be created for NSURLError code: \(notAlertingNSURLErrorCode)")
    }
}
