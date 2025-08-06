/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Fields of the Upload Cycle Metric.
///
/// This metric is not sent to Telemetry as-is, values are sent on the message-bus
/// and aggregated internally by RUM's message receiver. The aggregate is sent as an
/// attribute of the "RUM Session Ended" metric.
public enum UploadCycleMetric {
    /// Metric's name
    public static let name = "upload_cycle"
    /// The Metrics' upload track, or feature name.
    public static let track = "track"
}
