/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi


class WrapperSpan: OpenTelemetryApi.Span {
    var kind: OpenTelemetryApi.SpanKind
    var context: OpenTelemetryApi.SpanContext
    var name: String
    var nestedSpan: DDSpan
    var internalStatus: Status = Status.unset
    var attributes: [String: OpenTelemetryApi.AttributeValue]

    func end() {
        end(time: Date())
    }

    func end(time: Date) {
        isRecording = false
        switch status {
        case .ok:
            break
        case .unset:
            break
        case .error(let description):
            nestedSpan.setTag(key: "error.message", value: description)
        }
        nestedSpan.setTag(key: "span.kind", value: kind)
        for (key, val) in attributes {
            nestedSpan.setTag(key: key, value: val)
        }
        nestedSpan.finish(at: time)
    }

    init(
        name: String,
        context: SpanContext,
        kind: SpanKind,
        tracer: DatadogTracer,
        parentSpanID: SpanId?,
        startTime: Date?,
        attributes: [String: OpenTelemetryApi.AttributeValue],
        spanKind: SpanKind
    ) {
        self.attributes = attributes
        self.nestedSpan = .init(tracer: tracer,
                                context: .init(traceID: context.traceId.toDatadogTraceID(),
                                               spanID: context.spanId.toDatadogSpanID(),
                                               parentSpanID: parentSpanID?.toDatadogSpanID(),
                                               baggageItems: .init()),
                                operationName: name,
                                startTime: startTime ?? Date(),
                                tags: [:])
        self.kind = spanKind
        self.context = context
        self.name = name
    }

    var isRecording: Bool = true

    var status: Status {
        get {
            return internalStatus
        }
        set {
            guard isRecording else {
                return
            }

            internalStatus = newValue
        }
    }

    var description: String {
        return "WrapperSpan"
    }

    func updateName(name: String) {
        guard isRecording else {
            return
        }

        self.nestedSpan.setOperationName(name)
        self.name = name
    }

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue?) {
        guard isRecording else {
            return
        }

        self.nestedSpan.setTag(key: key, value: value?.description ?? "")
    }

    func addEvent(name: String) {
        guard isRecording else {
            return
        }

        self.nestedSpan.log(fields: [name: ""])
    }

    func addEvent(name: String, timestamp: Date) {
        guard isRecording else {
            return
        }

        self.nestedSpan.log(fields: [name: ""], timestamp: timestamp)
    }

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue]) {
        guard isRecording else {
            return
        }

        self.nestedSpan.log(fields: attributes)
    }

    func addEvent(name: String, attributes: [String: OpenTelemetryApi.AttributeValue], timestamp: Date) {
        guard isRecording else {
            return
        }

        self.nestedSpan.log(fields: attributes, timestamp: timestamp)
    }
}
