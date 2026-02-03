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

    /// Indicates whether the trace was sampled based on the provided headers.
    var sampled: Bool? { get }
}

extension TracePropagationHeadersReader {
    public var sampled: Bool? {
        samplingPriority?.isKept
    }

    /// Helper function that parses "4" from a "-4" string.
    ///
    /// In the headers, the value of the decision maker key/value pair has the form of a dash and a number,
    /// like "-4". This is not negative 4, it's defined as a separator and a positive integer. This function extracts
    /// the last substring for a substring in this format.
    ///
    /// - parameters:
    ///    - value: A substring in the format of "-x" as described above.
    ///
    /// - returns: The part of the input substring after the last dash if it exists, `nil` otherwise.
    static func parseDecisionMakerTag(fromValue value: Substring) -> Substring? {
        value.split(separator: "-", omittingEmptySubsequences: true).last
    }
}
