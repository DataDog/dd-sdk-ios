/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

private enum HTTPResponseStatusCode: Int {
    /// The request has been accepted for processing.
    case accepted = 202
    /// The server cannot or will not process the request (client error).
    case badRequest = 400
    /// The request lacks valid authentication credentials.
    case unauthorized = 401
    /// The server understood the request but refuses to authorize it.
    case forbidden = 403
    /// The server would like to shut down the connection.
    case requestTimeout = 408
    /// The request entity is larger than limits defined by server.
    case payloadTooLarge = 413
    /// The client has sent too many requests in a given amount of time.
    case tooManyRequests = 429
    /// The server encountered an unexpected condition.
    case internalServerError = 500
    /// The server is not ready to handle the request probably because it is overloaded.
    case serviceUnavailable = 503
    /// An unexpected status code.
    case unexpected = -999

    /// If it makes sense to retry the upload finished with this status code, e.g. if data upload failed due to `503` HTTP error, we should retry it later.
    var needsRetry: Bool {
        switch self {
        case .accepted, .badRequest, .unauthorized, .forbidden, .payloadTooLarge:
            // No retry - it's either success or a client error which won't be fixed in next upload.
            return false
        case .requestTimeout, .tooManyRequests, .internalServerError, .serviceUnavailable:
            // Retry - it's a temporary server or connection issue that might disappear on next attempt.
            return true
        case .unexpected:
            // This shouldn't happen, but if receiving an unexpected status code we do not retry.
            // This is safer than retrying as we don't know if the issue is coming from the client or server.
            return false
        }
    }
}

/// The status of a single upload attempt.
internal struct DataUploadStatus {
    /// If upload needs to be retried (`true`) because its associated data was not delivered but it may succeed
    /// in the next attempt (i.e. it failed due to device leaving signal range or a temporary server unavailability occured).
    /// If set to `false` then data associated with the upload should be deleted as it does not need any more upload
    /// attempts (i.e. the upload succeeded or failed due to unrecoverable client error).
    let needsRetry: Bool

    // MARK: - Debug Info

    /// Upload status description printed to the console if SDK `.debug` verbosity is enabled.
    let userDebugDescription: String

    /// An optional error printed to the console if SDK `.error` (or lower) verbosity is enabled.
    /// It is meant to indicate user action that must be taken to fix the upload issue (e.g. if the client token is invalid, it needs to be fixed).
    let userErrorMessage: String?

    /// An optional error logged to the Internal Monitoring feature (if it's enabled).
    let internalMonitoringError: (message: String, error: Error?, attributes: [String: String]?)?
}

extension DataUploadStatus {
    // MARK: - Initialization

    init(httpResponse: HTTPURLResponse, ddRequestID: String?) {
        let statusCode = HTTPResponseStatusCode(rawValue: httpResponse.statusCode) ?? .unexpected

        self.init(
            needsRetry: statusCode.needsRetry,
            userDebugDescription: "[response code: \(httpResponse.statusCode) (\(statusCode)), request ID: \(ddRequestID ?? "(???)")]",
            userErrorMessage: statusCode == .unauthorized ? "⚠️ The client token you provided seems to be invalid." : nil,
            internalMonitoringError: createInternalMonitoringErrorIfNeeded(for: httpResponse.statusCode, requestID: ddRequestID)
        )
    }

    init(networkError: Error) {
        self.init(
            needsRetry: true, // retry this upload as it failed due to network transport isse
            userDebugDescription: "[error: \(DDError(error: networkError).message)]", // e.g. "[error: A data connection is not currently allowed]"
            userErrorMessage: nil, // nothing actionable for the user
            internalMonitoringError: createInternalMonitoringErrorIfNeeded(for: networkError)
        )
    }
}

// MARK: - Internal Monitoring

#if DD_SDK_ENABLE_INTERNAL_MONITORING
/// Looks at the `statusCode` and produces error for Internal Monitoring feature if anything is going wrong.
private func createInternalMonitoringErrorIfNeeded(
    for statusCode: Int, requestID: String?
) -> (message: String, error: Error?, attributes: [String: String]?)? {
    guard let responseStatusCode = HTTPResponseStatusCode(rawValue: statusCode) else {
        // If status code is unexpected, do not produce an error for Internal Monitoring - otherwise monitoring may
        // become too verbose for old installations if we introduce a new status code in the API.
        return nil
    }

    switch responseStatusCode {
    case .accepted, .unauthorized, .forbidden:
        // These codes mean either success or the user configuration mistake - do not produce error.
        return nil
    case .internalServerError, .serviceUnavailable:
        // These codes mean Datadog service issue - do not produce SDK error as this is already monitored by other means.
        return nil
    case .badRequest, .payloadTooLarge, .tooManyRequests, .requestTimeout:
        // These codes mean that something wrong is happening either in the SDK or on the server - produce an error.
        return (
            message: "Data upload finished with status code: \(statusCode)",
            error: nil,
            attributes: ["dd_request_id": requestID ?? "(???)"]
        )
    case .unexpected:
        return nil
    }
}

/// A list of known NSURLError codes which should not produce error in Internal Monitoring.
/// Receiving these codes doesn't mean SDK issue, but the network transportation scenario where the connection interrupted due to external factors.
/// These list should evolve and we may want to add more codes in there.
///
/// Ref.: https://developer.apple.com/documentation/foundation/1508628-url_loading_system_error_codes
private let ignoredNSURLErrorCodes = Set([
    NSURLErrorNetworkConnectionLost, // -1005
    NSURLErrorTimedOut, // -1001
    NSURLErrorCannotParseResponse, // - 1017
    NSURLErrorNotConnectedToInternet, // -1009
    NSURLErrorCannotFindHost, // -1003
    NSURLErrorSecureConnectionFailed, // -1200
    NSURLErrorDataNotAllowed, // -1020
    NSURLErrorCannotConnectToHost, // -1004
])

/// Looks at the `networkError` and produces error for Internal Monitoring feature if anything is going wrong.
private func createInternalMonitoringErrorIfNeeded(
    for networkError: Error
) -> (message: String, error: Error?, attributes: [String: String]?)? {
    let nsError = networkError as NSError
    if nsError.domain == NSURLErrorDomain && !ignoredNSURLErrorCodes.contains(nsError.code) {
        return (message: "Data upload finished with error", error: nsError, attributes: nil)
    } else {
        return nil
    }
}
#else
private func createInternalMonitoringErrorIfNeeded(
    for statusCode: Int, requestID: String?
) -> (message: String, error: Error?, attributes: [String: String]?)? {
    return nil
}

private func createInternalMonitoringErrorIfNeeded(
    for networkError: Error
) -> (message: String, error: Error?, attributes: [String: String]?)? {
    return nil
}
#endif
