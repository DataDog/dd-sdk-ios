/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The `FeatureRequestBuilder` defines an interface for building a single `URLRequest`
/// for a list of data events and the current core context.
///
/// The core implementation can use the interface for creating requests targetting datadog intake
/// of a given feature.
/* public */ internal protocol FeatureRequestBuilder {
    /// Builds a `URLRequest` for a list of events and the current core context to be uploaded
    /// to the feature intake.
    ///
    /// The returned request must include all necessary information, including HTTP headers and
    /// URL queries for the intake to ingest the payload. The request will be sent as is by the core
    /// uploader.
    ///
    /// - Parameters:
    ///   - context: The current core context.
    ///   - events: The events data to upload.
    /// - Returns: The URL request.
    func request(for events: [Data], with context: DatadogContext) -> URLRequest
}
