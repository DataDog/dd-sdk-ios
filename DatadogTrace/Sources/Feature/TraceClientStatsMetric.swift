/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Definition of the "Trace Client Stats" telemetry.
///
/// Emitted on the client-side stats flush path so we can confirm, during dogfooding and in
/// production, that stats are actually being produced and that the aggregated numbers look
/// sane. It is the CSS-specific counterpart to the core's generic upload telemetry.
///
/// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
internal enum TraceClientStatsMetric {
    /// The name of this metric, included in the telemetry log.
    static let name = "Trace Client Stats"
    /// Metric type value.
    static let typeValue = "trace client stats"

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

    /// A separate metric counts spans collapsed by the per-bucket cardinality limit.
    static let collapsedSpansName = "Trace Client Stats Collapsed Spans"
    static let collapsedSpansTypeValue = "trace client stats collapsed spans"
    static let collapsedSpansCountKey = "collapsed_spans_count"
    static let maxGroupsPerBucketKey = "max_groups_per_bucket"
}

/// Builds and emits the "Trace Client Stats" telemetry, keeping the metric responsibility
/// out of `ClientStatsFeature`.
internal struct TraceClientStatsMetricController {
    let telemetry: Telemetry

    /// Reports cardinality loss without including resource names, peer tags or deployment values.
    func sendCollapsedSpans(count: UInt64, limit: Int) {
        guard count > 0 else {
            return
        }
        telemetry.metric(
            name: TraceClientStatsMetric.collapsedSpansName,
            attributes: [
                SDKMetricFields.typeKey: TraceClientStatsMetric.collapsedSpansTypeValue,
                TraceClientStatsMetric.collapsedSpansCountKey: count,
                "collapsed": "whole_key",
                TraceClientStatsMetric.maxGroupsPerBucketKey: limit
            ]
        )
    }

    /// Emits the metric summarizing what a non-empty flush produced.
    func send(for buckets: [ExportedBucket], force: Bool) {
        var groupsCount = 0
        var spansCount: UInt64 = 0
        var errorsCount: UInt64 = 0
        for bucket in buckets {
            groupsCount += bucket.stats.count
            for group in bucket.stats {
                spansCount += group.hits
                errorsCount += group.errors
            }
        }

        telemetry.metric(
            name: TraceClientStatsMetric.name,
            attributes: [
                SDKMetricFields.typeKey: TraceClientStatsMetric.typeValue,
                TraceClientStatsMetric.bucketsCountKey: buckets.count,
                TraceClientStatsMetric.groupsCountKey: groupsCount,
                TraceClientStatsMetric.spansCountKey: spansCount,
                TraceClientStatsMetric.errorsCountKey: errorsCount,
                TraceClientStatsMetric.forcedKey: force
            ]
        )
    }
}
