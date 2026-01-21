/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public class W3CHTTPHeadersReader: TracePropagationHeadersReader {
    typealias Constants = W3CHTTPHeaders.Constants

    private let httpHeaderFields: [String: String]

    public init(httpHeaderFields: [String: String]) {
        self.httpHeaderFields = httpHeaderFields
    }

    public func read() -> (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? {
        let values = httpHeaderFields[W3CHTTPHeaders.traceparent]?.components(
            separatedBy: W3CHTTPHeaders.Constants.separator
        )

        guard let traceIDValue = values?.dd[safe: 1],
              let spanIDValue = values?.dd[safe: 2],
              values?.dd[safe: 3] != W3CHTTPHeaders.Constants.unsampledValue,
              let traceID = TraceID(traceIDValue, representation: .hexadecimal),
              let spanID = SpanID(spanIDValue, representation: .hexadecimal)
        else {
            return nil
        }

        return (
            traceID: traceID,
            spanID: spanID,
            parentSpanID: nil
        )
    }

    public var samplingPriority: SamplingPriority? {
        if let tracestate,
           let priorityStringValue = tracestate[Substring(Constants.sampling)],
           let priority = SamplingPriority(string: priorityStringValue) {
            return priority
        } else if let traceparent = httpHeaderFields[W3CHTTPHeaders.traceparent] {
            guard let sampledHeaderValue = traceparent.components(separatedBy: W3CHTTPHeaders.Constants.separator).last else {
                return nil
            }
            let sampled = sampledHeaderValue == W3CHTTPHeaders.Constants.sampledValue
            return sampled ? .autoKeep : .autoDrop
        }

        return nil
    }

    public var samplingDecisionMaker: SamplingMechanismType? {
        if let tracestate,
           let decisionMakerStringValue = tracestate[Substring(Constants.samplingDecisionMaker)],
           let decisionMakerTag = Self.parseDecisionMakerTag(fromValue: decisionMakerStringValue),
           let decisionMaker = SamplingMechanismType(rawValue: String(decisionMakerTag)) {
            return decisionMaker
        }

        return nil
    }

    /// Parses the contents of the `tracestate` header to a dictionary of `Substring`.
    ///
    /// - returns: Dictionary of `tracestate` header keys and values if such header exists in the parsed request,
    /// `nil` otherwise.
    private lazy var tracestate: [Substring: Substring]? = {
        guard let tracestate = httpHeaderFields[W3CHTTPHeaders.tracestate] else {
            return nil
        }

        // These two variables are needed since the split function that takes a collection instead of an element
        // is only available in iOS 16. The compiler usually turns something like "=" passed in as an argument
        // to the split function into a String.Element (aka, a Character) but it can't do that when those are
        // defined as Strings in the Constants enum.
        let tracestatePairSeparator = Constants.tracestatePairSeparator[Constants.tracestatePairSeparator.startIndex]
        let tracestateKeyValueSeparator = Constants.tracestateKeyValueSeparator[Constants.tracestateKeyValueSeparator.startIndex]

        let pairs = tracestate
            .split(separator: tracestatePairSeparator)
            .compactMap { keyValueString -> (Substring, Substring)? in
                let elements = keyValueString.split(separator: tracestateKeyValueSeparator, maxSplits: 1)
                guard elements.count == 2 else {
                    return nil
                }
                return (elements[0], elements[1])
            }

        return Dictionary(pairs) { lhs, rhs in
            rhs
        }
    }()
}
