/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

class WrapperSpanBuilder: SpanBuilder {
    private var tracer: DatadogTracer
    private var spanName: String
    private var spanKind = SpanKind.client
    private var attributes: [String: OpenTelemetryApi.AttributeValue] = [:]
    private var startTime: Date?
    private var startAsActive: Bool = false
    private var parentType: ParentType = .currentSpan

    enum ParentType {
        case span(Span)
        case spanContext(SpanContext)
        case noParent
        case currentSpan
    }

    init(tracer: DatadogTracer, spanName: String) {
        self.tracer = tracer
        self.spanName = spanName
    }

    @discardableResult public func startSpan() -> Span {
        var parentContext = parentContext(parentType: parentType)
        let traceId: TraceId
        let spanId = SpanId.random()
        var traceState = TraceState()

        if let parentContext = parentContext, parentContext.isValid {
            traceId = parentContext.traceId
            traceState = parentContext.traceState
        } else {
            traceId = TraceId.random()
            parentContext = nil
        }

        let spanContext = SpanContext.create(traceId: traceId,
                                             spanId: spanId,
                                             traceFlags: TraceFlags(),
                                             traceState: traceState)

        let createdSpan = WrapperSpan(
            name: spanName,
            context: spanContext,
            kind: spanKind,
            tracer: tracer,
            parentSpanID: parentContext?.spanId,
            startTime: startTime,
            attributes: attributes,
            spanKind: spanKind
        )

        if startAsActive {
            OpenTelemetry.instance.contextProvider.setActiveSpan(createdSpan)
        }

        return createdSpan
    }

    func parentContext(parentType: ParentType) -> SpanContext? {
        switch parentType {
        case .span(let span):
            return span.context
        case .spanContext(let spanContext):
            return spanContext
        case .noParent:
            return nil
        case .currentSpan:
            return OpenTelemetry.instance.contextProvider.activeSpan?.context
        }
    }

    @discardableResult public func setParent(_ parent: Span) -> Self {
        parentType = .span(parent)
        return self
    }

    @discardableResult public func setParent(_ parent: SpanContext) -> Self {
        parentType = .spanContext(parent)
        return self
    }

    @discardableResult public func setNoParent() -> Self {
        parentType = .noParent
        return self
    }

    @discardableResult public func addLink(spanContext: SpanContext) -> Self {
        return self
    }

    @discardableResult public func addLink(spanContext: SpanContext, attributes: [String: OpenTelemetryApi.AttributeValue]) -> Self {
        return self
    }

    @discardableResult public func setSpanKind(spanKind: SpanKind) -> Self {
        self.spanKind = spanKind
        return self
    }

    @discardableResult public func setStartTime(time: Date) -> Self {
        startTime = time
        return self
    }

    public func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue) -> Self {
        attributes[key] = value
        return self
    }

    func setActive(_ active: Bool) -> Self {
        startAsActive = active
        return self
    }
}
