/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi

internal class OTelSpanBuilder: OpenTelemetryApi.SpanBuilder {
    var tracer: DatadogTracer
    var spanName: String
    var spanKind = SpanKind.client
    var attributes: [String: OpenTelemetryApi.AttributeValue]
    var startTime: Date?
    var active: Bool
    var parent: Parent
    var spanLinks: [OTelSpanLink] = []

    enum Parent {
        case currentSpan
        case span(OpenTelemetryApi.Span)
        case spanContext(OpenTelemetryApi.SpanContext)
        case noParent

        func context() -> OpenTelemetryApi.SpanContext? {
            switch self {
            case .currentSpan:
                return OpenTelemetry.instance.contextProvider.activeSpan?.context
            case .span(let span):
                return span.context
            case .spanContext(let context):
                return context
            case .noParent:
                return nil
            }
        }
    }

    init(
        active: Bool,
        attributes: [String: OpenTelemetryApi.AttributeValue],
        parent: Parent,
        spanKind: SpanKind,
        spanName: String,
        startTime: Date?,
        tracer: DatadogTracer
    ) {
        self.tracer = tracer
        self.spanName = spanName
        self.spanKind = spanKind
        self.attributes = attributes
        self.startTime = startTime
        self.active = active
        self.parent = parent
    }

    func setParent(_ parent: OpenTelemetryApi.Span) -> Self {
        self.parent = .span(parent)
        return self
    }

    func setParent(_ parent: OpenTelemetryApi.SpanContext) -> Self {
        self.parent = .spanContext(parent)
        return self
    }

    func setNoParent() -> Self {
        self.parent = .noParent
        return self
    }

    func addLink(spanContext: OpenTelemetryApi.SpanContext) -> Self {
        self.spanLinks.append(OTelSpanLink(context: spanContext, attributes: [:]))
        return self
    }

    func addLink(spanContext: OpenTelemetryApi.SpanContext, attributes: [String: OpenTelemetryApi.AttributeValue]) -> Self {
        self.spanLinks.append(OTelSpanLink(context: spanContext, attributes: attributes))
        return self
    }

    func setSpanKind(spanKind: OpenTelemetryApi.SpanKind) -> Self {
        self.spanKind = spanKind
        return self
    }

    func setStartTime(time: Date) -> Self {
        self.startTime = time
        return self
    }

    func setActive(_ active: Bool) -> Self {
        self.active = active
        return self
    }

    func startSpan() -> OpenTelemetryApi.Span {
        let parentContext = parent.context()
        let traceId: TraceId
        let spanId = SpanId.random()
        let traceState: TraceState

        if let parentContext = parentContext, parentContext.isValid {
            traceId = parentContext.traceId
            traceState = parentContext.traceState
        } else {
            traceId = TraceId.random()
            traceState = .init()
        }

        let spanContext = SpanContext.create(
            traceId: traceId,
            spanId: spanId,
            traceFlags: TraceFlags(),
            traceState: traceState
        )

        guard let core = tracer.core else {
            return NOPOTelSpan()
        }

        let writer = LazySpanWriteContext(core: core)

        let createdSpan = OTelSpan(
            attributes: attributes,
            kind: spanKind,
            name: spanName,
            parentSpanID: parentContext?.spanId,
            spanContext: spanContext,
            spanKind: spanKind,
            spanLinks: spanLinks,
            startTime: startTime ?? Date(),
            tracer: tracer,
            eventBuilder: tracer.spanEventBuilder,
            eventWriter: writer
        )

        if active {
            OpenTelemetry.instance.contextProvider.setActiveSpan(createdSpan)
        }

        return createdSpan
    }

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue) -> Self {
        attributes[key] = value
        return self
    }
}
