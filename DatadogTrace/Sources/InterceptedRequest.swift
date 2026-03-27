/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension Trace.Configuration {
    /// An immutable snapshot of a network request, passed to ``SpanCustomization`` callbacks.
    ///
    /// Properties are copied from the original `URLRequest` at interception time and are safe to read
    /// from any thread.
    public struct InterceptedRequest {
        /// The URL of the request.
        public let url: URL?
        /// The HTTP method of the request (e.g. `"GET"`, `"POST"`).
        public let httpMethod: String?
        /// The body data of the request.
        public let httpBody: Data?
    }
}

internal extension Trace.Configuration.InterceptedRequest {
    init(from request: ImmutableRequest) {
        self.url = request.url
        self.httpMethod = request.httpMethod
        // httpBody is Data? — safe to access; the thread-safety concern in ImmutableRequest
        // applies only to allHTTPHeaderFields (bridged NSMutableDictionary).
        self.httpBody = request.unsafeOriginal.httpBody
    }
}
