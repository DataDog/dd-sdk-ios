/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal


/// Mechanism used for sampling in ``SamplingDecision``.
internal protocol SamplingMechanism {
    /// The sampling priority provided by this mechanism.
    var samplingPriority: SamplingPriority { get }
}

/// Mechanism with a fixed, pre-computed value.
internal struct FixedValueMechanism: SamplingMechanism {
    /// The sampling priority provided by this mechanism.
    let samplingPriority: SamplingPriority
}
