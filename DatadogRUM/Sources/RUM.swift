/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

/// An entry point to Datadog RUM feature.
public struct RUM {
    /// Enables Datadog RUM feature.
    ///
    /// After RUM is enabled, use `RUMMonitor.shared(in:)` to collect RUM events.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    ///   - core: The instance of Datadog SDK to enable RUM in (global instance by default).
    public static func enable(
        with configuration: RUM.Configuration, in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            try enableOrThrow(with: configuration, in: core)
        } catch let error {
           consolePrint("\(error)")
       }
    }

    internal static func enableOrThrow(
        with configuration: RUM.Configuration, in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `RUM.enable(with:)`."
            )
        }

        // Register RUM feature:
        let rum = try RUMFeature(in: core, configuration: configuration)
        try core.register(feature: rum)

        // If resource tracking is configured, register URLSessionHandler to enable network instrumentation:
        if let urlSessionConfig = configuration.urlSessionTracking {
            let distributedTracing: DistributedTracing?

            // If first party hosts are configured, enable distributed tracing:
            switch urlSessionConfig.firstPartyHostsTracing {
            case let .trace(hosts, sampleRate):
                distributedTracing = DistributedTracing(
                    sampler: Sampler(samplingRate: configuration.debugSDK ? 100 : sampleRate),
                    firstPartyHosts: FirstPartyHosts(hosts),
                    traceIDGenerator: configuration.traceIDGenerator
                )
            case let .traceWithHeaders(hostsWithHeaders, sampleRate):
                distributedTracing = DistributedTracing(
                    sampler: Sampler(samplingRate: configuration.debugSDK ? 100 : sampleRate),
                    firstPartyHosts: FirstPartyHosts(hostsWithHeaders),
                    traceIDGenerator: configuration.traceIDGenerator
                )
            case .none:
                distributedTracing = nil
            }

            let urlSessionHandler = URLSessionRUMResourcesHandler(
                dateProvider: configuration.dateProvider,
                rumAttributesProvider: urlSessionConfig.resourceAttributesProvider,
                distributedTracing: distributedTracing
            )

            // Connect URLSession instrumentation to RUM monitor:
            urlSessionHandler.publish(to: rum.monitor)
            try core.register(urlSessionHandler: urlSessionHandler)
        }

        if configuration.debugViews {
            consolePrint("⚠️ Overriding RUM debugging with DD_DEBUG_RUM launch argument")
            rum.monitor.debug = true
        }

        // Do initial work:
        rum.monitor.notifySDKInit()
    }
}
