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
            let lateConfig = RUM.Configuration.LateURLSessionTracking(
                from: urlSessionConfig,
                debugSDK: configuration.debugSDK,
                dateProvider: configuration.dateProvider,
                traceIDGenerator: configuration.traceIDGenerator
            )

            try RUM._internal.enableURLSessionTracking(with: lateConfig, in: core)
        }

        if configuration.debugViews {
            consolePrint("⚠️ Overriding RUM debugging with DD_DEBUG_RUM launch argument")
            rum.monitor.debug = true
        }

        // Do initial work:
        rum.monitor.notifySDKInit()
    }
}
