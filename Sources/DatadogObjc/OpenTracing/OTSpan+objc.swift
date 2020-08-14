/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

@objc
/// Corresponds to: https://github.com/opentracing/opentracing-objc/blob/master/Pod/Classes/OTSpan.h
public protocol OTSpan {
    var context: OTSpanContext { get }
    var tracer: OTTracer { get }

    func setOperationName(_ operationName: String)

    func setTag(_ key: String, value: NSString)
    func setTag(_ key: String, numberValue: NSNumber)
    func setTag(_ key: String, boolValue: Bool)

    func log(_ fields: [String: NSObject])
    func log(_ fields: [String: NSObject], timestamp: Date?)

    func setBaggageItem(_ key: String, value: String) -> OTSpan
    func getBaggageItem(_ key: String) -> String?

    func finish()
    func finishWithTime(_ finishTime: Date?)
}
