/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
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
        guard format == OT.formatTextMap, let objcWriter = carrier as? DDHTTPHeadersWriter else {
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
        guard let ddspanContext = spanContext.dd else {
            return
        }
        swiftTracer.inject(
            spanContext: ddspanContext.swiftSpanContext,
            writer: objcWriter.swiftHTTPHeadersWriter
        )
    }

    @objc
    public func extractWithFormat(_ format: String, carrier: Any) throws {
        // TODO: RUMM-385 - we don't need to support it now
    }

    // MARK: - Private

    private func castTagsToSwift(_ tags: NSDictionary) -> [String: Encodable] {
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
                return AnyEncodable(objcTagValue)
            }
        }
    }
}
