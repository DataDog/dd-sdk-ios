/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// An entry point to Datadog Trace feature.
public enum Trace {
    /// Enables Datadog Trace feature.
    ///
    /// After Trace is enabled, use `Tracer.shared(in:)` to collect spans.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    ///   - core: The instance of Datadog SDK to enable Trace in (global instance by default).
    public static func enable(
        with configuration: Trace.Configuration = .init(), in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            try enableOrThrow(with: configuration, in: core)
        } catch let error {
            consolePrint("\(error)", .error)
       }
    }

    internal static func enableOrThrow(
        with configuration: Trace.Configuration, in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `Trace.enable(with:)`."
            )
        }

        // Register Trace feature:
        let trace = TraceFeature(in: core, configuration: configuration)
        try core.register(feature: trace)

        // If `URLSession` tracking is configured, register `URLSessionHandler` to enable distributed tracing:
        if let firstPartyHostsTracing = configuration.urlSessionTracking?.firstPartyHostsTracing {
            let firstPartyHosts: FirstPartyHosts
            let traceContextInjection: TraceContextInjection
            let tracingSampleRate: SampleRate

            switch firstPartyHostsTracing {
            case let .trace(hosts, sampleRate, injection):
                tracingSampleRate = sampleRate
                firstPartyHosts = FirstPartyHosts(hosts)
                traceContextInjection = injection
            case let .traceWithHeaders(hostsWithHeaders, sampleRate, injection):
                tracingSampleRate = sampleRate
                firstPartyHosts = FirstPartyHosts(hostsWithHeaders)
                traceContextInjection = injection
            }

            let urlSessionHandler = TracingURLSessionHandler(
                tracer: trace.tracer,
                contextReceiver: trace.contextReceiver,
                samplingRate: configuration.debugSDK ? 100 : tracingSampleRate,
                firstPartyHosts: firstPartyHosts,
                traceContextInjection: traceContextInjection
            )

            try core.register(urlSessionHandler: urlSessionHandler)
        }
    }
}
