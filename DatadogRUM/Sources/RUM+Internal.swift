/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2023-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension RUM: InternalExtended {}

/// NOTE: Methods in this extension are NOT considered part of the public of the Datadog SDK, and
/// may change or be removed in minor updates of the Datadog SDK.
extension InternalExtension where ExtendedType == RUM {
    /// Check whether `RUM` has been enabled for a specific SDK instance.
    ///
    /// - Parameters:
    ///    - in: the core to check
    ///
    /// - Returns: true if `RUM` has been enabled for the supplied core.
    public static func isEnabled(in core: DatadogCoreProtocol = CoreRegistry.default) -> Bool {
        return core.get(feature: RUMFeature.self) != nil
    }

    /// Enable URL session tracking after RUM has already been enabled. This method
    /// is only needed if the configuration of URL session tracking is not known at initialization time,
    /// or in the case of cross platform frameworks that do not initalize native URL session tracking.
    ///
    /// - Parameters:
    ///    - configuration: the configuration for URL session tracking
    ///    - in: the core to enable URL session in
    public static func enableURLSessionTracking(
        with configuration: RUM.Configuration.URLSessionTracking,
        in core: DatadogCoreProtocol = CoreRegistry.default) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK and RUM must be initialized before calling `RUM.enableUrlSessionTracking`."
            )
        }

        guard let rum = core.get(feature: RUMFeature.self) else {
            throw ProgrammerError(
                description: "RUM must be initialized before calling `RUM.enableUrlSessionTracking`."
            )
        }

        let distributedTracing: DistributedTracing?
        let rumConfiguration = rum.configuration

        // If first party hosts are configured, enable distributed tracing:
        switch configuration.firstPartyHostsTracing {
        case let .trace(hosts, sampleRate, traceContextInjection):
            distributedTracing = DistributedTracing(
                sampler: Sampler(samplingRate: rumConfiguration.debugSDK ? 100 : sampleRate),
                firstPartyHosts: FirstPartyHosts(hosts),
                traceIDGenerator: rumConfiguration.traceIDGenerator,
                spanIDGenerator: rumConfiguration.spanIDGenerator,
                traceContextInjection: traceContextInjection
            )
        case let .traceWithHeaders(hostsWithHeaders, sampleRate, traceContextInjection):
            distributedTracing = DistributedTracing(
                sampler: Sampler(samplingRate: rumConfiguration.debugSDK ? 100 : sampleRate),
                firstPartyHosts: FirstPartyHosts(hostsWithHeaders),
                traceIDGenerator: rumConfiguration.traceIDGenerator,
                spanIDGenerator: rumConfiguration.spanIDGenerator,
                traceContextInjection: traceContextInjection
            )
        case .none:
            distributedTracing = nil
        }

        let urlSessionHandler = URLSessionRUMResourcesHandler(
            dateProvider: rumConfiguration.dateProvider,
            rumAttributesProvider: configuration.resourceAttributesProvider,
            distributedTracing: distributedTracing
        )

        // Connect URLSession instrumentation to RUM monitor:
        urlSessionHandler.publish(to: rum.monitor)
        try core.register(urlSessionHandler: urlSessionHandler)
    }
}
