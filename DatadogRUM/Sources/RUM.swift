/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

/// An entry point to Datadog RUM feature.
public enum RUM {
    /// Enables Datadog RUM feature.
    ///
    /// After RUM is enabled, use `RUMMonitor.shared(in:)` to collect RUM events.
    ///
    /// - Parameters:
    ///   - configuration: Configuration of the feature.
    ///   - core: The instance of Datadog SDK to enable RUM in (global instance by default).
    public static func enable(
        with configuration: RUM.Configuration,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            try runOnMainThreadSync {
                try enableOrThrow(with: configuration, in: core)
            }
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }

    internal static func enableOrThrow(
        with configuration: RUM.Configuration,
        in core: DatadogCoreProtocol
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
            try RUM._internal.enableURLSessionTracking(with: urlSessionConfig, in: core)
        }

        if configuration.debugViews {
            consolePrint("⚠️ Overriding RUM debugging with DD_DEBUG_RUM launch argument", .warn)
            rum.monitor.debug = true
        }

        // Do initial work:
        rum.monitor.notifySDKInit()
    }
}

extension RUM {
    /// Attributes that can be added to RUM calls that have special properies in Datadog.
    public struct Attributes {
        /// Add a custom fingerprint to the RUM error.
        /// The value of this attribute must be a `String`.
        public static let errorFingerprint = "_dd.error.fingerprint"
    }
}

extension RUM: PlatformInterface {
    public var configuration: String {
  ""
    }
}
