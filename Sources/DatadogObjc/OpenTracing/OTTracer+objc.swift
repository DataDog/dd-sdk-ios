/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@objc
public class OT: NSObject {
    @objc public static let formatTextMap = "OTFormatTextMap"
}

/// Corresponds to: https://github.com/opentracing/opentracing-objc/blob/master/Pod/Classes/OTTracer.h
@objc
public protocol OTTracer {
    func startSpan(_ operationName: String) -> OTSpan
    func startSpan(_ operationName: String, tags: NSDictionary?) -> OTSpan
    func startSpan(_ operationName: String, childOf parent: OTSpanContext?) -> OTSpan
    func startSpan(_ operationName: String, childOf parent: OTSpanContext?, tags: NSDictionary?) -> OTSpan
    func startSpan(_ operationName: String, childOf parent: OTSpanContext?, tags: NSDictionary?, startTime: Date?) -> OTSpan
    func inject(_ spanContext: OTSpanContext, format: String, carrier: Any) throws
    func extractWithFormat(_ format: String, carrier: Any) throws
}
