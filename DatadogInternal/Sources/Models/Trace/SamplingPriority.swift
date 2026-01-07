/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The sampling priority for a trace span.
public enum SamplingPriority: Int {
    /// The span is not sampled based on a manual override.
    case manualDrop = -1
    /// The span is not sampled based on a sampler decision.
    case autoDrop = 0
    /// The span is sampled based on a sampler decision.
    case autoKeep = 1
    /// The span is sampled based on a manual override.
    case manualKeep = 2

    /// `true` if the span is sampled, `false` otherwise.
    public var isKept: Bool {
        switch self {
        case .manualDrop, .autoDrop: false
        case .manualKeep, .autoKeep: true
        }
    }
}
