/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An entry point to enable URLSession instrumentation.
public enum URLSessionInstrumentation {
    /// Enables URLSession instrumentation.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    ///   - core: The instance of Datadog SDK to enable URLSession instrumentation in (global instance by default).
    public static func enable(with configuration: URLSessionInstrumentation.Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) {
        do {
            try enableOrThrow(with: configuration, in: core)
        } catch let error {
            consolePrint("\(error)", .error)

            if error is InternalError { // SDK error, send to telemetry
                core.telemetry.error(error)
            }
        }
    }

    internal static func enableOrThrow(with configuration: URLSessionInstrumentation.Configuration, in core: DatadogCoreProtocol) throws {
        guard let feature = core.get(feature: NetworkInstrumentationFeature.self) else {
            throw ProgrammerError(description: "URLSession tracking must be enabled before enabling URLSessionInstrumentation using either RUM or Trace feature.")
        }

        try feature.bind(configuration: configuration)
    }

    /// Disables URLSession instrumentation.
    /// - Parameters:
    ///   - delegateClass: The delegate class to unbind.
    ///   - core: The instance of Datadog SDK to disable URLSession instrumentation in (global instance by default).
    public static func disable(delegateClass: URLSessionDataDelegate.Type, in core: DatadogCoreProtocol = CoreRegistry.default) {
        do {
            try disableOrThrow(delegateClass: delegateClass, in: core)
        } catch let error {
            consolePrint("\(error)", .error)

            if error is InternalError { // SDK error, send to telemetry
                core.telemetry.error(error)
            }
        }
    }

    internal static func disableOrThrow(delegateClass: URLSessionDataDelegate.Type, in core: DatadogCoreProtocol) throws {
        guard let feature = core.get(feature: NetworkInstrumentationFeature.self) else {
            throw ProgrammerError(description: "URLSession tracking must be enabled before enabling URLSessionInstrumentation using either RUM or Trace feature.")
        }

        feature.unbind(delegateClass: delegateClass)
    }
}

extension URLSessionInstrumentation {
    /// Configuration of URLSession instrumentation.
    public struct Configuration {
        /// The delegate class to be used to swizzle URLSessionTaskDelegate & URLSessionDataDelegate methods.
        public var delegateClass: URLSessionDataDelegate.Type

        /// Additional first party hosts to consider in the interception.
        public var firstPartyHostsTracing: FirstPartyHostsTracing?

        /// Configuration of URLSession instrumentation.
        /// - Parameters:
        ///   - delegate: The delegate class to be used to swizzle URLSessionTaskDelegate & URLSessionDataDelegate methods.
        ///   - firstPartyHostsTracing: Additional first party hosts to consider in the interception.
        public init(delegateClass: URLSessionDataDelegate.Type, firstPartyHostsTracing: FirstPartyHostsTracing? = nil) {
            self.delegateClass = delegateClass
            self.firstPartyHostsTracing = firstPartyHostsTracing
        }
    }

    /// Defines configuration for first-party hosts in distributed tracing.
    public enum FirstPartyHostsTracing {
        /// Trace the specified hosts using Datadog and W3C `tracecontext` tracing headers.
        ///
        /// - Parameters:
        ///   - hosts: The set of hosts to inject tracing headers. Note: Hosts must not include the "http(s)://" prefix.
        case trace(hosts: Set<String>)

        /// Trace given hosts with using custom tracing headers.
        ///
        /// - `hostsWithHeaders` - Dictionary of hosts and tracing header types to use. Note: Hosts must not include "http(s)://" prefix.
        case traceWithHeaders(hostsWithHeaders: [String: Set<TracingHeaderType>])
    }
}
