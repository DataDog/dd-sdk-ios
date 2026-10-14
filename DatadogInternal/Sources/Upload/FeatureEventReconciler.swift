/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An optional capability for request builders that can reconcile persisted events before uploading them.
///
/// Core performs reconciliation on the feature's upload queue. Any failure falls back to uploading the
/// original events, without changing the persisted batch or its upload retry behavior.
public protocol FeatureEventReconciler: FeatureRequestBuilder {
    /// The response used to reconcile events.
    associatedtype Response

    /// Determines whether the batch needs a reconciliation request.
    func reconciliation(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) throws -> EventReconciliation

    /// Validates and decodes a reconciliation response.
    func response(from data: Data?, with response: HTTPURLResponse) throws -> Response

    /// Returns the events that still need uploading after reconciliation.
    func events(from events: [Event], using response: Response) throws -> [Event]
}

/// The next step in reconciling a persisted batch.
public enum EventReconciliation {
    /// Upload the original events without reconciliation.
    case skip
    /// Send this request before deciding which events still need uploading.
    case request(URLRequest)
    /// Complete the batch without a reconciliation request or an upload.
    case resolved
}
