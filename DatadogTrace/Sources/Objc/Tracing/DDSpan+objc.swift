/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

@objc(DDSpanObjc)
@objcMembers
internal class objc_SpanObjc: NSObject, objc_OTSpan {
    let swiftSpan: OTSpan

    init(objcTracer: objc_OTTracer, swiftSpan: OTSpan) {
        self.tracer = objcTracer
        self.context = objc_SpanContextObjc(swiftSpanContext: swiftSpan.context)
        self.swiftSpan = swiftSpan
    }

    // MARK: - Open Tracing Objective-C Interface

    let tracer: objc_OTTracer

    let context: objc_OTSpanContext

    func setOperationName(_ operationName: String) {
        swiftSpan.setOperationName(operationName)
    }

    func setTag(_ key: String, value: NSString) {
        swiftSpan.setTag(key: key, value: value as String)
    }

    func setTag(_ key: String, numberValue: NSNumber) {
        swiftSpan.setTag(key: key, value: AnyEncodable(numberValue))
    }

    func setTag(_ key: String, boolValue: Bool) {
        swiftSpan.setTag(key: key, value: boolValue)
    }

    func log(_ fields: [String: NSObject]) {
        self.log(fields, timestamp: Date())
    }

    func log(_ fields: [String: NSObject], timestamp: Date?) {
        if let timestamp = timestamp {
            swiftSpan.log(
                fields: fields.mapValues { AnyEncodable($0) },
                timestamp: timestamp
            )
        } else {
            swiftSpan.log(
                fields: fields.mapValues { AnyEncodable($0) }
            )
        }
    }

    func setBaggageItem(_ key: String, value: String) -> objc_OTSpan {
        swiftSpan.setBaggageItem(key: key, value: value)
        return self
    }

    func getBaggageItem(_ key: String) -> String? {
        return swiftSpan.baggageItem(withKey: key)
    }

    func setError(_ error: Error) {
        swiftSpan.setError(error)
    }

    func setError(kind: String, message: String, stack: String?) {
        swiftSpan.setError(kind: kind, message: message, stack: stack ?? "")
    }

    func finish() {
        swiftSpan.finish()
    }

    func finishWithTime(_ finishTime: Date?) {
        if let finishTime = finishTime {
            swiftSpan.finish(at: finishTime)
        } else {
            swiftSpan.finish()
        }
    }

    func setActive() -> objc_OTSpan {
        _ = swiftSpan.setActive()
        return self
    }
}
