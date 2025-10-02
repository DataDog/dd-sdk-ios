/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public enum Flags {
    public struct Configuration {
        /// Custom server URL for retrieving flag assignments.
        ///
        /// If not set, the SDK uses the default Datadog Flags endpoint for the configured site.
        ///
        /// Default: `nil`.
        public var customFlagsEndpoint: URL?

        /// Additional HTTP headers to attach to requests made to `customFlagsEndpoint`.
        ///
        /// Useful for authentication or routing when using your own Flags service. Ignored when using the default Datadog endpoint.
        ///
        /// Default: `nil`.
        public var customFlagsHeaders: [String: String]?

        /// Custom server url for sending Flags exposure data.
        ///
        /// Default: `nil`.
        public var customExposureEndpoint: URL?

        public init(
            customFlagsEndpoint: URL? = nil,
            customFlagsHeaders: [String: String]? = nil,
            customExposureEndpoint: URL? = nil
        ) {
            self.customFlagsEndpoint = customFlagsEndpoint
            self.customFlagsHeaders = customFlagsHeaders
            self.customExposureEndpoint = customExposureEndpoint
        }
    }

    /// Enables the Datadog Flags feature.
    ///
    /// - Parameters:
    ///   - configuration: Flags configuration options.
    ///   - core: The Datadog SDK instance to enable Flags in (defaults to the global core instance).
    public static func enable(
        with configuration: Flags.Configuration = .init(),
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
        with configuration: Flags.Configuration,
        in core: DatadogCoreProtocol
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `Flags.enable(with:)`."
            )
        }

        let featureScope = core.scope(for: FlagsFeature.self) // safe to obtain scope before feature registration; scope is lazily evaluated
        let feature = FlagsFeature(
            configuration: configuration,
            featureScope: featureScope
        )
        try core.register(feature: feature)
    }
}
