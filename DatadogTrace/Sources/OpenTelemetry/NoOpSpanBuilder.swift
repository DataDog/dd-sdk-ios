/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

class NoOpSpanBuilder: SpanBuilder {
    @discardableResult public func startSpan() -> Span {
        return NoOpSpan()
    }

    @discardableResult public func setParent(_ parent: Span) -> Self {
        return self
    }

    @discardableResult public func setParent(_ parent: SpanContext) -> Self {
        return self
    }

    @discardableResult public func setNoParent() -> Self {
        return self
    }

    @discardableResult public func addLink(spanContext: SpanContext) -> Self {
        return self
    }

    @discardableResult public func addLink(spanContext: SpanContext, attributes: [String: OpenTelemetryApi.AttributeValue]) -> Self {
        return self
    }

    @discardableResult public func setSpanKind(spanKind: SpanKind) -> Self {
        return self
    }

    @discardableResult public func setStartTime(time: Date) -> Self {
        return self
    }

    public func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue) -> Self {
        return self
    }

    func setActive(_ active: Bool) -> Self {
        return self
    }
}
