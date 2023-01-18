/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import struct Datadog.DDAnyEncodable
import class Datadog.Tracer
import protocol Datadog.OTTracer
import struct Datadog.OTReference
import class Datadog.HTTPHeadersWriter

@objc
public class DDTracer: NSObject, DatadogObjc.OTTracer {
    @available(*, deprecated, message: "Use `DDTracer(configuration:)`.")
    @objc
    public static func initialize(configuration: DDTracerConfiguration) -> DatadogObjc.OTTracer {
        return DDTracer(configuration: configuration)
    }

    // MARK: - Internal

    internal let swiftTracer: Datadog.OTTracer

    internal init(swiftTracer: Datadog.OTTracer) {
        self.swiftTracer = swiftTracer
    }

    // MARK: - Public

    @objc
    public convenience init(configuration: DDTracerConfiguration) {
        self.init(
            swiftTracer: Datadog.Tracer.initialize(
                configuration: configuration.swiftConfiguration
            )
        )
    }

    @objc
    public func startSpan(_ operationName: String) -> OTSpan {
        return DDSpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(operationName: operationName)
        )
    }

    @objc
    public func startSpan(_ operationName: String, tags: NSDictionary?) -> OTSpan {
        return DDSpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                tags: tags.flatMap { castTagsToSwift($0) }
            )
        )
    }

    @objc
    public func startSpan(_ operationName: String, childOf parent: OTSpanContext?) -> OTSpan {
        let ddspanContext = parent?.dd
        return DDSpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: ddspanContext?.swiftSpanContext
            )
        )
    }

    @objc
    public func startSpan(
        _ operationName: String,
        childOf parent: OTSpanContext?,
        tags: NSDictionary?
    ) -> OTSpan {
        let ddspanContext = parent?.dd
        return DDSpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: ddspanContext?.swiftSpanContext,
                tags: tags.flatMap { castTagsToSwift($0) }
            )
        )
    }

    @objc
    public func startSpan(
        _ operationName: String,
        childOf parent: OTSpanContext?,
        tags: NSDictionary?,
        startTime: Date?
    ) -> OTSpan {
        let ddspanContext = parent?.dd
        return DDSpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: ddspanContext?.swiftSpanContext,
                tags: tags.flatMap { castTagsToSwift($0) },
                startTime: startTime
            )
        )
    }

    @objc
    public func inject(_ spanContext: OTSpanContext, format: String, carrier: Any) throws {
        if let objcWriter = carrier as? DDHTTPHeadersWriter, format == OT.formatTextMap {
            guard let ddspanContext = spanContext.dd else {
                return
            }
            swiftTracer.inject(
                spanContext: ddspanContext.swiftSpanContext,
                writer: objcWriter.swiftHTTPHeadersWriter
            )
        } else if let objcWriter = carrier as? DDOTelHTTPHeadersWriter, format == OT.formatTextMap {
            guard let ddspanContext = spanContext.dd else {
                return
            }
            swiftTracer.inject(
                spanContext: ddspanContext.swiftSpanContext,
                writer: objcWriter.swiftOTelHTTPHeadersWriter
            )
        } else if let objcWriter = carrier as? DDW3CHTTPHeadersWriter, format == OT.formatTextMap {
            guard let ddspanContext = spanContext.dd else {
                return
            }
            swiftTracer.inject(
                spanContext: ddspanContext.swiftSpanContext,
                writer: objcWriter.swiftW3CHTTPHeadersWriter
            )
        } else {
            let error = NSError(
                domain: "DDTracer",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey: "Trying to inject `OTSpanContext` using wrong format and/or carrier.",
                    NSLocalizedRecoverySuggestionErrorKey: "Use `DDHTTPHeadersWriter` carrier with `OT.formatTextMap` format."
                ]
            )
            throw error
        }
    }

    @objc
    public func extractWithFormat(_ format: String, carrier: Any) throws {
        // TODO: RUMM-385 - we don't need to support it now
    }

    // MARK: - Private

    private func castTagsToSwift(_ tags: NSDictionary) -> [String: Encodable] {
        var validTags: [String: Encodable] = [:]

        tags.forEach { tagKey, tagValue in
            if let stringKey = tagKey as? String {
                let encodableValue: Encodable = {
                    if let stringValue = tagValue as? String {
                        return stringValue
                    } else if let urlValue = tagValue as? URL {
                        return urlValue
                    } else {
                        return DDAnyEncodable(tagValue)
                    }
                }()

                validTags[stringKey] = encodableValue
            }
        }

        return validTags
    }
}
