/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import protocol Datadog.OTTracer
import struct Datadog.OTReference
import class Datadog.HTTPHeadersWriter

public let OTFormatHTTPHeaders = "OTFormatHTTPHeaders"

@objcMembers
@objc(OTTracer)
public class DDOTTracer: NSObject {
    /*
     Although `DDTracer` doesn't implement the `opentracing-objc` explicitly, we keep its interface 1:1 with
     https://github.com/opentracing/opentracing-objc/blob/master/Pod/Classes/OTTracer.h
     */

    internal let swiftTracer: OTTracer

    internal init(swiftTracer: OTTracer) {
        self.swiftTracer = swiftTracer
    }

    // MARK: - Open Tracing Objective-C Interface

    public func startSpan(operationName: String) -> DDOTSpan {
        // Corresponds to:
        // - (id<OTSpan>)startSpan:(NSString*)operationName;
        return DDOTSpan(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(operationName: operationName)
        )
    }

    public func startSpan(operationName: String, tags: NSDictionary?) -> DDOTSpan {
        // Corresponds to:
        // - (id<OTSpan>)startSpan:(NSString*)operationName
        //               tags:(nullable NSDictionary*)tags;
        return DDOTSpan(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                tags: tags.flatMap { castTagsToSwift($0) }
            )
        )
    }

    // - (id<OTSpan>)startSpan:(NSString*)operationName childOf:(nullable id<OTSpanContext>)parent;
    public func startSpan(operationName: String, childOf parent: DDOTSpanContext?) -> DDOTSpan {
        // Corresponds to:
        // - (id<OTSpan>)startSpan:(NSString*)operationName
        //               childOf:(nullable id<OTSpanContext>)parent;
        return DDOTSpan(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: parent?.swiftSpanContext
            )
        )
    }

    public func startSpan(
        operationName: String,
        childOf parent: DDOTSpanContext?,
        tags: NSDictionary?
    ) -> DDOTSpan {
        // Corresponds to:
        // - (id<OTSpan>)startSpan:(NSString*)operationName
        //               childOf:(nullable id<OTSpanContext>)parent
        //               tags:(nullable NSDictionary*)tags;
        return DDOTSpan(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: parent?.swiftSpanContext,
                tags: tags.flatMap { castTagsToSwift($0) }
            )
        )
    }

    public func startSpan(
        operationName: String,
        childOf parent: DDOTSpanContext?,
        tags: NSDictionary?,
        startTime: Date?
    ) -> DDOTSpan {
        // Corresponds to:
        // - (id<OTSpan>)startSpan:(NSString*)operationName
        //               childOf:(nullable id<OTSpanContext>)parent
        //               tags:(nullable NSDictionary*)tags
        //               startTime:(nullable NSDate*)startTime;
        return DDOTSpan(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: parent?.swiftSpanContext,
                tags: tags.flatMap { castTagsToSwift($0) },
                startTime: startTime
            )
        )
    }

    public func inject(spanContext: DDOTSpanContext, format: String, carrier: Any) throws {
        // Corresponds to:
        // - (BOOL)inject:(id<OTSpanContext>)spanContext format:(NSString*)format carrier:(id)carrier error:(NSError* __autoreleasing *)outError;
        guard format == OTFormatHTTPHeaders, let objcWriter = carrier as? DDHTTPHeadersWriter else {
            let error = NSError(
                domain: "DDTracer",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey: "Trying to inject `OTSpanContext` using wrong format or carrier.",
                    NSLocalizedRecoverySuggestionErrorKey: "Use `DDHTTPHeadersWriter` carrier with `OTFormatHTTPHeaders` format."
                ]
            )
            throw error
        }
        swiftTracer.inject(
            spanContext: spanContext.swiftSpanContext,
            writer: objcWriter.swiftHTTPHeadersWriter
        )
    }

    public func extractWithFormat(format: String, carrier: Any) throws {
        // Corresponds to:
        // - (nullable id<OTSpanContext>)extractWithFormat:(NSString*)format carrier:(id)carrier error:(NSError* __autoreleasing *)outError;
        // TODO: RUMM-385 - we don't need to support it now
    }

    // MARK: - Private

    private func castTagsToSwift(_ tags: NSDictionary) -> [String: Codable] {
        guard let dictionary = tags as? [String: Any] else {
            return [:]
        }

        return dictionary.mapValues { objcTagValue in
            // As underlying `Datadog.JSONStringEncodableValue` provides special handling for `String` and `URL`
            // when converting those `Encodables` to lossless JSON string representation, we have to cast them directly:
            if let stringValue = objcTagValue as? String {
                return stringValue
            } else if let urlValue = objcTagValue as? URL {
                return urlValue
            } else {
                return AnyCodable(objcTagValue)
            }
        }
    }
}
