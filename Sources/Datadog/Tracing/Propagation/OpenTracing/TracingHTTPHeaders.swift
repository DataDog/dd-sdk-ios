/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Trace propagation headers as explained in
/// https://docs.datadoghq.com/real_user_monitoring/connect_rum_and_traces/?tab=browserrum#how-are-rum-resources-linked-to-traces
internal enum TracingHTTPHeaders {
    /// Trace propagation header.
    /// It is used both in Tracing and RUM features.
    static let traceIDField = "x-datadog-trace-id"

    /// Trace propagation header.
    /// In RUM - it allows Datadog to generate the first span from the trace.
    /// In Tracing - it injects the `spanID` of mobile span so downstream spans can be properly linked in distributed tracing.
    static let parentSpanIDField = "x-datadog-parent-id"

    /// To make sure that the Agent keeps the trace.
    /// It is used both in Tracing and RUM features.
    static let samplingPriorityField = "x-datadog-sampling-priority"

    /// To make sure the generated traces from RUM don’t affect APM Index Spans counts.
    /// **Note:** it is only added to requests that we create RUM Resource for (it is not injected when RUM feature is disabled and only Tracing is used).
    static let ddOrigin = (field: "x-datadog-origin", value: "rum")
}
