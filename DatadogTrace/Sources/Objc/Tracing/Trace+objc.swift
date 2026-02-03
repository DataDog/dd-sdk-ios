/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(objc)
import DatadogInternal

@objc(DDTraceConfiguration)
@objcMembers
@_spi(objc)
public final class objc_TraceConfiguration: NSObject {
    internal var swiftConfig: Trace.Configuration

    override public init() {
        swiftConfig = .init()
    }

    public var sampleRate: Float {
        set { swiftConfig.sampleRate = newValue }
        get { swiftConfig.sampleRate }
    }

    public var service: String? {
        set { swiftConfig.service = newValue }
        get { swiftConfig.service }
    }

    public var tags: [String: Any]? {
        set { swiftConfig.tags = newValue?.dd.swiftSendableAttributes }
        get { swiftConfig.tags?.dd.objCAttributes }
    }

    public func setURLSessionTracking(_ tracking: objc_TraceURLSessionTracking) {
        swiftConfig.urlSessionTracking = tracking.swiftConfig
    }

    public var bundleWithRumEnabled: Bool {
        set { swiftConfig.bundleWithRumEnabled = newValue }
        get { swiftConfig.bundleWithRumEnabled }
    }

    public var networkInfoEnabled: Bool {
        set { swiftConfig.networkInfoEnabled = newValue }
        get { swiftConfig.networkInfoEnabled }
    }

    public var customEndpoint: URL? {
        set { swiftConfig.customEndpoint = newValue }
        get { swiftConfig.customEndpoint }
    }
}

@objc(DDTraceFirstPartyHostsTracing)
@objcMembers
@_spi(objc)
public final class objc_TraceFirstPartyHostsTracing: NSObject {
    internal var swiftType: Trace.Configuration.URLSessionTracking.FirstPartyHostsTracing

    @_spi(objc)
    public init(hostsWithHeaderTypes: [String: Set<objc_TracingHeaderType>]) {
        let swiftHostsWithHeaders = hostsWithHeaderTypes.mapValues { headerTypes in Set(headerTypes.map { $0.swiftType }) }
        swiftType = .traceWithHeaders(hostsWithHeaders: swiftHostsWithHeaders)
    }

    @_spi(objc)
    public init(hostsWithHeaderTypes: [String: Set<objc_TracingHeaderType>], sampleRate: Float) {
        let swiftHostsWithHeaders = hostsWithHeaderTypes.mapValues { headerTypes in Set(headerTypes.map { $0.swiftType }) }
        swiftType = .traceWithHeaders(hostsWithHeaders: swiftHostsWithHeaders, sampleRate: sampleRate)
    }

    public init(hosts: Set<String>) {
        swiftType = .trace(hosts: hosts)
    }

    public init(hosts: Set<String>, sampleRate: Float) {
        swiftType = .trace(hosts: hosts, sampleRate: sampleRate)
    }
}

@objc(DDTraceURLSessionTracking)
@objcMembers
@_spi(objc)
public final class objc_TraceURLSessionTracking: NSObject {
    internal var swiftConfig: Trace.Configuration.URLSessionTracking

    public init(firstPartyHostsTracing: objc_TraceFirstPartyHostsTracing) {
        swiftConfig = .init(firstPartyHostsTracing: firstPartyHostsTracing.swiftType)
    }

    public func setFirstPartyHostsTracing(_ firstPartyHostsTracing: objc_TraceFirstPartyHostsTracing) {
        swiftConfig.firstPartyHostsTracing = firstPartyHostsTracing.swiftType
    }
}

@objc(DDTrace)
@objcMembers
@_spi(objc)
public final class objc_Trace: NSObject {
    public static func enable(with configuration: objc_TraceConfiguration) {
        Trace.enable(with: configuration.swiftConfig)
    }
}

@objc(DDTracer)
@objcMembers
@_spi(objc)
public final class objc_Tracer: NSObject, objc_OTTracer {
    // MARK: - Internal

    internal let swiftTracer: OTTracer

    internal init(swiftTracer: OTTracer) {
        self.swiftTracer = swiftTracer
    }

    // MARK: - Public

    public static func shared() -> objc_OTTracer {
        objc_Tracer(swiftTracer: Tracer.shared())
    }

    public func startSpan(_ operationName: String) -> objc_OTSpan {
        return objc_SpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(operationName: operationName)
        )
    }

    public func startSpan(_ operationName: String, tags: NSDictionary?) -> objc_OTSpan {
        return objc_SpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                tags: tags.flatMap { castTagsToSwift($0) as? [String: OTTracer.TagValue] }
            )
        )
    }

    public func startSpan(_ operationName: String, childOf parent: objc_OTSpanContext?) -> objc_OTSpan {
        let ddspanContext = parent?.dd
        return objc_SpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: ddspanContext?.swiftSpanContext
            )
        )
    }

    public func startSpan(
        _ operationName: String,
        childOf parent: objc_OTSpanContext?,
        tags: NSDictionary?
    ) -> objc_OTSpan {
        let ddspanContext = parent?.dd
        return objc_SpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: ddspanContext?.swiftSpanContext,
                tags: tags.flatMap { castTagsToSwift($0) as? [String: OTTracer.TagValue]}
            )
        )
    }

    public func startSpan(
        _ operationName: String,
        childOf parent: objc_OTSpanContext?,
        tags: NSDictionary?,
        startTime: Date?
    ) -> objc_OTSpan {
        let ddspanContext = parent?.dd
        return objc_SpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                childOf: ddspanContext?.swiftSpanContext,
                tags: tags.flatMap { castTagsToSwift($0) as? [String: OTTracer.TagValue]},
                startTime: startTime
            )
        )
    }

    public func startRootSpan(
        _ operationName: String,
        tags: NSDictionary?,
        startTime: Date?,
        customSampleRate: NSNumber?
    ) -> any objc_OTSpan {
        return objc_SpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startRootSpan(
                operationName: operationName,
                tags: tags.flatMap { castTagsToSwift($0) as? [String: OTTracer.TagValue] },
                startTime: startTime,
                customSampleRate: customSampleRate?.floatValue
            )
        )
    }

    public func inject(_ spanContext: objc_OTSpanContext, format: String, carrier: Any) throws {
        if let objcWriter = carrier as? objc_HTTPHeadersWriter, format == OT.formatTextMap {
            guard let ddspanContext = spanContext.dd else {
                return
            }
            swiftTracer.inject(
                spanContext: ddspanContext.swiftSpanContext,
                writer: objcWriter.swiftHTTPHeadersWriter
            )
        } else if let objcWriter = carrier as? objc_B3HTTPHeadersWriter, format == OT.formatTextMap {
            guard let ddspanContext = spanContext.dd else {
                return
            }
            swiftTracer.inject(
                spanContext: ddspanContext.swiftSpanContext,
                writer: objcWriter.swiftB3HTTPHeadersWriter
            )
        } else if let objcWriter = carrier as? objc_W3CHTTPHeadersWriter, format == OT.formatTextMap {
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
                        return AnyEncodable(tagValue)
                    }
                }()

                validTags[stringKey] = encodableValue
            }
        }

        return validTags
    }
}
