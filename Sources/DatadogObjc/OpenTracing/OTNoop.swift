/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal let noopTracer: OTTracer = DDNoopTracer()
internal let noopSpan: OTSpan = DDNoopSpan()
internal let noopSpanContext: OTSpanContext = DDNoopSpanContext()

private class DDNoopTracer: OTTracer {
    func startSpan(_ operationName: String) -> OTSpan { noopSpan }
    func startSpan(_ operationName: String, tags: NSDictionary?) -> OTSpan { noopSpan }
    func startSpan(_ operationName: String, childOf parent: OTSpanContext?) -> OTSpan { noopSpan }
    func startSpan(_ operationName: String, childOf parent: OTSpanContext?, tags: NSDictionary?) -> OTSpan { noopSpan }
    func startSpan(_ operationName: String, childOf parent: OTSpanContext?, tags: NSDictionary?, startTime: Date?) -> OTSpan { noopSpan }
    func inject(_ spanContext: OTSpanContext, format: String, carrier: Any) throws {}
    func extractWithFormat(_ format: String, carrier: Any) throws {}
}

private class DDNoopSpan: OTSpan {
    var context: OTSpanContext { noopSpanContext }
    var tracer: OTTracer { noopTracer }
    func setOperationName(_ operationName: String) {}
    func setTag(_ key: String, value: NSString) {}
    func setTag(_ key: String, numberValue: NSNumber) {}
    func setTag(_ key: String, boolValue: Bool) {}
    func log(_ fields: [String: NSObject]) {}
    func log(_ fields: [String: NSObject], timestamp: Date?) {}
    func setBaggageItem(_ key: String, value: String) -> OTSpan { self }
    func getBaggageItem(_ key: String) -> String? { nil }
    func finish() {}
    func finishWithTime(_ finishTime: Date?) {}
}

private class DDNoopSpanContext: OTSpanContext {
    func forEachBaggageItem(_ callback: (String, String) -> Bool) {}
}
