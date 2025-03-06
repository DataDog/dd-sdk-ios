/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import DatadogInternal
import OpenTelemetryApi

internal enum DatadogTagKeys: String {
    case spanKind = "span.kind"
    case errorType = "error.type"
    case errorMessage = "error.message"
    case spanLinks = "_dd.span_links"
}

extension OpenTelemetryApi.TraceId {
    /// Returns 32 character hexadecimal string representation of lower 64 bits of the trace ID.
    var lowerLongHexString: String {
        return String(format: "%016llx", rawLowerLong)
    }
}

internal extension OpenTelemetryApi.Status {
    /// Ok > Error > Unset
    /// https://opentelemetry.io/docs/specs/otel/trace/api/#set-status
    var priority: UInt {
        switch self {
        case .ok:
            return 3
        case .error:
            return 2
        case .unset:
            return 1
        @unknown default:
            return 1
        }
    }
}

internal class OTelSpan: OpenTelemetryApi.Span {
    @ReadWriteLock
    private var _status: OpenTelemetryApi.Status

    @ReadWriteLock
    private var _name: String

    @ReadWriteLock
    var attributes: [String: OpenTelemetryApi.AttributeValue]
    let context: OpenTelemetryApi.SpanContext
    @ReadWriteLock
    var kind: OpenTelemetryApi.SpanKind
    let ddSpan: DDSpan
    let tracer: DatadogTracer
    let spanLinks: [OTelSpanLink]

    /// `isRecording` indicates whether the span is recording or not
    /// and events can be added to it.
    @ReadWriteLock
    var isRecording: Bool

    /// Saves status of the span indicating whether the span has recorded errors.
    /// This will be done by setting `error.message` tag on the span.
    var status: OpenTelemetryApi.Status {
        get {
            _status
        }
        set {
            __status.mutate {
                guard isRecording else {
                    return
                }

                // If the code has been set to a higher value before (Ok > Error > Unset),
                // the code will not be changed.
                guard newValue.priority >= $0.priority else {
                    return
                }

                $0 = newValue
            }
        }
    }

    /// `name` of the span is akin to operation name in Datadog
    var name: String {
        get {
            _name
        }
        set {
            __name.mutate {
                guard isRecording else {
                    return
                }
                $0 = newValue
                ddSpan.setOperationName($0)
            }
        }
    }

    init(
        attributes: [String: OpenTelemetryApi.AttributeValue],
        kind: OpenTelemetryApi.SpanKind,
        name: String,
        parentSpanID: OpenTelemetryApi.SpanId?,
        spanContext: OpenTelemetryApi.SpanContext,
        spanKind: OpenTelemetryApi.SpanKind,
        spanLinks: [OTelSpanLink],
        startTime: Date,
        tracer: DatadogTracer,
        eventBuilder: SpanEventBuilder,
        eventWriter: SpanWriteContext
    ) {
        self._name = name
        self._status = .unset
        self.attributes = attributes
        self.context = spanContext
        self.kind = kind
        self.isRecording = true
        self.tracer = tracer
        self.spanLinks = spanLinks
        self.ddSpan = .init(
            tracer: tracer,
            context: .init(
                traceID: context.traceId.toDatadog(),
                spanID: context.spanId.toDatadog(),
                parentSpanID: parentSpanID?.toDatadog(),
                baggageItems: .init(),
                sampleRate: tracer.localTraceSampler.samplingRate,
                isKept: tracer.localTraceSampler.sample()
            ),
            operationName: name,
            startTime: startTime,
            tags: [:],
            eventBuilder: eventBuilder,
            eventWriter: eventWriter
        )
    }

    func addEvent(name: String) {
        DD.logger.warn("\(#function) is not yet supported in `DatadogTrace`")
    }

    func addEvent(name: String, timestamp: Date) {
        DD.logger.warn("\(#function) is not yet supported in `DatadogTrace`")
    }

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue]) {
        DD.logger.warn("\(#function) is not yet supported in `DatadogTrace`")
    }

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {
        DD.logger.warn("\(#function) is not yet supported in `DatadogTrace`")
    }

    func recordException(_ exception: any OpenTelemetryApi.SpanException, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {
        // RUM-8558: `recordException()` should be based on `addEvent()` which we currently don't support.
        // Ref.: https://github.com/open-telemetry/opentelemetry-swift/blob/1.13.0/Sources/OpenTelemetrySdk/Trace/RecordEventsReadableSpan.swift#L356
        DD.logger.warn("\(#function) is not yet supported in `DatadogTrace`")
    }

    func recordException(_ exception: any OpenTelemetryApi.SpanException, attributes: [String: OpenTelemetryApi.AttributeValue]) {
        DD.logger.warn("\(#function) is not yet supported in `DatadogTrace`")
    }

    func recordException(_ exception: any OpenTelemetryApi.SpanException, timestamp: Date) {
        DD.logger.warn("\(#function) is not yet supported in `DatadogTrace`")
    }

    func recordException(_ exception: any OpenTelemetryApi.SpanException) {
        DD.logger.warn("\(#function) is not yet supported in `DatadogTrace`")
    }

    func end() {
        end(time: Date())
    }

    func end(time: Date) {
        var tags: [String: String] = [:]

        guard isRecording else {
            return
        }
        isRecording = false
        tags = attributes.tags

        // set global tags
        for (key, value) in tracer.tags {
            ddSpan.setTag(key: key, value: value)
        }

        // set local tags
        // local takes precedence over global
        for (key, value) in tags {
            ddSpan.setTag(key: key, value: value)
        }

        switch status {
        case .ok, .unset:
            break
        case .error(description: let description):
            // set error tags on the span
            tags[DatadogTagKeys.errorMessage.rawValue] = description

            // send error log to Datadog
            // Empty kind or description is equivalent to not present
            ddSpan.setError(kind: "", message: description)
        @unknown default:
            break
        }

        // SpanKind maps to the `span.kind` tag in Datadog
        ddSpan.setTag(key: DatadogTagKeys.spanKind.rawValue, value: kind.rawValue)

        // Datadog uses `_dd.span_links` tag to send span links
        if !spanLinks.isEmpty {
            ddSpan.setTag(key: DatadogTagKeys.spanLinks.rawValue, value: spanLinks)
        }

        ddSpan.finish(at: time)
        OpenTelemetry.instance.contextProvider.removeContextForSpan(self)
    }

    var description: String {
        return "OTelSpan"
    }

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue?) {
        guard isRecording else {
            return
        }

        attributes[key] = value
    }
}
