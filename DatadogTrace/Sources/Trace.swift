/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import OpenTelemetryApi

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
           consolePrint("\(error)")
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
            let distributedTraceSampler: Sampler
            let firstPartyHosts: FirstPartyHosts

            switch firstPartyHostsTracing {
            case let .trace(hosts, sampleRate):
                distributedTraceSampler = Sampler(samplingRate: configuration.debugSDK ? 100 : sampleRate)
                firstPartyHosts = FirstPartyHosts(hosts)
            case let .traceWithHeaders(hostsWithHeaders, sampleRate):
                distributedTraceSampler = Sampler(samplingRate: configuration.debugSDK ? 100 : sampleRate)
                firstPartyHosts = FirstPartyHosts(hostsWithHeaders)
            }

            let urlSessionHandler = TracingURLSessionHandler(
                tracer: trace.tracer,
                contextReceiver: trace.tracer.contextReceiver,
                tracingSampler: distributedTraceSampler,
                firstPartyHosts: firstPartyHosts
            )

            try core.register(urlSessionHandler: urlSessionHandler)
        }
    }
}
