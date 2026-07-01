/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Definition of the "Trace Client Stats Flushed" telemetry.
///
/// Emitted on the client-side stats flush path so we can confirm, during dogfooding and in
/// production, that stats are actually being produced and that the aggregated numbers look
/// sane. It is the CSS-specific counterpart to the core's generic upload telemetry.
///
/// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
internal enum TraceClientStatsFlushedMetric {
    /// The name of this metric, included in the telemetry log.
    static let name = "Trace Client Stats Flushed"
    /// Metric type value.
    static let typeValue = "trace client stats flushed"

    /// The number of buckets exported in this flush.
    static let bucketsCountKey = "buckets_count"
    /// The total number of aggregation groups across all exported buckets.
    static let groupsCountKey = "groups_count"
    /// The total number of spans aggregated into this flush (sum of group hits).
    static let spansCountKey = "spans_count"
    /// The total number of errored spans across all groups (sum of group errors).
    static let errorsCountKey = "errors_count"
    /// Whether the flush was forced (SDK teardown) rather than a periodic flush.
    static let forcedKey = "forced"
}
