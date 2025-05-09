/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(objc)
import DatadogInternal
import DatadogTrace

@objcMembers
public final class DDTraceConfiguration: NSObject {
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
        set { swiftConfig.tags = newValue?.dd.swiftAttributes }
        get { swiftConfig.tags?.dd.objCAttributes }
    }

    public func setURLSessionTracking(_ tracking: DDTraceURLSessionTracking) {
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

@objcMembers
public final class DDTraceFirstPartyHostsTracing: NSObject {
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

@objcMembers
public final class DDTraceURLSessionTracking: NSObject {
    internal var swiftConfig: Trace.Configuration.URLSessionTracking

    public init(firstPartyHostsTracing: DDTraceFirstPartyHostsTracing) {
        swiftConfig = .init(firstPartyHostsTracing: firstPartyHostsTracing.swiftType)
    }

    public func setFirstPartyHostsTracing(_ firstPartyHostsTracing: DDTraceFirstPartyHostsTracing) {
        swiftConfig.firstPartyHostsTracing = firstPartyHostsTracing.swiftType
    }
}

@objcMembers
@_spi(objc)
public final class DDTrace: NSObject {
    public static func enable(with configuration: DDTraceConfiguration) {
        Trace.enable(with: configuration.swiftConfig)
    }
}

@objcMembers
@_spi(objc)
public final class DDTracer: NSObject, DatadogObjc.OTTracer {
    // MARK: - Internal

    internal let swiftTracer: DatadogTrace.OTTracer

    internal init(swiftTracer: DatadogTrace.OTTracer) {
        self.swiftTracer = swiftTracer
    }

    // MARK: - Public

    public static func shared() -> DatadogObjc.OTTracer {
        DDTracer(swiftTracer: Tracer.shared())
    }

    public func startSpan(_ operationName: String) -> OTSpan {
        return DDSpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(operationName: operationName)
        )
    }

    public func startSpan(_ operationName: String, tags: NSDictionary?) -> OTSpan {
        return DDSpanObjc(
            objcTracer: self,
            swiftSpan: swiftTracer.startSpan(
                operationName: operationName,
                tags: tags.flatMap { castTagsToSwift($0) }
            )
        )
    }

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

    public func inject(_ spanContext: OTSpanContext, format: String, carrier: Any) throws {
        if let objcWriter = carrier as? DDHTTPHeadersWriter, format == OT.formatTextMap {
            guard let ddspanContext = spanContext.dd else {
                return
            }
            swiftTracer.inject(
                spanContext: ddspanContext.swiftSpanContext,
                writer: objcWriter.swiftHTTPHeadersWriter
            )
        } else if let objcWriter = carrier as? DDB3HTTPHeadersWriter, format == OT.formatTextMap {
            guard let ddspanContext = spanContext.dd else {
                return
            }
            swiftTracer.inject(
                spanContext: ddspanContext.swiftSpanContext,
                writer: objcWriter.swiftB3HTTPHeadersWriter
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
