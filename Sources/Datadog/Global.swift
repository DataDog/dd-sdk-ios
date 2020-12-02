/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

/// Namespace storing global Datadog components.
public struct Global {
    /// Shared tracer instance to use throughout the app.
    public static var sharedTracer: OTTracer = DDNoopGlobals.tracer

    /// Shared RUM monitor instance to use throughout the app.
    public static var rum: DDRUMMonitor = DDNoopRUMMonitor()

    /// Tracing context read from environment variables if injected
    internal static var environmentContext: (spanID: TracingUUID, traceID: TracingUUID)? {
        guard let traceIDValue = ProcessInfo.processInfo.environment[TracingHTTPHeaders.traceIDField],
              let spanIDValue = ProcessInfo.processInfo.environment[TracingHTTPHeaders.parentSpanIDField],
              let traceID = UInt64(traceIDValue).flatMap({ TracingUUID(rawValue: $0) }),
              let spanID = UInt64(spanIDValue).flatMap({ TracingUUID(rawValue: $0) }) else {
            return nil
        }
        return (spanID, traceID)
    }
}
