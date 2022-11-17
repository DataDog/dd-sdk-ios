/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The `OpenTelemetryHTTPHeadersWriter` should be used to inject trace propagation headers to
/// the network requests send to the backend instrumented with Datadog APM.
/// The injected headers conform to [Open Telemetry](https://github.com/openzipkin/b3-propagation) standard.
///
/// Usage:
///
///     var request = URLRequest(...)
///
///     let writer = OpenTelemetryHTTPHeadersWriter(openTelemetryHeaderType: .single)
///     let span = Global.sharedTracer.startSpan("network request")
///     writer.inject(spanContext: span.context)
///
///     writer.tracePropagationHTTPHeaders.forEach { (field, value) in
///         request.setValue(value, forHTTPHeaderField: field)
///     }
///
///     // call span.finish() when the request completes
///
///
public class OpenTelemetryHTTPHeadersWriter: OTHTTPHeadersWriter {
    /// Open Telemetry header type.
    ///
    /// There are two encodings of B3:
    /// [Single Header](https://github.com/openzipkin/b3-propagation#single-header)
    /// and [Multiple Header](https://github.com/openzipkin/b3-propagation#multiple-headers).
    ///
    /// Multiple header encoding uses an `X-B3-` prefixed header per item in the trace context.
    /// Single header delimits the context into into a single entry named b3.
    /// The single-header variant takes precedence over the multiple header one when extracting fields.
    public enum OpenTelemetryHeaderType {
        case multiple, single
    }

    /// A dictionary with HTTP Headers required to propagate the trace started in the mobile app
    /// to the backend instrumented with Datadog APM.
    ///
    /// Usage:
    ///
    ///     writer.tracePropagationHTTPHeaders.forEach { (field, value) in
    ///         request.setValue(value, forHTTPHeaderField: field)
    ///     }
    ///
    public private(set) var tracePropagationHTTPHeaders: [String: String] = [:]

    /// The tracing sampler.
    ///
    /// This value will decide of the `X-B3-Sampled` header field value
    /// and if `X-B3-TraceId`, `X-B3-SpanId` and `X-B3-ParentSpanId` are propagated.
    private let sampler: Sampler

    /// Determines the type of telemetry header type used by the writer.
    private let openTelemetryHeaderType: OpenTelemetryHeaderType

    /// Creates a `OpenTelemetryHTTPHeadersWriter` to inject traces propagation headers
    /// to network request.
    ///
    /// - Parameter samplingRate: Tracing sampling rate. 20% by default.
    /// - Parameter openTelemetryHeaderType: Determines the type of telemetry header type used by the writer.
    public init(
        samplingRate: Float = 20,
        openTelemetryHeaderType: OpenTelemetryHeaderType
    ) {
        self.sampler = Sampler(samplingRate: samplingRate)
        self.openTelemetryHeaderType = openTelemetryHeaderType
    }

    /// Creates a `OpenTelemetryHTTPHeadersWriter` to inject traces propagation headers
    /// to network request.
    ///
    /// - Parameter sampler: Tracing sampler responsible for randomizing the sample.
    /// - Parameter openTelemetryHeaderType: Determines the type of telemetry header type used by the writer.
    internal init(
        sampler: Sampler,
        openTelemetryHeaderType: OpenTelemetryHeaderType
    ) {
        self.sampler = sampler
        self.openTelemetryHeaderType = openTelemetryHeaderType
    }

    public func inject(spanContext: OTSpanContext) {
        guard let spanContext = spanContext.dd else {
            return
        }

        let samplingPriority = sampler.sample()

        switch openTelemetryHeaderType {
        case .multiple:
            tracePropagationHTTPHeaders = [
                OpenTelemetryHTTPHeaders.Multiple.sampledField: samplingPriority ? Constants.sampledValue : Constants.unsampledValue
            ]

            if samplingPriority {
                tracePropagationHTTPHeaders[OpenTelemetryHTTPHeaders.Multiple.traceIDField] = spanContext.traceID.toHexadecimalString
                tracePropagationHTTPHeaders[OpenTelemetryHTTPHeaders.Multiple.spanIDField] = spanContext.spanID.toHexadecimalString
                if let parentSpanID = spanContext.parentSpanID {
                    tracePropagationHTTPHeaders[OpenTelemetryHTTPHeaders.Multiple.parentSpanIDField] = parentSpanID.toHexadecimalString
                }
            }
        case .single:
            if samplingPriority {
                let parentSpanIdHexadecimalString: String?
                if let parentSpanID = spanContext.parentSpanID {
                    parentSpanIdHexadecimalString = parentSpanID.toHexadecimalString
                } else {
                    parentSpanIdHexadecimalString = nil
                }
                tracePropagationHTTPHeaders[OpenTelemetryHTTPHeaders.Single.b3Field] = [
                    spanContext.traceID.toHexadecimalString,
                    spanContext.spanID.toHexadecimalString,
                    Constants.sampledValue,
                    parentSpanIdHexadecimalString
                ]
                .compactMap { $0 }
                .joined(separator: Constants.b3Separator)
            } else {
                tracePropagationHTTPHeaders[OpenTelemetryHTTPHeaders.Single.b3Field] = Constants.unsampledValue
            }
        }
    }

    private enum Constants {
        static let sampledValue = "1"
        static let unsampledValue = "0"
        static let b3Separator = "-"
    }
}
