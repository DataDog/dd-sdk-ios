/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public protocol UploadPerformancePreset {
    /// Initial upload delay (in seconds).
    /// At runtime, the upload interval starts with `initialUploadDelay` and then ranges from `minUploadDelay` to `maxUploadDelay` depending
    /// on delivery success or failure.
    var initialUploadDelay: TimeInterval { get }
    /// Mininum  interval of data upload (in seconds).
    var minUploadDelay: TimeInterval { get }
    /// Maximum interval of data upload (in seconds).
    var maxUploadDelay: TimeInterval { get }
    /// If upload succeeds or fails, current interval is changed by this rate. Should be less or equal `1.0`.
    /// E.g: if rate is `0.1` then `delay` can be increased or decreased by `delay * 0.1`.
    var uploadDelayChangeRate: Double { get }
    /// Number of batches to process during one upload cycle.
    var maxBatchesPerUpload: Int { get }
    /// Enable uploads on networks with "Low Data Mode" enabled. Default is `true`.
    var constrainedNetworkAccessEnabled: Bool { get }
}
