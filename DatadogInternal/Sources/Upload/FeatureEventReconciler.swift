/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An optional capability for request builders that can reconcile persisted events before uploading them.
///
/// The uploader calls ``reconciliation(for:with:execution:)`` on the feature's upload queue to decide whether
/// to send a reconciliation request, upload the original events, or complete the batch.
///
/// If the reconciliation request succeeds, it calls ``reconcile(from:using:data:)`` with the original batch
/// and the response to select the events that still need uploading.
///
/// It passes those events to ``FeatureRequestBuilder/request(for:with:execution:)`` to build the upload request,
/// or completes the batch if none remain.
///
/// If reconciliation fails, it uploads the original events without changing the persisted batch or its
/// upload retry behavior.
public protocol FeatureEventReconciler: FeatureRequestBuilder {
    /// Determines whether the batch needs a reconciliation request.
    func reconciliation(
        for events: [Event],
        with context: DatadogContext,
        execution: ExecutionContext
    ) throws -> EventReconciliation

    /// Decodes the reconciliation response and returns the events that still need uploading.
    func reconcile(from events: [Event], using response: HTTPURLResponse, data: Data?) throws -> [Event]
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
