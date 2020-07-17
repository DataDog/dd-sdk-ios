/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct DDNoopGlobals {
    static let tracer = DDNoopTracer()
    static let span = DDNoopSpan()
    static let context = DDNoopSpanContext()
}

internal struct DDNoopTracer: OTTracer {
    func extract(reader: OTFormatReader) -> OTSpanContext? { DDNoopGlobals.context }
    func inject(spanContext: OTSpanContext, writer: OTFormatWriter) {}
    func startSpan(operationName: String, references: [OTReference]?, tags: [String: Encodable]?, startTime: Date?) -> OTSpan { DDNoopGlobals.span }
}

internal struct DDNoopSpan: OTSpan {
    var context: OTSpanContext { DDNoopGlobals.context }
    func tracer() -> OTTracer { DDNoopGlobals.tracer }
    func setOperationName(_ operationName: String) {}
    func finish(at time: Date) {}
    func log(fields: [String: Encodable], timestamp: Date) {}
    func baggageItem(withKey key: String) -> String? { nil }
    func setBaggageItem(key: String, value: String) {}
    func setTag(key: String, value: Encodable) {}
}

internal struct DDNoopSpanContext: OTSpanContext {
    func forEachBaggageItem(callback: (String, String) -> Bool) {}
}
