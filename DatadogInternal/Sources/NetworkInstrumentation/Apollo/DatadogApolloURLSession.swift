/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if Apollo
import Foundation
import Apollo

/// Custom URLSession wrapper for Apollo iOS v2 that enables Datadog network instrumentation.
///
/// Apollo iOS v2's default implementation uses `bytes(for:delegate:)` with `delegate: nil`, which
/// prevents URLSessionDataDelegate methods from being invoked. This wrapper uses `dataTask(with:)`
/// without a completion handler to ensure delegate methods fire, allowing Datadog's swizzling to
/// capture network data. It bridges delegate callbacks to async/await continuations and returns
/// data as an `AsyncChunkSequence` for Apollo v2 compatibility.
///
/// - Note: Must be used with `DatadogApolloDelegate`. Register the delegate via
///   `URLSessionInstrumentation.enable(with: .init(delegateClass: DatadogApolloDelegate.self))`
public final class DatadogApolloURLSession: NSObject, ApolloURLSession {
    private let urlSession: URLSession
    private let delegate: DatadogApolloDelegate

    /// Initializes a custom URLSession wrapper with Datadog instrumentation support.
    ///
    /// - Parameters:
    ///   - configuration: The URLSessionConfiguration to use for network requests
    ///   - delegate: The DatadogApolloDelegate that will handle network callbacks and be swizzled by Datadog
    public init(configuration: URLSessionConfiguration, delegate: DatadogApolloDelegate = .init()) {
        self.delegate = delegate
        self.urlSession = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        super.init()
    }

    /// Returns a data stream of the response chunks for the request.
    ///
    /// This implementation uses `dataTask(with:)` without a completion handler to ensure
    /// URLSessionDataDelegate methods are called, allowing both Datadog instrumentation
    /// and Apollo to receive the response data.
    ///
    /// - Parameter request: The URLRequest to execute
    /// - Returns: An async stream of data chunks and the URLResponse
    public func chunks(for request: URLRequest) async throws -> (any AsyncChunkSequence, URLResponse) {
        // Create a data task WITHOUT a completion handler to ensure delegate methods are called
        let (data, response) = try await withCheckedThrowingContinuation { continuation in
            let task = urlSession.dataTask(with: request)

            // Register the continuation with the delegate so it can resume when data is complete
            delegate.registerContinuation(for: task, continuation: continuation)

            task.resume()
        }

        let sequence = DataChunkSequence(data: data)
        return (sequence, response)
    }
}

/// A simple async sequence that yields a single chunk of data.
///
/// Apollo v2 expects an `AsyncChunkSequence` for processing responses. For most GraphQL requests,
/// the entire response is received as a single chunk, so this implementation yields the complete
/// data once and then terminates.
private struct DataChunkSequence: AsyncChunkSequence {
    let data: Data

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(data: data)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        private var data: Data?

        init(data: Data) {
            self.data = data
        }

        mutating func next() async throws -> Data? {
            defer { data = nil }
            return data
        }
    }
}
#endif
