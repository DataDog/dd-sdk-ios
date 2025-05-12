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

    func withActiveSpan<T>(_ operation: (any OpenTelemetryApi.SpanBase) throws -> T) rethrows -> T {
        let span = startSpan()
        defer { span.end() }
        return try operation(span)
    }

#if canImport(_Concurrency)
    /// Ref.: https://github.com/open-telemetry/opentelemetry-swift/issues/578
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    func withActiveSpan<T>(_ operation: (any OpenTelemetryApi.SpanBase) async throws -> T) async rethrows -> T {
        let span = startSpan()
        defer { span.end() }
        return try await operation(span)
    }
#endif
}
