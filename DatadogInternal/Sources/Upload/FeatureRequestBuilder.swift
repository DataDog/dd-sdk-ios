/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `FeatureRequestBuilder` defines an interface for building a single `URLRequest`
/// for a list of data events and the current core context.
///
/// A Feature should use this interface for creating requests that needs be sent to its Datadog Intake.
/// The request will be transported by `DatadogCore`.
public protocol FeatureRequestBuilder {
    /// Builds an `URLRequest` for a list of events and the current core context to be uploaded
    /// to the Feature's Intake.
    ///
    /// The returned request must include all necessary information, i.e. HTTP headers and
    /// URL queries required by the Feature's Intake. The request will be sent by the core.
    ///
    /// **Note:** When `Error` is thrown, underlying data will be dropped permanently and never retried. The
    /// implementation should make a wise consideration of throwing vs recovering strategy.
    ///
    /// - Parameters:
    ///   - context: The current core context.
    ///   - events: The events data to be uploaded.
    /// - Returns: The URL request.
    func request(for events: [Event], with context: DatadogContext) throws -> URLRequest
}
