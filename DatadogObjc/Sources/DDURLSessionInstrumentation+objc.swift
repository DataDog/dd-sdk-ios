/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogCore
import DatadogInternal

/// Configuration of URLSession instrumentation.
@objc
public class DDURLSessionInstrumentationConfiguration: NSObject {
    internal var swiftConfig: URLSessionInstrumentation.Configuration

    @objc
    public init(delegateClass: URLSessionDataDelegate.Type) {
        swiftConfig = .init(delegateClass: delegateClass)
    }

    /// Sets additional first party hosts to consider in the interception.
    @objc
    public func setFirstPartyHostsTracing(_ firstPartyHostsTracing: DDURLSessionInstrumentationFirstPartyHostsTracing) {
        swiftConfig.firstPartyHostsTracing = firstPartyHostsTracing.swiftType
    }

    /// The delegate class to be used to swizzle URLSessionTaskDelegate & URLSessionDataDelegate methods.
    @objc public var delegateClass: URLSessionDataDelegate.Type {
        set { swiftConfig.delegateClass = newValue }
        get { swiftConfig.delegateClass }
    }
}

/// Defines configuration for first-party hosts in distributed tracing.
@objc
public class DDURLSessionInstrumentationFirstPartyHostsTracing: NSObject {
    internal var swiftType: URLSessionInstrumentation.FirstPartyHostsTracing

    @objc
    public init(hostsWithHeaderTypes: [String: Set<DDTracingHeaderType>]) {
        let swiftHostsWithHeaders = hostsWithHeaderTypes.mapValues { headerTypes in
            Set(headerTypes.map {
                $0.swiftType
            })
        }
        swiftType = .traceWithHeaders(hostsWithHeaders: swiftHostsWithHeaders)
    }

    @objc
    public init(hosts: Set<String>) {
        swiftType = .trace(hosts: hosts)
    }
}

@objc
public class DDURLSessionInstrumentation: NSObject {
    /// Enables URLSession instrumentation.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    @objc
    public static func enable(configuration: DDURLSessionInstrumentationConfiguration) {
        URLSessionInstrumentation.enable(with: configuration.swiftConfig)
    }

    /// Disables URLSession instrumentation.
    /// - Parameters:
    ///   - delegateClass: The delegate class to unbind.
    @objc
    public static func disable(delegateClass: URLSessionDataDelegate.Type) {
        if delegateClass == DDNSURLSessionDelegate.self {
            URLSessionInstrumentation.disable(delegateClass: DatadogURLSessionDelegate.self)
        }
        URLSessionInstrumentation.disable(delegateClass: delegateClass)
    }
}
