/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Available strategies for sampling trace propagation headers.
@objc
public class DDTraceSamplingStrategy: NSObject {
    internal let swiftType: DatadogInternal.TraceSamplingStrategy

    /// Trace propagation headers will be sampled same as propagated span.
    ///
    /// Use this option to leverage head-based sampling, where the decision to keep or drop the trace
    /// is determined from the first span of the trace, the head, when the trace is created. With `.headBased`
    /// strategy, this decision is propagated through the request context to downstream services.
    @objc
    public static func headBased() -> DDTraceSamplingStrategy {
        return DDTraceSamplingStrategy(swiftType: .headBased)
    }

    /// Trace propagation headers will be sampled independently from sampling decision in propagated span.
    ///
    /// Use this option to apply the provided `sampleRate` for determining the decision to keep or drop the trace
    /// in downstream services independently of sampling their parent span.
    @objc
    public static func custom(sampleRate: Float) -> DDTraceSamplingStrategy {
        return DDTraceSamplingStrategy(swiftType: .custom(sampleRate: sampleRate))
    }

    private init(swiftType: DatadogInternal.TraceSamplingStrategy) {
        self.swiftType = swiftType
    }
}
