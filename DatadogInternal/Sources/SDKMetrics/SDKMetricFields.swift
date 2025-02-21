/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Common fields in SDK metrics.
public enum SDKMetricFields {
    /// Metric type key. It expects `String` value.
    public static let typeKey = "metric_type"
    /// The first sample rate applied to the metric.
    public static let headSampleRate = "head_sample_rate"
    /// Key referencing the session ID (`String`) that the metric should be sent with. It expects `String` value.
    ///
    /// When attached to metric attributes, the value of this key (session ID) will be used to replace
    /// the ID of session that the metric was collected in. The key itself is dropped before the metric is sent.
    public static let sessionIDOverrideKey = "session_id_override"
}
