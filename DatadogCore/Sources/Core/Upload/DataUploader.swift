/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import CommonCrypto

/// A type that performs data uploads.
internal protocol DataUploaderType {
    func upload(events: [Event], context: DatadogContext, previous: DataUploadStatus?) throws -> DataUploadStatus
}

/// Synchronously uploads data to server using `HTTPClient`.
internal final class DataUploader: DataUploaderType {
    /// An unreachable upload status - only meant to satisfy the compiler.
    private static let unreachableUploadStatus = DataUploadStatus(
        needsRetry: false,
        responseCode: nil,
        userDebugDescription: "",
        error: nil,
        attempt: 0
    )

    private let httpClient: HTTPClient
    private let requestBuilder: FeatureRequestBuilder

    init(httpClient: HTTPClient, requestBuilder: FeatureRequestBuilder) {
        self.httpClient = httpClient
        self.requestBuilder = requestBuilder
    }

    /// Uploads data synchronously (will block current thread) and returns the upload status.
    /// Uses timeout configured for `HTTPClient`.
    func upload(events: [Event], context: DatadogContext, previous: DataUploadStatus?) throws -> DataUploadStatus {
        var request = try requestBuilder.request(for: events, with: context)
        let attempt: UInt
        if let previous = previous {
            attempt = previous.attempt + 1
        } else {
            attempt = 0
        }

        let requestID = request.value(forHTTPHeaderField: URLRequestBuilder.HTTPHeader.ddRequestIDHeaderField)

        // check for any existing ddtags which could be added by feature request builders
        var ddTags: [String] = []
        if let existing = request.url?.queryItem("ddtags")?.value {
            request.url?.removeQueryItem(name: "ddtags")
            ddTags.append(existing)
        }

        // add retry related information
        ddTags.append("retry_count:\(attempt + 1)") // for reporting attempt always start from 1
        if let responseCode = previous?.responseCode {
            ddTags.append("last_failure_status:\(responseCode)")
        }

        request.url?.append(
            .init(
                name: "ddtags",
                value: ddTags.joined(separator: ",")
            )
        )

        // set idempotency key for POST
        if let body = request.httpBody {
            request.setValue(body.sha1(), forHTTPHeaderField: "DD-IDEMPOTENCY-KEY")
        }

        var uploadStatus: DataUploadStatus?

        let semaphore = DispatchSemaphore(value: 0)

        httpClient.send(request: request) { result in
            switch result {
            case .success(let httpResponse):
                uploadStatus = DataUploadStatus(
                    httpResponse: httpResponse,
                    ddRequestID: requestID,
                    attempt: attempt
                )
            case .failure(let error):
                uploadStatus = DataUploadStatus(
                    networkError: error,
                    attempt: attempt
                )
            }

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        return uploadStatus ?? DataUploader.unreachableUploadStatus
    }
}
