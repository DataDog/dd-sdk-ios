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
    private let httpClient: HTTPClient
    private let requestBuilder: FeatureRequestBuilder
    /// Name of the feature this worker is performing uploads for.
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

    /// Uploads data synchronously (will block current thread) and returns the upload status.
    /// Uses timeout configured for `HTTPClient`.
    func upload(events: [Event], context: DatadogContext, previous: DataUploadStatus?) throws -> DataUploadStatus {
        let attempt: UInt
        if let previous = previous {
            attempt = previous.attempt + 1
        } else {
            attempt = 0
        }

        let execution: ExecutionContext = .init(previousResponseCode: previous?.responseCode, attempt: attempt)
        var reconciledEvents = events
        if let reconciler = requestBuilder as? any FeatureEventReconciler {
            reconciledEvents = self.reconciledEvents(events, with: reconciler, context: context, execution: execution)
            if reconciledEvents.isEmpty {
                return DataUploadStatus(
                    needsRetry: false,
                    isReconciled: true,
                    responseCode: nil,
                    userDebugDescription: "[batch resolved by reconciliation]",
                    error: nil,
                    attempt: attempt
                )
            }
        }

        let request = try requestBuilder.request(for: reconciledEvents, with: context, execution: execution)
        let requestID = request.value(forHTTPHeaderField: URLRequestBuilder.HTTPHeader.ddRequestIDHeaderField)

        switch send(request: request) {
        case .success(let (httpResponse, _)):
            return DataUploadStatus(
                httpResponse: httpResponse,
                ddRequestID: requestID,
                attempt: attempt
            )
        case .failure(let error):
            return DataUploadStatus(networkError: error, attempt: attempt)
        }
    }

    private func reconciledEvents(
        _ events: [Event],
        with reconciler: any FeatureEventReconciler,
        context: DatadogContext,
        execution: ExecutionContext
    ) -> [Event] {
        do {
            switch try reconciler.reconciliation(for: events, with: context, execution: execution) {
            case .skip:
                return events
            case .resolved:
                return []
            case .request(let request):
                let (httpResponse, data) = try send(request: request).get()
                guard (200..<300).contains(httpResponse.statusCode) else {
                    return events
                }
                return try reconciler.reconcile(from: events, using: httpResponse, data: data)
            }
        } catch {
            // Reconciliation is optional and should not prevent the batch from being sent
            return events
        }
    }

    private func send(request: URLRequest) -> Result<(HTTPURLResponse, Data?), Error> {
        var result: Result<(HTTPURLResponse, Data?), Error>?
        let semaphore = DispatchSemaphore(value: 0)

#if DD_BENCHMARK
        let delegate: URLSessionTaskDelegate = BenchmarkURLSessionTaskDelegate(track: featureName)
#else
        let delegate: URLSessionTaskDelegate? = nil
#endif

        httpClient.send(request: request, delegate: delegate) {
            result = $0
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)

#if DD_BENCHMARK
        bench.meter.counter(metric: "ios.benchmark.bytes_uploaded")
            .increment(by: request.httpBody?.count ?? 0, attributes: ["track": featureName])
#endif

        return result ?? .failure(URLSessionTransportInconsistencyException())
    }
}
