/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(objc)
import DatadogInternal

/// Configuration of URLSession instrumentation.
@objc(DDURLSessionInstrumentationConfiguration)
@objcMembers
@_spi(objc)
public final class objc_URLSessionInstrumentationConfiguration: NSObject {
    internal var swiftConfig: URLSessionInstrumentation.Configuration

    public init(delegateClass: URLSessionDataDelegate.Type) {
        swiftConfig = .init(delegateClass: delegateClass)
    }

    /// Sets additional first party hosts to consider in the interception.
    public func setFirstPartyHostsTracing(_ firstPartyHostsTracing: objc_URLSessionInstrumentationFirstPartyHostsTracing) {
        swiftConfig.firstPartyHostsTracing = firstPartyHostsTracing.swiftType
    }

    /// The delegate class to be used to swizzle URLSessionTaskDelegate & URLSessionDataDelegate methods.
    public var delegateClass: URLSessionDataDelegate.Type {
        set { swiftConfig.delegateClass = newValue }
        get { swiftConfig.delegateClass }
    }
}

/// Defines configuration for first-party hosts in distributed tracing.
@objc(DDURLSessionInstrumentationFirstPartyHostsTracing)
@objcMembers
@_spi(objc)
public final class objc_URLSessionInstrumentationFirstPartyHostsTracing: NSObject {
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

@objc(DDURLSessionInstrumentation)
@objcMembers
@_spi(objc)
public final class objc_URLSessionInstrumentation: NSObject {
    /// Enables metrics mode to capture detailed timing breakdowns for URLSession tasks.
    ///
    /// This method is optional. Automatic network tracking is already enabled by default when RUM or Trace is initialized with URL session tracking configuration.
    /// Metrics mode provides additional detailed timing information captured from `URLSessionTaskMetrics` (including DNS, Connection, SSL, First Byte, Download).
    ///
    /// Note: Metrics mode involves swizzling `URLSessionDataDelegate` methods to capture `URLSessionTaskMetrics`.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    public static func trackMetrics(configuration: objc_URLSessionInstrumentationConfiguration) {
        URLSessionInstrumentation.trackMetrics(with: configuration.swiftConfig)
    }

    /// Enables URLSession instrumentation.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    @available(*, deprecated, renamed: "trackMetrics(configuration:)", message: "Use trackMetrics(configuration:) instead.")
    public static func enable(configuration: objc_URLSessionInstrumentationConfiguration) {
        URLSessionInstrumentation.enable(with: configuration.swiftConfig)
    }

    /// Disables URLSession instrumentation.
    /// - Parameters:
    ///   - delegateClass: The delegate class to unbind.
    public static func disable(delegateClass: URLSessionDataDelegate.Type) {
        URLSessionInstrumentation.disable(delegateClass: delegateClass)
    }
}
