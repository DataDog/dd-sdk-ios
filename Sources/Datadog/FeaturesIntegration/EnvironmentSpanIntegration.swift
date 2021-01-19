/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

fileprivate struct EnvironmentSpanIntegration {
    /// Tracing context read from environment variables if injected
    static var environmentContext: (spanID: String, traceID: String)? {
        guard let spanIDValue = ProcessInfo.processInfo.environment[TracingHTTPHeaders.parentSpanIDField] ,
              let traceIDValue = ProcessInfo.processInfo.environment[TracingHTTPHeaders.traceIDField] else {
            return nil
        }
        return (spanIDValue, traceIDValue)
    }
}

internal struct TracingWithEnvironmentSpanIntegration {
    /// Span context to be attached to all root spans in order to continue the trace
    /// injected by external process through ENV variables.
    var environmentSpanContext: (spanID: TracingUUID, traceID: TracingUUID)? {
        guard let environmentContext = EnvironmentSpanIntegration.environmentContext,
              let spanID = UInt64(environmentContext.spanID).flatMap({ TracingUUID(rawValue: $0) }),
              let traceID = UInt64(environmentContext.traceID).flatMap({ TracingUUID(rawValue: $0) }) else {
            return nil
        }
        return (spanID, traceID)
    }
}

internal struct LoggingWithEnvironmentSpanIntegration {
    struct Attributes {
        static let spanID = "dd.span_id"
        static let traceID = "dd.trace_id"
    }
    /// Additional log attributes describing the ENV span injected by external process.
    /// Adding those attributes to `Log` will correlate them with that span.
    var environmentSpanAttributes: [String: Encodable]? {
        guard let environmentContext = EnvironmentSpanIntegration.environmentContext else {
            return nil
        }
        return [
            Attributes.spanID: environmentContext.spanID,
            Attributes.traceID: environmentContext.traceID
        ]
    }
}
