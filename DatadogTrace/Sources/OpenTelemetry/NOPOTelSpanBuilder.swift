/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import OpenTelemetryApi

internal class NOPOTelSpanBuilder: SpanBuilder {
    @discardableResult
    func startSpan() -> Span {
        return NOPOTelSpan()
    }

    @discardableResult
    func setParent(_ parent: Span) -> Self {
        return self
    }

    @discardableResult
    func setParent(_ parent: SpanContext) -> Self {
        return self
    }

    @discardableResult
    func setNoParent() -> Self {
        return self
    }

    @discardableResult
    func addLink(spanContext: SpanContext) -> Self {
        return self
    }

    @discardableResult
    func addLink(spanContext: SpanContext, attributes: [String: OpenTelemetryApi.AttributeValue]) -> Self {
        return self
    }

    @discardableResult
    func setSpanKind(spanKind: SpanKind) -> Self {
        return self
    }

    @discardableResult
    func setStartTime(time: Date) -> Self {
        return self
    }

    func setAttribute(key: String, value: OpenTelemetryApi.AttributeValue) -> Self {
        return self
    }

    func setActive(_ active: Bool) -> Self {
        return self
    }

    @discardableResult
    func withActiveSpan<T>(_ operation: (any OpenTelemetryApi.SpanBase) throws -> T) rethrows -> T {
        return try operation(NOPOTelSpan())
    }

    @discardableResult
    func withActiveSpan<T>(_ operation: (any OpenTelemetryApi.SpanBase) async throws -> T) async rethrows -> T {
        return try await operation(NOPOTelSpan())
    }

}
