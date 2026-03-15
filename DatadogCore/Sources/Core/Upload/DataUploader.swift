/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import CommonCrypto

/// A type that performs data uploads.
internal protocol DataUploaderType: Sendable {
    func upload(events: [Event], context: DatadogContext, previous: DataUploadStatus?) async throws -> DataUploadStatus
}

/// Uploads data to server using `HTTPClient`.
internal final class DataUploader: DataUploaderType, Sendable {
    private let httpClient: HTTPClient
    private let requestBuilder: FeatureRequestBuilder
    private let featureName: String

    init(
        httpClient: HTTPClient,
        requestBuilder: FeatureRequestBuilder,
        featureName: String
    ) {
        self.httpClient = httpClient
        self.requestBuilder = requestBuilder
        self.featureName = featureName
    }

    func upload(events: [Event], context: DatadogContext, previous: DataUploadStatus?) async throws -> DataUploadStatus {
        let attempt: UInt = previous.map { $0.attempt + 1 } ?? 0
        let execution: ExecutionContext = .init(previousResponseCode: previous?.responseCode, attempt: attempt)
        let request = try requestBuilder.request(for: events, with: context, execution: execution)
        let requestID = request.value(forHTTPHeaderField: URLRequestBuilder.HTTPHeader.ddRequestIDHeaderField)

#if DD_BENCHMARK
        let delegate: URLSessionTaskDelegate = BenchmarkURLSessionTaskDelegate(track: featureName)
#else
        let delegate: URLSessionTaskDelegate? = nil
#endif

        do {
            let httpResponse = try await httpClient.send(request: request, delegate: delegate)

#if DD_BENCHMARK
            bench.meter.counter(metric: "ios.benchmark.bytes_uploaded")
                .increment(by: request.httpBody?.count ?? 0, attributes: ["track": featureName])
#endif

            return DataUploadStatus(
                httpResponse: httpResponse,
                ddRequestID: requestID,
                attempt: attempt
            )
        } catch {
            return DataUploadStatus(
                networkError: error,
                attempt: attempt
            )
        }
    }
}
