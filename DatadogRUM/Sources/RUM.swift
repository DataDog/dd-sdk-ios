/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// An entry point to Datadog RUM feature.
public struct RUM {
    /// Enables Datadog RUM feature.
    /// - Parameters:
    ///   - configuration: configuration of the feature
    ///   - core: an instance of Datadog SDK to enable the feture for (uses default instance if not set)
    public static func enable(
        with configuration: RUMConfiguration, in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            try enableOrThrow(with: configuration, in: core)
        } catch let error {
           consolePrint("\(error)")
       }
    }

    internal static func enableOrThrow(
        with configuration: RUMConfiguration, in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `RUM.enable(with:)`."
            )
        }

        let rum = try RUMFeature(in: core, configuration: configuration)
        try core.register(feature: rum)
    }
}
