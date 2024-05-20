/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An immutable version of `URLRequest`.
///
/// Introduced in response to concerns raised in https://github.com/DataDog/dd-sdk-ios/issues/1638
/// it makes a copy of request attributes, safeguarding against potential thread safety issues arising from concurrent
/// mutations (see more context in https://github.com/DataDog/dd-sdk-ios/pull/1767 ).
public struct ImmutableRequest {
    /// The URL of the request.
    public let url: URL?
    /// The HTTP method of the request.
    public let httpMethod: String?
    /// The value of `x-datadog-origin` header (if any).
    public let ddOriginHeaderValue: String?
    /// A reference to the original `URLRequest` object provided during initialization. Direct use is discouraged
    /// due to thread safety concerns. Instead, necessary attributes should be accessed through `ImmutableRequest` fields.
    public let unsafeOriginal: URLRequest

    public init(request: URLRequest) {
        self.url = request.url
        self.httpMethod = request.httpMethod
        // RUM-3183: As observed in https://github.com/DataDog/dd-sdk-ios/issues/1638, accessing `request.allHTTPHeaderFields` is not
        // safe and can lead to crashes with undefined root cause. To avoid issues we should prefer `request.value(forHTTPHeaderField:)`
        // when interacting with `URLRequest`.
        self.ddOriginHeaderValue = request.value(forHTTPHeaderField: TracingHTTPHeaders.originField)
        self.unsafeOriginal = request
    }
}
