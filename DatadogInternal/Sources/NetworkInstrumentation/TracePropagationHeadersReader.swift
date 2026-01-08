/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Interface that defines shared responsibilities of HTTP header readers.
public protocol TracePropagationHeadersReader {
    func read() -> (
        traceID: TraceID,
        spanID: SpanID,
        parentSpanID: SpanID?
    )?

    /// This trace sampling priority based on the provided headers.
    var samplingPriority: SamplingPriority? { get }

    /// The sampling decision maker mechanism based on the provided headers.
    var samplingDecisionMaker: SamplingMechanismType? { get }
}
