/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import protocol Datadog.OTSpan

@objcMembers
@objc(OTSpan)
public class DDOTSpan: NSObject {
    let objcContext: DDOTSpanContext
    let swiftSpan: Datadog.OTSpan

    internal init(objcTracer: DDOTTracer, swiftSpan: Datadog.OTSpan) {
        self.tracer = objcTracer
        self.objcContext = DDOTSpanContext(swiftSpanContext: swiftSpan.context)
        self.swiftSpan = swiftSpan
    }

    // MARK: - Open Tracing Objective-C Interface

    public var context: DDOTSpanContext {
        return objcContext
    }

    public let tracer: DDOTTracer

    public func set(operationName: String) {
        // Corresponds to:
        // - (void)setOperationName:(NSString*)operationName;
        swiftSpan.setOperationName(operationName)
    }

    public func setTag(key: String, value: NSString) {
        // Corresponds to:
        // - (void)setTag:(NSString *)key value:(NSString *)value;
        swiftSpan.setTag(key: key, value: value as String)
    }

    public func setTag(key: String, numberValue: NSNumber) {
        // Corresponds to:
        // - (void)setTag:(NSString *)key numberValue:(NSNumber *)value;
        swiftSpan.setTag(key: key, value: AnyCodable(numberValue))
    }

    public func setTag(key: String, boolValue: Bool) {
        // Corresponds to:
        // - (void)setTag:(NSString *)key boolValue:(BOOL)value;
        swiftSpan.setTag(key: key, value: boolValue)
    }

    public func log(fields: [String: NSObject], timestamp: Date? = nil) {
        // Corresponds to:
        // - (void)log:(NSDictionary<NSString*, NSObject*>*)fields timestamp:(nullable NSDate*)timestamp;
        if let timestamp = timestamp {
            swiftSpan.log(
                fields: fields.mapValues { AnyCodable($0) },
                timestamp: timestamp
            )
        } else {
            swiftSpan.log(
                fields: fields.mapValues { AnyCodable($0) }
            )
        }
    }

    public func setBaggageItem(key: String, value: String) -> DDOTSpan {
        // Corresponds to:
        // - (id<OTSpan>)setBaggageItem:(NSString*)key value:(NSString*)value;
        swiftSpan.setBaggageItem(key: key, value: value)
        return self
    }

    public func getBaggageItem(key: String) -> String? {
        // Corresponds to:
        // - (nullable NSString*)getBaggageItem:(NSString*)key;
        return swiftSpan.baggageItem(withKey: key)
    }

    public func finish() {
        // Corresponds to:
        // - (void)finish;
        swiftSpan.finish()
    }

    public func finish(withTime finishTime: Date?) {
        // Corresponds to:
        // - (void)finishWithTime:(nullable NSDate*)finishTime;
        if let finishTime = finishTime {
            swiftSpan.finish(at: finishTime)
        } else {
            swiftSpan.finish()
        }
    }
}
