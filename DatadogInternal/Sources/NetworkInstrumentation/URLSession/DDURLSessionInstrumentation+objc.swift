/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Configuration of URLSession instrumentation.
@objcMembers
@_spi(objc)
public class DDURLSessionInstrumentationConfiguration: NSObject {
    public internal(set) var swiftConfig: URLSessionInstrumentation.Configuration

    public init(delegateClass: URLSessionDataDelegate.Type) {
        swiftConfig = .init(delegateClass: delegateClass)
    }

    /// Sets additional first party hosts to consider in the interception.
    public func setFirstPartyHostsTracing(_ firstPartyHostsTracing: DDURLSessionInstrumentationFirstPartyHostsTracing) {
        swiftConfig.firstPartyHostsTracing = firstPartyHostsTracing.swiftType
    }

    /// The delegate class to be used to swizzle URLSessionTaskDelegate & URLSessionDataDelegate methods.
    public var delegateClass: URLSessionDataDelegate.Type {
        set { swiftConfig.delegateClass = newValue }
        get { swiftConfig.delegateClass }
    }
}

/// Defines configuration for first-party hosts in distributed tracing.
@objcMembers
@_spi(objc)
public class DDURLSessionInstrumentationFirstPartyHostsTracing: NSObject {
    internal var swiftType: URLSessionInstrumentation.FirstPartyHostsTracing

    public init(hostsWithHeaderTypes: [String: Set<objc_TracingHeaderType>]) {
        let swiftHostsWithHeaders = hostsWithHeaderTypes.mapValues { headerTypes in
            Set(headerTypes.map {
                $0.swiftType
            })
        }
        swiftType = .traceWithHeaders(hostsWithHeaders: swiftHostsWithHeaders)
    }

    public init(hosts: Set<String>) {
        swiftType = .trace(hosts: hosts)
    }
}

@objcMembers
@_spi(objc)
public class DDURLSessionInstrumentation: NSObject {
    /// Enables URLSession instrumentation.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    public static func enable(configuration: DDURLSessionInstrumentationConfiguration) {
        URLSessionInstrumentation.enable(with: configuration.swiftConfig)
    }

    /// Disables URLSession instrumentation.
    /// - Parameters:
    ///   - delegateClass: The delegate class to unbind.
    public static func disable(delegateClass: URLSessionDataDelegate.Type) {
        URLSessionInstrumentation.disable(delegateClass: delegateClass)
    }
}
