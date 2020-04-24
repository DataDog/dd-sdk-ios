/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import OpenTracing
import Foundation

private struct DDNoopGlobals {
    static let tracer = DDNoopTracer()
    static let span = DDNoopSpan()
    static let context = DDNoopSpanContext()
}

internal struct DDNoopTracer: OpenTracing.Tracer {
    func extract(reader: FormatReader) -> SpanContext? { DDNoopGlobals.context }
    func inject(spanContext: SpanContext, writer: FormatWriter) {}
    func startSpan(operationName: String, references: [Reference]?, tags: [String: Codable]?, startTime: Date?) -> OpenTracing.Span { DDNoopGlobals.span }
}

internal struct DDNoopSpan: OpenTracing.Span {
    var context: SpanContext { DDNoopGlobals.context }
    func tracer() -> Tracer { DDNoopGlobals.tracer }
    func setOperationName(_ operationName: String) {}
    func finish(at time: Date) {}
    func log(fields: [String: Codable], timestamp: Date) {}
    func baggageItem(withKey key: String) -> String? { nil }
    func setBaggageItem(key: String, value: String) {}
    func setTag(key: String, value: Codable) {}
}

internal struct DDNoopSpanContext: OpenTracing.SpanContext {
    func forEachBaggageItem(callback: (String, String) -> Bool) {}
}
