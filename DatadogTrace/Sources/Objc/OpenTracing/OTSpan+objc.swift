/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Corresponds to: https://github.com/opentracing/opentracing-objc/blob/master/Pod/Classes/OTSpan.h
@objc(OTSpan)
@_spi(objc)
public protocol objc_OTSpan {
    var context: objc_OTSpanContext { get }
    var tracer: objc_OTTracer { get }

    func setOperationName(_ operationName: String)

    func setTag(_ key: String, value: NSString)
    func setTag(_ key: String, numberValue: NSNumber)
    func setTag(_ key: String, boolValue: Bool)

    func log(_ fields: [String: NSObject])
    func log(_ fields: [String: NSObject], timestamp: Date?)

    func setBaggageItem(_ key: String, value: String) -> objc_OTSpan
    func getBaggageItem(_ key: String) -> String?

    func setError(_ error: Error)
    func setError(kind: String, message: String, stack: String?)

    func finish()
    func finishWithTime(_ finishTime: Date?)

    @discardableResult
    func setActive() -> objc_OTSpan
}
