/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
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

    let error: DataUploadError?
}

extension DataUploadStatus {
    // MARK: - Initialization

    init(httpResponse: HTTPURLResponse, ddRequestID: String?) {
        let statusCode = HTTPResponseStatusCode(rawValue: httpResponse.statusCode) ?? .unexpected

        self.init(
            needsRetry: statusCode.needsRetry,
            userDebugDescription: "[response code: \(httpResponse.statusCode) (\(statusCode)), request ID: \(ddRequestID ?? "(???)")]",
            error: DataUploadError(status: httpResponse.statusCode)
        )
    }

    init(networkError: Error) {
        self.init(
            needsRetry: true, // retry this upload as it failed due to network transport isse
            userDebugDescription: "[error: \(DDError(error: networkError).message)]", // e.g. "[error: A data connection is not currently allowed]"
            error: DataUploadError(networkError: networkError)
        )
    }
}

// MARK: - Data Upload Errors

internal enum DataUploadError: Error, Equatable {
    case unauthorized
    case httpError(statusCode: Int)
    case networkError(error: NSError)
}

/// A list of known NSURLError codes which should not produce error in Telemetry.
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

extension DataUploadError {
    init?(status code: Int) {
        guard let responseStatusCode = HTTPResponseStatusCode(rawValue: code) else {
            // If status code is unexpected, do not produce an error for internal Telemetry - otherwise monitoring may
            // become too verbose for old installations if we introduce a new status code in the API.
            return nil
        }

        switch responseStatusCode {
        case .accepted:
            return nil
        case .unauthorized, .forbidden:
            self = .unauthorized
        case .internalServerError, .serviceUnavailable:
            // These codes mean Datadog service issue - do not produce SDK error as this is already monitored by other means.
            return nil
        case .badRequest, .payloadTooLarge, .tooManyRequests, .requestTimeout:
            // These codes mean that something wrong is happening either in the SDK or on the server - produce an error.
            self = .httpError(statusCode: code)
        case .unexpected:
            return nil
        }
    }

    init?(networkError: Error) {
        let nsError = networkError as NSError
        guard nsError.domain == NSURLErrorDomain, !ignoredNSURLErrorCodes.contains(nsError.code) else {
            return nil
        }

        self = .networkError(error: nsError)
    }
}
