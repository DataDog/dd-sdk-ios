/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An entry point to enable URLSession instrumentation.
public enum URLSessionInstrumentation {
    /// Enables metrics mode to capture detailed timing breakdowns for URLSession tasks.
    ///
    /// This method is optional. Automatic network tracking is already enabled by default when RUM or Trace is initialized with `urlSessionTracking` configuration.
    /// Metrics mode provides additional detailed timing information captured from `URLSessionTaskMetrics` (including DNS, Connection, SSL, First Byte, Download).
    ///
    /// Note: Metrics mode involves swizzling `URLSessionDataDelegate` methods to capture `URLSessionTaskMetrics`.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    ///   - core: The instance of Datadog SDK to enable URLSession instrumentation in (global instance by default).
    public static func trackMetrics(with configuration: URLSessionInstrumentation.Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) {
        do {
            try enableOrThrow(with: configuration, in: core)

            core.telemetry.debug(
                id: "URLSessionInstrumentation:trackMetrics",
                message: "URLSession metrics mode enabled"
            )
        } catch let error {
            consolePrint("\(error)", .error)

            if error is InternalError { // SDK error, send to telemetry
                core.telemetry.error(error)
            }
        }
    }

    /// Enables URLSession instrumentation.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    ///   - core: The instance of Datadog SDK to enable URLSession instrumentation in (global instance by default).
    @available(*, deprecated, renamed: "trackMetrics(with:in:)", message: "Use trackMetrics(with:in:) instead.")
    public static func enable(with configuration: URLSessionInstrumentation.Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) {
        do {
            try enableOrThrow(with: configuration, in: core)

            core.telemetry.debug(
                id: "URLSessionInstrumentation:enable",
                message: "URLSession metrics mode enabled (deprecated API)"
            )
        } catch let error {
            consolePrint("\(error)", .error)

            if error is InternalError { // SDK error, send to telemetry
                core.telemetry.error(error)
            }
        }
    }

    @_spi(Internal)
    public static func enableOrThrow(with configuration: URLSessionInstrumentation.Configuration?, in core: DatadogCoreProtocol) throws {
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
    /// Configuration for metrics mode.
    ///
    /// Metrics mode captures detailed timing breakdowns by swizzling delegate methods to access `URLSessionTaskMetrics`.
    public struct Configuration {
        /// The delegate class to be used to swizzle URLSessionTaskDelegate & URLSessionDataDelegate methods.
        ///
        /// This enables capturing `URLSessionTaskMetrics` for detailed timing information (DNS, SSL, TTFB, etc.)
        /// and response data via delegate methods.
        public var delegateClass: URLSessionDataDelegate.Type

        /// Additional first party hosts to consider in the interception.
        public var firstPartyHostsTracing: FirstPartyHostsTracing?

        /// Configuration for metrics mode.
        /// - Parameters:
        ///   - delegateClass: The delegate class to be used to swizzle URLSessionTaskDelegate & URLSessionDataDelegate methods.
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
